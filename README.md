# Confluent Cloud Gateway Setup for Cluster Switchover

This guide demonstrates how to set up Confluent Gateway on EKS to enable seamless switchover between Confluent Cloud clusters (Primary and DR).

## Architecture Diagram:
<img width="1540" height="870" alt="image (2)" src="https://github.com/user-attachments/assets/f0721e47-cf64-4e8d-aced-060d30f414f2" />


## 🚀 Quick Start - Automated Deployment

**New!** This project now includes complete automation for deployment and cleanup:

```bash
# 1. Configure
cp .env.example .env
# Edit .env with your AWS & Confluent Cloud credentials

# 2. Deploy everything (~20 minutes)
./deploy.sh

# 3. Destroy everything when done (~15 minutes)
./destroy.sh
```

**👉 For automated deployment, see [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)**

**📖 Documentation:**
- **[DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)** - Automated deployment guide (recommended)
- **[MAKEFILE-GUIDE.md](MAKEFILE-GUIDE.md)** - Certificate automation reference
- **[AUTOMATION-SUMMARY.md](AUTOMATION-SUMMARY.md)** - Quick overview of automation
- **This README** - Detailed manual setup instructions (below)

---

## Architecture Overview

- **Primary Cluster**: Confluent Cloud on AWS US-East-1
- **DR Cluster**: Confluent Cloud on GCP US-West1
- **Gateway Endpoint**: `kafka.cpc.yesh.com:9092` (your custom domain)
- **EKS Cluster**: Running in AWS us-west-2
- **Switchover**: Update gateway configuration to switch between clusters

**Note**: The automated deployment scripts will create clusters dynamically. Update cluster endpoints, domain names, and LoadBalancer IPs in the YAML files to match your actual deployment.

## Prerequisites

