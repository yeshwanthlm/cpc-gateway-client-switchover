# =============================================================================
# Role-Based Access Control (RBAC) Configuration
# =============================================================================
# This file manages role bindings for service accounts to enable ACL creation
#
# IMPORTANT: Your Cloud API key (in terraform.tfvars) must have OrganizationAdmin
# or EnvironmentAdmin permissions to create these role bindings.
#
# To grant this permission (one-time manual step):
# 1. Go to: https://confluent.cloud/settings/api-keys
# 2. Find your Cloud API key: PPBQ6IBKOFRNECEG
# 3. Add role binding: OrganizationAdmin
#
# After that, all ACL and permission management is handled by Terraform.
# =============================================================================

# Grant EnvironmentAdmin role to AWS cluster service account
# This allows the service account to manage ACLs within the environment
resource "confluent_role_binding" "aws_cluster_admin" {
  principal   = "User:${confluent_service_account.aws_cluster_manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.aws_cluster.rbac_crn
}

# Grant EnvironmentAdmin role to GCP cluster service account
# This allows the service account to manage ACLs within the environment
resource "confluent_role_binding" "gcp_cluster_admin" {
  principal   = "User:${confluent_service_account.gcp_cluster_manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.gcp_cluster.rbac_crn
}

# Note: These role bindings grant the service accounts admin permissions on their
# respective clusters. Combined with the ACLs in main.tf, this provides:
# 1. Cluster admin capabilities (via role binding)
# 2. Topic and consumer group access (via ACLs)
#
# For production, you may want to use more restrictive roles:
# - DeveloperRead (read-only access)
# - DeveloperWrite (write access)
# - DeveloperManage (manage topics, ACLs, etc.)
