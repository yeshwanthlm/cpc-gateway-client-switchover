variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "environment_name" {
  description = "Confluent Cloud Environment Name"
  type        = string
  default     = "cpc-gateway-demo"
}

variable "aws_cluster_name" {
  description = "Name for the AWS Kafka cluster"
  type        = string
  default     = "aws-us-east-1-cluster"
}

variable "gcp_cluster_name" {
  description = "Name for the GCP Kafka cluster"
  type        = string
  default     = "gcp-us-west-cluster"
}

variable "availability" {
  description = "Availability zone configuration (SINGLE_ZONE or MULTI_ZONE)"
  type        = string
  default     = "SINGLE_ZONE"
}
