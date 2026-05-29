output "environment_id" {
  description = "Confluent Cloud Environment ID"
  value       = confluent_environment.main.id
}

output "aws_cluster_id" {
  description = "AWS Kafka Cluster ID"
  value       = confluent_kafka_cluster.aws_cluster.id
}

output "aws_cluster_bootstrap_endpoint" {
  description = "AWS Kafka Cluster Bootstrap Endpoint"
  value       = confluent_kafka_cluster.aws_cluster.bootstrap_endpoint
}

output "aws_cluster_rest_endpoint" {
  description = "AWS Kafka Cluster REST Endpoint"
  value       = confluent_kafka_cluster.aws_cluster.rest_endpoint
}

output "aws_cluster_api_key" {
  description = "AWS Kafka Cluster API Key"
  value       = confluent_api_key.aws_cluster_api_key.id
  sensitive   = true
}

output "aws_cluster_api_secret" {
  description = "AWS Kafka Cluster API Secret"
  value       = confluent_api_key.aws_cluster_api_key.secret
  sensitive   = true
}

output "gcp_cluster_id" {
  description = "GCP Kafka Cluster ID"
  value       = confluent_kafka_cluster.gcp_cluster.id
}

output "gcp_cluster_bootstrap_endpoint" {
  description = "GCP Kafka Cluster Bootstrap Endpoint"
  value       = confluent_kafka_cluster.gcp_cluster.bootstrap_endpoint
}

output "gcp_cluster_rest_endpoint" {
  description = "GCP Kafka Cluster REST Endpoint"
  value       = confluent_kafka_cluster.gcp_cluster.rest_endpoint
}

output "gcp_cluster_api_key" {
  description = "GCP Kafka Cluster API Key"
  value       = confluent_api_key.gcp_cluster_api_key.id
  sensitive   = true
}

output "gcp_cluster_api_secret" {
  description = "GCP Kafka Cluster API Secret"
  value       = confluent_api_key.gcp_cluster_api_key.secret
  sensitive   = true
}

output "connection_details" {
  description = "Connection details for both clusters"
  value = {
    aws_cluster = {
      cluster_id        = confluent_kafka_cluster.aws_cluster.id
      bootstrap_servers = confluent_kafka_cluster.aws_cluster.bootstrap_endpoint
      rest_endpoint     = confluent_kafka_cluster.aws_cluster.rest_endpoint
      region            = "us-east-1"
      cloud             = "AWS"
    }
    gcp_cluster = {
      cluster_id        = confluent_kafka_cluster.gcp_cluster.id
      bootstrap_servers = confluent_kafka_cluster.gcp_cluster.bootstrap_endpoint
      rest_endpoint     = confluent_kafka_cluster.gcp_cluster.rest_endpoint
      region            = "us-west1"
      cloud             = "GCP"
    }
  }
}

# Service Account IDs (needed for creating ACLs)
output "aws_service_account_id" {
  description = "AWS cluster service account ID (for ACL creation)"
  value       = confluent_service_account.aws_cluster_manager.id
}

output "gcp_service_account_id" {
  description = "GCP cluster service account ID (for ACL creation)"
  value       = confluent_service_account.gcp_cluster_manager.id
}

output "bootstrap_instructions" {
  description = "One-time bootstrap instructions for Terraform automation"
  value       = <<-EOT

    ╔════════════════════════════════════════════════════════════════╗
    ║  ONE-TIME BOOTSTRAP REQUIRED                                   ║
    ╠════════════════════════════════════════════════════════════════╣
    ║  To enable full Terraform automation, grant your Cloud API key ║
    ║  OrganizationAdmin permissions (one-time manual step).         ║
    ║                                                                 ║
    ║  1. Go to: https://confluent.cloud/settings/api-keys          ║
    ║  2. Find: PPBQ6IBKOFRNECEG                                    ║
    ║  3. Add role: OrganizationAdmin                               ║
    ║  4. Run: terraform apply                                      ║
    ║                                                                 ║
    ║  After this, everything is managed by Terraform!              ║
    ║                                                                 ║
    ║  See: BOOTSTRAP.md for detailed instructions                  ║
    ╚════════════════════════════════════════════════════════════════╝

  EOT
}

output "terraform_managed_resources" {
  description = "List of resources managed by Terraform after bootstrap"
  value       = <<-EOT

    After bootstrap, Terraform manages:

    Infrastructure:
      ✓ Environment: ${confluent_environment.main.id}
      ✓ AWS Cluster: ${confluent_kafka_cluster.aws_cluster.id}
      ✓ GCP Cluster: ${confluent_kafka_cluster.gcp_cluster.id}
      ✓ Service Accounts: ${confluent_service_account.aws_cluster_manager.id}, ${confluent_service_account.gcp_cluster_manager.id}
      ✓ API Keys: 2 cluster-specific keys

    Access Control (after bootstrap):
      ✓ Role Bindings: CloudClusterAdmin for both clusters
      ✓ ACLs: 10 total (5 per cluster)
        - CREATE, WRITE, READ, DESCRIBE for topics
        - READ for consumer groups

  EOT
}