### For Automated Deployment (Recommended)

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3.0
- [OpenSSL](https://www.openssl.org/)
- Java KeyTool (part of JDK)
- Confluent Cloud API keys ([Get them here](https://confluent.cloud/settings/api-keys))

### For Manual Setup (This Guide)

- EKS cluster with Confluent for Kubernetes operator installed
- Two Confluent Cloud clusters (Primary and DR)
- API keys for both clusters
- Route53 hosted zone for your domain (optional)
- kubectl and AWS CLI configured

---

## Manual Setup Instructions

**Note:** If you're using the automated deployment scripts, you can skip this section. The instructions below are for manual step-by-step setup or for understanding the details of each component.

## Step 0: Have the K8S cluster ready and run the following:

```bash
# make sure to install image tag 0.
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
kubectl create namespace confluent
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes -n confluent
kubectl get pods -n confluent
```

## Certificate Management (Automated Option)

**💡 Quick Certificate Setup:** You can automate all certificate operations using the Makefile:

```bash
# Create all certificates and secrets in one command
make certs k8s-secrets

# Or use individual targets
make confluent-certs    # Download and convert Confluent Cloud certificates
make gateway-certs      # Generate gateway TLS certificates
make client-configs     # Create client configuration files
make k8s-secrets        # Create all Kubernetes secrets
make verify-certs       # Verify all certificates are valid

# See all available commands
make help
```

**For details, see [MAKEFILE-GUIDE.md](MAKEFILE-GUIDE.md)**

For manual certificate setup, follow Steps 1-6 below:

---

## Step 1: Download Confluent Cloud Certificates

Create truststore files for both clusters:

```bash
cd certs

# Download certificates for primary cluster
./download-cc-certs.sh pkc-XXXXXX.us-east-1.aws.confluent.cloud:9092

# Download certificates for DR cluster
./download-cc-certs.sh pkc-XXXXXX.us-west1.gcp.confluent.cloud:9092
```

This creates truststore files in `ssl/<cluster-name>/` directories.

**Or use Makefile:** `make confluent-certs`

## Step 2: Convert Truststores and Create Kubernetes Secrets

**IMPORTANT**: The download-cc-certs.sh script creates PKCS12 format truststores, but the Gateway operator requires JKS format. Also, the password must be in Java properties format.

### Convert PKCS12 to JKS

```bash
# Convert Primary Cluster Truststore (AWS)
keytool -importkeystore \
  -srckeystore ./certs/ssl/pkc-oxqxx9.us-east-1.aws.confluent.cloud/truststore.p12 \
  -srcstoretype PKCS12 \
  -srcstorepass confluent \
  -destkeystore /tmp/cc-primary-truststore.jks \
  -deststoretype JKS \
  -deststorepass confluent \
  -noprompt

# Convert DR Cluster Truststore (GCP)
keytool -importkeystore \
  -srckeystore ./certs/ssl/pkc-lgk0v.us-west1.gcp.confluent.cloud/truststore.p12 \
  -srcstoretype PKCS12 \
  -srcstorepass confluent \
  -destkeystore /tmp/cc-dr-truststore.jks \
  -deststoretype JKS \
  -deststorepass confluent \
  -noprompt

# Verify the conversions
keytool -list -keystore /tmp/cc-primary-truststore.jks -storepass confluent
keytool -list -keystore /tmp/cc-dr-truststore.jks -storepass confluent
```

### Create Password File in Properties Format

**CRITICAL**: The password file must be in Java properties format (`key=value`), not plain text.

```bash
echo "jksPassword=confluent" > /tmp/jksPassword.txt
```

### Create Kubernetes Secrets

```bash
# Primary cluster TLS secret
kubectl -n confluent create secret generic cc-primary-tls \
  --from-file=truststore.jks=/tmp/cc-primary-truststore.jks \
  --from-file=jksPassword.txt=/tmp/jksPassword.txt

# DR cluster TLS secret
kubectl -n confluent create secret generic cc-dr-tls \
  --from-file=truststore.jks=/tmp/cc-dr-truststore.jks \
  --from-file=jksPassword.txt=/tmp/jksPassword.txt
```

## Step 3: Create Gateway TLS Certificate

Generate a self-signed certificate for the gateway:

```bash
# Generate CA key and certificate
openssl genrsa -out ca-key.pem 2048
openssl req -new -x509 -key ca-key.pem -out cacerts.pem -days 365 \
  -subj "/C=US/ST=CA/L=Mountain View/O=Confluent/OU=Engineering/CN=Gateway Test CA"

# Create SAN configuration
cat > gateway-san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = Mountain View
O = Confluent
OU = Engineering
CN = kafka.cpc.yesh.com

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = kafka.cpc.yesh.com
DNS.2 = *.kafka.cpc.yesh.com
EOF

# Generate gateway certificate
openssl genrsa -out gateway-key.pem 2048
openssl req -new -key gateway-key.pem -out gateway.csr -config gateway-san.cnf
openssl x509 -req -in gateway.csr -CA cacerts.pem -CAkey ca-key.pem \
  -CAcreateserial -out gateway-cert.pem -days 365 -extensions v3_req \
  -extfile gateway-san.cnf

# Create fullchain
cat gateway-cert.pem cacerts.pem > fullchain.pem

# Create Kubernetes secret
kubectl create secret generic gateway-tls -n confluent \
  --from-file=fullchain.pem=fullchain.pem \
  --from-file=privkey.pem=gateway-key.pem \
  --from-file=cacerts.pem=cacerts.pem
```

## Step 4: Create Gateway Truststore Secret

Create a JKS truststore from the gateway CA certificate for client applications:

```bash
# Extract the gateway CA certificate
kubectl get secret gateway-tls -n confluent -o jsonpath='{.data.cacerts\.pem}' | base64 -d > /tmp/gateway-ca.pem

# Create JKS truststore from the CA certificate
keytool -import -trustcacerts -alias gateway-ca \
  -file /tmp/gateway-ca.pem \
  -keystore /tmp/gateway-truststore.jks \
  -storepass clienttrustpass \
  -noprompt

# Create Kubernetes secret with the truststore
kubectl create secret generic gateway-truststore -n confluent \
  --from-file=truststore.jks=/tmp/gateway-truststore.jks \
  --from-literal=password=clienttrustpass
```

**Note**: This truststore is used by client applications to trust the gateway's TLS certificate.

## Step 5: Create Client Configuration Files

**IMPORTANT**: Use **cluster-specific API keys**, not global/cloud API keys. Create separate API keys for each cluster in the Confluent Cloud UI.

Create client properties for both clusters:

**clients/client-primary.properties:**
```properties
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<PRIMARY_CLUSTER_API_KEY>" password="<PRIMARY_CLUSTER_API_SECRET>";
ssl.truststore.location=/etc/kafka/tls/truststore.jks
ssl.truststore.password=clienttrustpass
ssl.endpoint.identification.algorithm=
```

**clients/client-dr.properties:**
```properties
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<DR_CLUSTER_API_KEY>" password="<DR_CLUSTER_API_SECRET>";
ssl.truststore.location=/etc/kafka/tls/truststore.jks
ssl.truststore.password=clienttrustpass
ssl.endpoint.identification.algorithm=
```

Create secrets:

```bash
kubectl -n confluent create secret generic client-primary \
  --from-file=client-primary.properties=./clients/client-primary.properties

kubectl -n confluent create secret generic client-dr \
  --from-file=client-dr.properties=./clients/client-dr.properties
```

## Step 6: Deploy Confluent Gateway

Apply the gateway configuration:

```bash
kubectl apply -f kubernetes-resources/gateway.yaml -n confluent
```

Wait for the gateway to be ready:

```bash
kubectl wait --for=condition=Ready pod -l app=confluent-gateway --timeout=600s -n confluent
```

## Step 7: Configure DNS

Get the LoadBalancer hostname:

```bash
kubectl get svc -n confluent confluent-gateway-bootstrap-lb \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Create a CNAME record in Route53:

```bash
Update route53-update-gateway.json with your LoadBalancer hostname
```

**Note**: Ensure your domain's nameservers are pointing to Route53 nameservers.

## Step 8: Deploy Kafka Tools Pod for Testing

**IMPORTANT**: Update the kafka-tools.yaml with LoadBalancer IPs before deploying.

### Get LoadBalancer IPs

```bash
# Get LoadBalancer hostname
LB_HOST=$(kubectl get svc confluent-gateway-bootstrap-lb -n confluent \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Resolve to IP addresses
nslookup $LB_HOST
```

### Update kafka-tools.yaml

Edit `kubernetes-resources/kafka-tools.yaml` and update the `hostAliases` section with the resolved IPs:

```yaml
hostAliases:
  - ip: "<LOADBALANCER_IP_1>"
    hostnames:
      - "kafka.cpc.yesh.com"
  - ip: "<LOADBALANCER_IP_2>"
    hostnames:
      - "kafka.cpc.yesh.com"
```

### Deploy the Pod

```bash
kubectl apply -f kubernetes-resources/kafka-tools.yaml -n confluent
kubectl wait --for=condition=Ready pod/kafka-tools --timeout=120s -n confluent
```

## Step 9: Verify Gateway Connectivity and Test

### Verify Gateway is Routing to the Correct Cluster

```bash
# Check which cluster gateway is routing to
kubectl get gateway confluent-gateway -n confluent -o yaml | grep -A5 "streamingDomain:"

# Verify broker connectivity (check the rack ID to identify cluster)
kubectl exec kafka-tools -n confluent -- kafka-broker-api-versions \
  --bootstrap-server kafka.cpc.yesh.com:9092 \
  --command-config /etc/kafka/client-dr/client-dr.properties 2>&1 | head -5
# Look for rack: "usw1-a" (GCP us-west1) or "use1-az1" (AWS us-east-1)
```

### Test Producing and Consuming Messages

```bash
# List existing topics
kubectl exec kafka-tools -n confluent -- kafka-topics \
  --bootstrap-server kafka.cpc.yesh.com:9092 \
  --command-config /etc/kafka/client-dr/client-dr.properties \
  --list

# Produce messages to DR cluster
kubectl exec kafka-tools -n confluent -- bash -c 'echo -e "test message 1\ntest message 2\ntest message 3" | kafka-console-producer \
  --bootstrap-server kafka.cpc.yesh.com:9092 \
  --producer.config /etc/kafka/client-dr/client-dr.properties \
  --topic test_topic'

# Consume messages from DR cluster
kubectl exec kafka-tools -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka.cpc.yesh.com:9092 \
  --consumer.config /etc/kafka/client-dr/client-dr.properties \
  --topic test_topic \
  --from-beginning \
  --max-messages 10 \
  --timeout-ms 10000
```

## Step 10: Switch to Primary Cluster

Update the gateway configuration to route to Primary:

Edit `kubernetes-resources/gateway.yaml` and change the `streamingDomain` section (lines 50-52):

```yaml
streamingDomain:
  name: cc-primary              # Changed from cc-dr
  bootstrapServerId: CC_PRIMARY  # Changed from CC_DR
```

Apply the changes:

```bash
kubectl apply -f kubernetes-resources/gateway.yaml -n confluent

# Restart gateway pods to apply changes
kubectl delete pod -n confluent -l app=confluent-gateway
kubectl wait --for=condition=Ready pod -l app=confluent-gateway --timeout=120s -n confluent
```

## Step 11: Test Primary Cluster Connection

```bash
# Verify routing to Primary cluster (rack should show "use1-az1")
kubectl exec kafka-tools -n confluent -- kafka-broker-api-versions \
  --bootstrap-server kafka.cpc.yesh.com:9092 \
  --command-config /etc/kafka/client-primary/client-primary.properties 2>&1 | head -5

# Produce messages to Primary cluster
kubectl exec kafka-tools -n confluent -- bash -c 'echo -e "primary test 1\nprimary test 2\nprimary test 3" | kafka-console-producer \
  --bootstrap-server kafka.cpc.yesh.com:9092 \
  --producer.config /etc/kafka/client-primary/client-primary.properties \
  --topic test_topic'

# Consume messages from Primary cluster
kubectl exec kafka-tools -n confluent -- kafka-console-consumer \
  --bootstrap-server kafka.cpc.yesh.com:9092 \
  --consumer.config /etc/kafka/client-primary/client-primary.properties \
  --topic test_topic \
  --from-beginning \
  --max-messages 10 \
  --timeout-ms 10000
```

## Cluster Switchover Process

To switch between clusters:

1. Update the gateway configuration (`streamingDomain` section)
2. Apply the configuration: `kubectl apply -f kubernetes-resources/gateway.yaml -n confluent`
3. Restart gateway pods: `kubectl delete pod -n confluent -l app=confluent-gateway`
4. Clients automatically reconnect to the new cluster through the same endpoint

## Troubleshooting

### Issue 1: Gateway Pod CrashLoopBackOff - Invalid Password Format

**Error**: `invalid jksPassword secret data, use format jksPassword=<password>`

**Solution**: Password file must be in properties format:
```bash
echo "jksPassword=confluent" > /tmp/jksPassword.txt
# NOT just: echo "confluent" > /tmp/jksPassword.txt
```

### Issue 2: Gateway Pod CrashLoopBackOff - Keystore Password Incorrect

**Error**: `keystore password was incorrect` or `Keystore was tampered with`

**Root Cause**: Gateway expects JKS format, but download-cc-certs.sh creates PKCS12.

**Solution**: Convert truststores from PKCS12 to JKS:
```bash
keytool -importkeystore \
  -srckeystore ./certs/ssl/<cluster>/truststore.p12 \
  -srcstoretype PKCS12 \
  -srcstorepass confluent \
  -destkeystore /tmp/truststore.jks \
  -deststoretype JKS \
  -deststorepass confluent \
  -noprompt
```

### Issue 3: SSL Handshake Failed - Key Usage Error

**Error**: `javax.net.ssl.SSLHandshakeException: KeyUsage does not allow digital signatures`

**Root Cause**: Gateway certificate missing "Digital Signature" in Key Usage extension.

**Solution**: Regenerate certificate with correct keyUsage in gateway-san.cnf:
```ini
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
# NOT just: keyUsage = keyEncipherment, dataEncipherment
```

### Issue 4: Authentication Failed

**Error**: `Authentication failed` or `SSL handshake failed authentication`

**Root Cause**: Using global/cloud API keys instead of cluster-specific API keys.

**Solution**: 
1. Create cluster-specific API keys in Confluent Cloud UI for each cluster
2. Update client-primary.properties and client-dr.properties
3. Recreate the secrets:
```bash
kubectl delete secret client-primary client-dr -n confluent
kubectl create secret generic client-primary \
  --from-file=client-primary.properties=./clients/client-primary.properties -n confluent
kubectl create secret generic client-dr \
  --from-file=client-dr.properties=./clients/client-dr.properties -n confluent
```

### Issue 5: DNS Not Resolving

If DNS isn't resolving, verify:
- Route53 record exists: `aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID>`
- Domain nameservers point to Route53
- DNS propagation (can take up to 48 hours)
- Use `nslookup kafka.cpc.yesh.com` to verify

### Issue 6: Connection Timeout

**Error**: Cannot connect to kafka.cpc.yesh.com:9092

**Solutions**:
1. Check LoadBalancer is active:
   ```bash
   kubectl get svc confluent-gateway-bootstrap-lb -n confluent
   ```
2. Verify hostAliases in kafka-tools pod has correct LoadBalancer IPs
3. Try using LoadBalancer hostname directly instead of DNS name

### Debugging Commands

```bash
# View gateway logs
kubectl logs -n confluent -l app=confluent-gateway --tail=100

# Check gateway status
kubectl get gateway -n confluent

# Describe gateway resource
kubectl describe gateway confluent-gateway -n confluent

# Verify which cluster is active
kubectl get gateway confluent-gateway -n confluent -o yaml | grep -A5 "streamingDomain:"

# Check secrets format
kubectl get secret cc-primary-tls -n confluent -o yaml
```

## File Structure

```
.
├── README.md
├── certs/
│   ├── download-cc-certs.sh
│   └── ssl/
├── clients/
│   ├── client-primary.properties
│   └── client-dr.properties
├── kubernetes-resources/
│   ├── gateway.yaml
│   └── kafka-tools.yaml
```

## Key Configuration Details

### Gateway Configuration

- **Streaming Domains**: Define both primary and DR clusters
- **Routes**: Configure the endpoint and active streaming domain
- **Security**: Passthrough authentication (client credentials passed to backend cluster)
- **TLS**: Separate TLS configuration for client-to-gateway and gateway-to-cluster

### Port Mapping

The gateway uses port-based broker identification:
- Port 9092: Bootstrap/initial connection
- Ports 9093-9098+: Individual broker connections

All traffic goes through the LoadBalancer on different ports.

## Production Considerations

1. **DNS**: Use proper DNS with low TTL for faster switchover
2. **Certificates**: Use certificates from a trusted CA
3. **Monitoring**: Monitor gateway metrics and logs
4. **Testing**: Regularly test switchover procedures
5. **Automation**: Automate switchover process with scripts/operators
6. **Client Configuration**: Ensure clients have proper retry and timeout settings

## Resources

- [Confluent Gateway Documentation](https://docs.confluent.io/platform/current/multi-dc-deployments/cluster-linking/index.html)
- [Confluent for Kubernetes](https://docs.confluent.io/operator/current/overview.html)

---

## Summary: Manual vs Automated Setup

This README provides detailed manual setup instructions for those who want to understand each component or customize the deployment. However, **for the fastest setup**, use the automated scripts:

### Automated Setup (Recommended)
✅ **One command deployment:** `./deploy.sh`  
✅ **One command cleanup:** `./destroy.sh`  
✅ **Automated certificates:** `make certs k8s-secrets`  
✅ **Total time:** ~20 minutes  
✅ **Documentation:** [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)

### Manual Setup (This Guide)
📖 **Step-by-step understanding** of each component  
📖 **Customization flexibility** for specific requirements  
📖 **Learning resource** for Confluent Gateway internals  
📖 **Time required:** ~1-2 hours  

### Choose Your Path

| Use Case | Recommended Approach |
|----------|---------------------|
| **Quick demo/POC** | Automated (`./deploy.sh`) |
| **Learning Confluent Gateway** | Manual (this README) + Automation |
| **Production deployment** | Manual with customizations |
| **Team collaboration** | Automated (push to GitHub) |
| **Cost optimization** | Automated (easy destroy/redeploy) |
| **Certificate management** | Makefile (`make help`) |

### All Documentation Files

- **[README.md](README.md)** (this file) - Detailed manual setup
- **[DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)** - Automated deployment guide
- **[MAKEFILE-GUIDE.md](MAKEFILE-GUIDE.md)** - Certificate automation reference  
- **[AUTOMATION-SUMMARY.md](AUTOMATION-SUMMARY.md)** - Quick overview
- **[.env.example](.env.example)** - Configuration template

## Quick Command Reference

```bash
# Automated Deployment
./deploy.sh                    # Deploy everything
./destroy.sh                   # Destroy everything

# Certificate Management
make certs                     # Create all certificates
make k8s-secrets               # Create Kubernetes secrets
make verify-certs              # Verify certificates
make clean                     # Clean up certificates

# Kubernetes Operations
kubectl get pods -n confluent  # Check pod status
kubectl logs -n confluent -l app=confluent-gateway  # Gateway logs
kubectl exec kafka-tools -n confluent -- bash  # Interactive shell

# Testing
kubectl exec kafka-tools -n confluent -- kafka-topics --list \
  --bootstrap-server kafka.cpc.example.com:9092 \
  --command-config /etc/kafka/client-dr/client-dr.properties
```

## Support & Contributing

- **Issues:** Open an issue on GitHub
- **Questions:** See troubleshooting sections in each guide
- **Contributions:** PRs welcome!

---

**Happy Confluent Gateway testing! 🚀**
