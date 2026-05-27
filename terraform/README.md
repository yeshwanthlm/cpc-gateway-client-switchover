# EKS Cluster with Terraform

This Terraform configuration creates an AWS EKS cluster with 2 worker nodes.

## Prerequisites

1. AWS CLI installed and configured with credentials
2. Terraform installed (>= 1.0)
3. kubectl installed

## Usage

1. Initialize Terraform:
```bash
terraform init
```

2. Review the plan:
```bash
terraform plan
```

3. Apply the configuration:
```bash
terraform apply
```

4. Configure kubectl to access your cluster:
```bash
aws eks update-kubeconfig --region us-west-2 --name my-eks-cluster
```

5. Verify access:
```bash
kubectl get nodes
```

## Customization

Edit `variables.tf` or create a `terraform.tfvars` file:

```hcl
aws_region         = "us-east-1"
cluster_name       = "my-custom-cluster"
kubernetes_version = "1.28"
instance_type      = "t3.large"
```

## Cleanup

To destroy all resources:
```bash
terraform destroy
```
