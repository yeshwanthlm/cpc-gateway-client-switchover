#!/bin/bash

# =============================================================================
# Confluent Cloud Gateway Demo - Deployment Script
# =============================================================================
# This script automates the complete deployment of:
# - AWS EKS Cluster
# - Confluent Cloud Kafka Clusters (AWS & GCP)
# - Confluent Gateway on Kubernetes
# - All necessary certificates and secrets
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed. Please install it first."
        exit 1
    fi
    print_success "$1 is installed"
}

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------

print_header "Pre-flight Checks"

# Check required commands
check_command terraform
check_command aws
check_command kubectl
check_command helm
check_command openssl
check_command keytool

# Check for .env file
if [ ! -f .env ]; then
    print_error ".env file not found!"
    print_info "Please copy .env.example to .env and fill in your configuration"
    print_info "  cp .env.example .env"
    print_info "  # Edit .env with your values"
    exit 1
fi

# Load environment variables
print_info "Loading configuration from .env file..."
export $(cat .env | grep -v '^#' | xargs)
print_success "Configuration loaded"

# Validate required variables
REQUIRED_VARS=(
    "AWS_REGION"
    "EKS_CLUSTER_NAME"
    "CONFLUENT_CLOUD_API_KEY"
    "CONFLUENT_CLOUD_API_SECRET"
    "GATEWAY_DOMAIN"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "Required variable $var is not set in .env file"
        exit 1
    fi
done
print_success "All required variables are set"

# Check AWS credentials
print_info "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured or invalid"
    exit 1
fi
print_success "AWS credentials are valid"

# -----------------------------------------------------------------------------
# Step 1: Deploy EKS Cluster
# -----------------------------------------------------------------------------

print_header "Step 1: Deploying EKS Cluster"

cd terraform

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
aws_region         = "${AWS_REGION}"
cluster_name       = "${EKS_CLUSTER_NAME}"
kubernetes_version = "${KUBERNETES_VERSION:-1.31}"
instance_type      = "${INSTANCE_TYPE:-t3.medium}"
EOF

print_info "Initializing Terraform..."
terraform init

print_info "Deploying EKS cluster (this may take 10-15 minutes)..."
terraform apply -auto-approve

print_success "EKS cluster deployed successfully"

# Configure kubectl
print_info "Configuring kubectl..."
aws eks update-kubeconfig --region ${AWS_REGION} --name ${EKS_CLUSTER_NAME}
print_success "kubectl configured"

# Verify cluster access
print_info "Verifying cluster access..."
kubectl get nodes
print_success "Cluster is accessible"

cd ..

# -----------------------------------------------------------------------------
# Step 2: Install Confluent Operator
# -----------------------------------------------------------------------------

print_header "Step 2: Installing Confluent Operator"

print_info "Adding Confluent Helm repository..."
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

print_info "Creating confluent namespace..."
kubectl create namespace confluent

print_info "Installing Confluent for Kubernetes operator..."
helm upgrade --install confluent-operator \
    confluentinc/confluent-for-kubernetes \
    --namespace confluent \
    --wait

print_success "Confluent operator installed successfully"

# Wait for operator to be ready
print_info "Waiting for operator pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=confluent-operator -n confluent --timeout=300s
print_success "Confluent operator is ready"

# -----------------------------------------------------------------------------
# Step 3: Deploy Confluent Cloud Clusters with ACLs
# -----------------------------------------------------------------------------

print_header "Step 3: Deploying Confluent Cloud Clusters"

cd confluent-terraform

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
confluent_cloud_api_key    = "${CONFLUENT_CLOUD_API_KEY}"
confluent_cloud_api_secret = "${CONFLUENT_CLOUD_API_SECRET}"
environment_name           = "${CONFLUENT_ENVIRONMENT_NAME:-cpc-gateway-demo}"
aws_cluster_name           = "${AWS_KAFKA_CLUSTER_NAME:-aws-us-east-1-cluster}"
gcp_cluster_name           = "${GCP_KAFKA_CLUSTER_NAME:-gcp-us-west-cluster}"
availability               = "${KAFKA_AVAILABILITY:-SINGLE_ZONE}"
EOF

print_info "Initializing Terraform..."
terraform init

print_info "Deploying Confluent Cloud clusters with ACLs (this may take 5-10 minutes)..."
print_warning "Note: ACL creation requires your Cloud API key to have OrganizationAdmin role"
print_info "If ACL creation fails, see confluent-terraform/BOOTSTRAP.md"

# Try to apply with ACLs
if terraform apply -auto-approve; then
    print_success "Confluent Cloud clusters and ACLs deployed successfully"
else
    print_error "Terraform apply failed"
    print_warning "This is likely due to insufficient Cloud API key permissions"
    print_info "To fix:"
    print_info "  1. Go to: https://confluent.cloud/settings/api-keys"
    print_info "  2. Find your Cloud API key: ${CONFLUENT_CLOUD_API_KEY}"
    print_info "  3. Add role binding: OrganizationAdmin"
    print_info "  4. Run: cd confluent-terraform && terraform apply"
    print_info "  5. Then resume: ./deploy.sh --skip-terraform"
    exit 1
fi

# Get cluster endpoints and API keys
print_info "Retrieving cluster information..."
AWS_CLUSTER_ENDPOINT=$(terraform output -raw aws_cluster_bootstrap_endpoint | sed 's/SASL_SSL:\/\///')
GCP_CLUSTER_ENDPOINT=$(terraform output -raw gcp_cluster_bootstrap_endpoint | sed 's/SASL_SSL:\/\///')
AWS_CLUSTER_API_KEY=$(terraform output -raw aws_cluster_api_key)
AWS_CLUSTER_API_SECRET=$(terraform output -raw aws_cluster_api_secret)
GCP_CLUSTER_API_KEY=$(terraform output -raw gcp_cluster_api_key)
GCP_CLUSTER_API_SECRET=$(terraform output -raw gcp_cluster_api_secret)
AWS_SERVICE_ACCOUNT_ID=$(terraform output -raw aws_service_account_id)
GCP_SERVICE_ACCOUNT_ID=$(terraform output -raw gcp_service_account_id)

print_success "Cluster information retrieved"

cd ..

# -----------------------------------------------------------------------------
# Step 4-6: Create All Certificates and Secrets using Makefile
# -----------------------------------------------------------------------------

print_header "Steps 4-6: Creating Certificates and Secrets"

# Update .env with cluster information from Terraform
print_info "Updating .env file with cluster information..."

# Remove old entries if they exist
grep -v "^AWS_CLUSTER_ENDPOINT=" .env > .env.tmp 2>/dev/null || cp .env .env.tmp
grep -v "^GCP_CLUSTER_ENDPOINT=" .env.tmp > .env.tmp2 2>/dev/null || cp .env.tmp .env.tmp2
grep -v "^AWS_CLUSTER_API_KEY=" .env.tmp2 > .env.tmp3 2>/dev/null || cp .env.tmp2 .env.tmp3
grep -v "^AWS_CLUSTER_API_SECRET=" .env.tmp3 > .env.tmp4 2>/dev/null || cp .env.tmp3 .env.tmp4
grep -v "^GCP_CLUSTER_API_KEY=" .env.tmp4 > .env.tmp5 2>/dev/null || cp .env.tmp4 .env.tmp5
grep -v "^GCP_CLUSTER_API_SECRET=" .env.tmp5 > .env.tmp6 2>/dev/null || cp .env.tmp5 .env.tmp6
grep -v "^AWS_SERVICE_ACCOUNT_ID=" .env.tmp6 > .env.tmp7 2>/dev/null || cp .env.tmp6 .env.tmp7
grep -v "^GCP_SERVICE_ACCOUNT_ID=" .env.tmp7 > .env 2>/dev/null || cp .env.tmp7 .env
rm -f .env.tmp .env.tmp2 .env.tmp3 .env.tmp4 .env.tmp5 .env.tmp6 .env.tmp7

# Append new values
cat >> .env <<EOF

# Auto-populated from Terraform (confluent-terraform/)
AWS_CLUSTER_ENDPOINT=${AWS_CLUSTER_ENDPOINT}
GCP_CLUSTER_ENDPOINT=${GCP_CLUSTER_ENDPOINT}
AWS_CLUSTER_API_KEY=${AWS_CLUSTER_API_KEY}
AWS_CLUSTER_API_SECRET=${AWS_CLUSTER_API_SECRET}
GCP_CLUSTER_API_KEY=${GCP_CLUSTER_API_KEY}
GCP_CLUSTER_API_SECRET=${GCP_CLUSTER_API_SECRET}
AWS_SERVICE_ACCOUNT_ID=${AWS_SERVICE_ACCOUNT_ID}
GCP_SERVICE_ACCOUNT_ID=${GCP_SERVICE_ACCOUNT_ID}
EOF

print_success ".env file updated with cluster credentials"

print_info "Using Makefile to automate certificate creation..."
print_info "This will:"
echo "  - Download and convert Confluent Cloud certificates"
echo "  - Generate gateway TLS certificates"
echo "  - Create client configuration files"
echo "  - Create all Kubernetes secrets"
echo ""

# Run make to create all certificates and secrets
make certs
make k8s-secrets

print_success "All certificates and secrets created successfully"

# Verify certificates
print_info "Verifying certificates..."
make verify-certs

# -----------------------------------------------------------------------------
# Step 7: Update and Deploy Gateway Configuration
# -----------------------------------------------------------------------------

print_header "Step 7: Deploying Confluent Gateway"

# Update gateway.yaml with actual cluster endpoints
print_info "Updating gateway configuration with cluster endpoints..."

# This will be done manually or you can use sed to update the YAML file
# For now, we'll just deploy the gateway as-is and let the user update it

print_warning "Please update kubernetes-resources/gateway.yaml with your cluster endpoints:"
print_info "  - AWS Cluster: ${AWS_CLUSTER_ENDPOINT}"
print_info "  - GCP Cluster: ${GCP_CLUSTER_ENDPOINT}"
print_info ""
print_info "Press Enter when ready to continue..."
read

print_info "Deploying gateway..."
kubectl apply -f kubernetes-resources/gateway.yaml -n confluent

print_info "Waiting for gateway to be ready..."
kubectl wait --for=condition=Ready pod -l app=confluent-gateway --timeout=600s -n confluent

print_success "Gateway deployed successfully"

# -----------------------------------------------------------------------------
# Step 8: Deploy Kafka Tools Pod
# -----------------------------------------------------------------------------

print_header "Step 8: Deploying Kafka Tools Pod"

# Get LoadBalancer hostname
print_info "Getting LoadBalancer hostname..."
sleep 30  # Wait for LB to be provisioned

LB_HOST=$(kubectl get svc confluent-gateway-bootstrap-lb -n confluent \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$LB_HOST" ]; then
    print_warning "LoadBalancer hostname not available yet. You may need to wait and update kafka-tools.yaml manually."
else
    print_info "LoadBalancer hostname: ${LB_HOST}"
    print_info "Resolving to IP addresses..."
    nslookup ${LB_HOST} || true
fi

print_warning "Please update kubernetes-resources/kafka-tools.yaml with LoadBalancer IPs in the hostAliases section"
print_info "Press Enter when ready to continue..."
read

print_info "Deploying kafka-tools pod..."
kubectl apply -f kubernetes-resources/kafka-tools.yaml -n confluent

kubectl wait --for=condition=Ready pod/kafka-tools --timeout=120s -n confluent

print_success "Kafka tools pod deployed successfully"

# -----------------------------------------------------------------------------
# Deployment Complete
# -----------------------------------------------------------------------------

print_header "Deployment Complete!"

print_success "All resources have been deployed successfully!"
echo ""
print_info "Summary:"
echo "  - EKS Cluster: ${EKS_CLUSTER_NAME} (${AWS_REGION})"
echo "  - AWS Kafka Cluster: ${AWS_CLUSTER_ENDPOINT}"
echo "    • Service Account: ${AWS_SERVICE_ACCOUNT_ID}"
echo "    • API Key: ${AWS_CLUSTER_API_KEY}"
echo "  - GCP Kafka Cluster: ${GCP_CLUSTER_ENDPOINT}"
echo "    • Service Account: ${GCP_SERVICE_ACCOUNT_ID}"
echo "    • API Key: ${GCP_CLUSTER_API_KEY}"
echo "  - Gateway Domain: ${GATEWAY_DOMAIN}"
echo "  - LoadBalancer: ${LB_HOST}"
echo ""
print_success "ACLs and Permissions:"
echo "  ✓ Role bindings created (CloudClusterAdmin)"
echo "  ✓ ACLs created (CREATE, WRITE, READ, DESCRIBE for topics)"
echo "  ✓ Consumer group permissions granted"
echo ""
print_info "Next Steps:"
echo ""
echo "  1. Update your DNS (Route53) to point ${GATEWAY_DOMAIN} to the LoadBalancer"
echo ""
echo "  2. Test topic listing:"
echo "     kubectl exec kafka-tools -n confluent -- kafka-topics \\"
echo "       --bootstrap-server ${GATEWAY_DOMAIN}:9092 \\"
echo "       --command-config /etc/kafka/client-primary/client-primary.properties \\"
echo "       --list"
echo ""
echo "  3. Test message production:"
echo "     kubectl exec kafka-tools -n confluent -- bash -c 'echo -e \"test 1\\ntest 2\\ntest 3\" | kafka-console-producer \\"
echo "       --bootstrap-server ${GATEWAY_DOMAIN}:9092 \\"
echo "       --producer.config /etc/kafka/client-primary/client-primary.properties \\"
echo "       --topic test_topic'"
echo ""
echo "  4. To switch between clusters, update kubernetes-resources/gateway.yaml"
echo "     and run: kubectl apply -f kubernetes-resources/gateway.yaml -n confluent"
echo ""
print_info "Credentials saved to: .env"
print_info "For more details, see README.md"
echo ""
