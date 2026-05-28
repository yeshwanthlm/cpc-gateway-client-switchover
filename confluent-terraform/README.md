# Confluent Cloud Terraform Configuration

This Terraform configuration creates two Confluent Cloud Kafka clusters:
- **AWS Cluster**: Located in `us-east-1` region
- **GCP Cluster**: Located in `us-west1` region

Both clusters are created in the same Confluent Cloud environment with their own service accounts and API keys.

## Prerequisites

1. **Confluent Cloud Account**: Sign up at https://confluent.cloud
2. **Cloud API Key and Secret**: 
   - Navigate to https://confluent.cloud/settings/api-keys
   - Click "Add key" and select "Granular access" or "Cloud resource management"
   - Save the API Key and Secret securely
3. **Terraform**: Install from https://www.terraform.io/downloads

## Setup Instructions

### 1. Configure Credentials

Create a `terraform.tfvars` file from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and add your Confluent Cloud credentials:

```hcl
confluent_cloud_api_key    = "YOUR_CLOUD_API_KEY"
confluent_cloud_api_secret = "YOUR_CLOUD_API_SECRET"
```

**Important**: Never commit `terraform.tfvars` to version control. It's already in `.gitignore`.

### 2. Initialize Terraform

```bash
terraform init
```

This will download the required Confluent provider.

### 3. Review the Plan

```bash
terraform plan
```

This will show you what resources will be created:
- 1 Confluent Cloud Environment
- 2 Kafka Clusters (AWS and GCP)
- 2 Service Accounts
- 2 API Keys

### 4. Apply the Configuration

```bash
terraform apply
```

Type `yes` when prompted to create the resources.

**Note**: Cluster creation typically takes 5-10 minutes.

## What Gets Created

### Environment
- **Name**: `cpc-gateway-demo` (customizable in `terraform.tfvars`)
- Contains both Kafka clusters

### AWS Kafka Cluster
- **Region**: us-east-1
- **Cloud Provider**: AWS
- **Type**: Basic cluster (single-zone by default)
- **Service Account**: Created automatically with manager permissions
- **API Key**: Generated for cluster access

### GCP Kafka Cluster
- **Region**: us-west1
- **Cloud Provider**: GCP
- **Type**: Basic cluster (single-zone by default)
- **Service Account**: Created automatically with manager permissions
- **API Key**: Generated for cluster access

## Accessing Cluster Information

After successful deployment, view the cluster details:

```bash
# View all outputs
terraform output

# View connection details
terraform output connection_details

# View specific cluster bootstrap endpoints
terraform output aws_cluster_bootstrap_endpoint
terraform output gcp_cluster_bootstrap_endpoint

# View sensitive outputs (API keys)
terraform output -json aws_cluster_api_key
terraform output -json aws_cluster_api_secret
```

## Using the Clusters

### AWS Cluster Connection

```bash
# Get the bootstrap endpoint
AWS_BOOTSTRAP=$(terraform output -raw aws_cluster_bootstrap_endpoint)
AWS_API_KEY=$(terraform output -raw aws_cluster_api_key)
AWS_API_SECRET=$(terraform output -raw aws_cluster_api_secret)

# Use with kafka-console-producer or your application
kafka-console-producer --bootstrap-server $AWS_BOOTSTRAP \
  --producer-property security.protocol=SASL_SSL \
  --producer-property sasl.mechanism=PLAIN \
  --producer-property sasl.jaas.config="org.apache.kafka.common.security.plain.PlainLoginModule required username='$AWS_API_KEY' password='$AWS_API_SECRET';" \
  --topic test-topic
```

### GCP Cluster Connection

```bash
# Get the bootstrap endpoint
GCP_BOOTSTRAP=$(terraform output -raw gcp_cluster_bootstrap_endpoint)
GCP_API_KEY=$(terraform output -raw gcp_cluster_api_key)
GCP_API_SECRET=$(terraform output -raw gcp_cluster_api_secret)

# Use with kafka-console-producer or your application
kafka-console-producer --bootstrap-server $GCP_BOOTSTRAP \
  --producer-property security.protocol=SASL_SSL \
  --producer-property sasl.mechanism=PLAIN \
  --producer-property sasl.jaas.config="org.apache.kafka.common.security.plain.PlainLoginModule required username='$GCP_API_KEY' password='$GCP_API_SECRET';" \
  --topic test-topic
```

## Customization

You can customize the following in `terraform.tfvars`:

```hcl
# Environment name
environment_name = "my-custom-environment"

# Cluster names
aws_cluster_name = "my-aws-cluster"
gcp_cluster_name = "my-gcp-cluster"

# Availability (SINGLE_ZONE or MULTI_ZONE)
# Note: MULTI_ZONE is more expensive but provides higher availability
availability = "MULTI_ZONE"
```

## Cluster Types and Pricing

This configuration uses **Basic** clusters by default:
- Good for development and testing
- Lower cost
- Single-zone or multi-zone availability

To use **Standard** or **Dedicated** clusters, modify the cluster configuration in `main.tf`:

```hcl
# For Standard cluster
standard {
  # Add Standard cluster configuration
}

# For Dedicated cluster
dedicated {
  cku = 1  # Confluent Kafka Units
}
```

## Cleanup

To destroy all created resources:

```bash
terraform destroy
```

Type `yes` when prompted.

**Warning**: This will permanently delete:
- Both Kafka clusters
- All topics and data in the clusters
- Service accounts
- API keys
- The environment (if no other clusters exist)

## Troubleshooting

### Authentication Errors

If you see authentication errors:
1. Verify your Cloud API Key and Secret in `terraform.tfvars`
2. Ensure the API key has "CloudClusterAdmin" or "OrganizationAdmin" role
3. Check that the key hasn't expired

### Resource Already Exists

If resources already exist:
```bash
# Import existing environment
terraform import confluent_environment.main env-xxxxx

# Import existing cluster
terraform import confluent_kafka_cluster.aws_cluster lkc-xxxxx
```

### Rate Limiting

Confluent Cloud API has rate limits. If you encounter rate limiting:
- Wait a few minutes before retrying
- Use `terraform apply -parallelism=1` to reduce concurrent API calls

## State Management

Terraform state is stored locally in `terraform.tfstate`. For production:
1. Use remote state (S3, Terraform Cloud, etc.)
2. Enable state locking
3. Never commit `terraform.tfstate` to version control

## Security Best Practices

1. **Never commit credentials**: Use environment variables or secret management
2. **Rotate API keys regularly**: Create new keys and update `terraform.tfvars`
3. **Use least privilege**: Grant minimum required permissions to service accounts
4. **Enable audit logs**: Monitor cluster access and changes

## Additional Resources

- [Confluent Cloud Documentation](https://docs.confluent.io/cloud/current/overview.html)
- [Terraform Confluent Provider](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs)
- [Confluent Cloud Terraform Examples](https://github.com/confluentinc/terraform-provider-confluent/tree/master/examples)

## Support

For issues with:
- **Terraform Configuration**: Check the Terraform Confluent Provider documentation
- **Confluent Cloud**: Contact Confluent Support or check the Confluent Community
- **This Demo**: Refer to the main README in the parent directory
