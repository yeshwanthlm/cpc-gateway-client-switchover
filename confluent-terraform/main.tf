terraform {
  required_version = ">= 1.0"
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# Environment for the clusters
resource "confluent_environment" "main" {
  display_name = var.environment_name

  lifecycle {
    prevent_destroy = false
  }
}

# AWS Cluster in us-east-1
resource "confluent_kafka_cluster" "aws_cluster" {
  display_name = var.aws_cluster_name
  availability = var.availability
  cloud        = "AWS"
  region       = "us-east-1"

  basic {}

  environment {
    id = confluent_environment.main.id
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Service Account for AWS Cluster
resource "confluent_service_account" "aws_cluster_manager" {
  display_name = "${var.aws_cluster_name}-manager"
  description  = "Service account for AWS cluster management"
}

# API Key for AWS Cluster
resource "confluent_api_key" "aws_cluster_api_key" {
  display_name = "${var.aws_cluster_name}-api-key"
  description  = "API Key for AWS Kafka cluster"
  owner {
    id          = confluent_service_account.aws_cluster_manager.id
    api_version = confluent_service_account.aws_cluster_manager.api_version
    kind        = confluent_service_account.aws_cluster_manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.aws_cluster.id
    api_version = confluent_kafka_cluster.aws_cluster.api_version
    kind        = confluent_kafka_cluster.aws_cluster.kind

    environment {
      id = confluent_environment.main.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}

# GCP Cluster in us-west1
resource "confluent_kafka_cluster" "gcp_cluster" {
  display_name = var.gcp_cluster_name
  availability = var.availability
  cloud        = "GCP"
  region       = "us-west1"

  basic {}

  environment {
    id = confluent_environment.main.id
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Service Account for GCP Cluster
resource "confluent_service_account" "gcp_cluster_manager" {
  display_name = "${var.gcp_cluster_name}-manager"
  description  = "Service account for GCP cluster management"
}

# API Key for GCP Cluster
resource "confluent_api_key" "gcp_cluster_api_key" {
  display_name = "${var.gcp_cluster_name}-api-key"
  description  = "API Key for GCP Kafka cluster"
  owner {
    id          = confluent_service_account.gcp_cluster_manager.id
    api_version = confluent_service_account.gcp_cluster_manager.api_version
    kind        = confluent_service_account.gcp_cluster_manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.gcp_cluster.id
    api_version = confluent_kafka_cluster.gcp_cluster.api_version
    kind        = confluent_kafka_cluster.gcp_cluster.kind

    environment {
      id = confluent_environment.main.id
    }
  }

  lifecycle {
    prevent_destroy = false
  }
}
