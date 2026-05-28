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
