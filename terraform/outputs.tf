# =========================
# VectorFlow Terraform Outputs
# =========================

# ----- VPC Outputs -----

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

# ----- EKS Outputs -----

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA"
  value       = module.eks.cluster_oidc_issuer_url
}

# ----- ECR Outputs -----

output "ecr_repositories" {
  description = "ECR repository URLs"
  value = {
    for k, v in aws_ecr_repository.services : k => v.repository_url
  }
}

# ----- Kubeconfig Command -----

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ----- Cost Alerts -----

output "billing_alarm_arn" {
  description = "Billing alarm ARN"
  value       = var.create_billing_alarm ? aws_cloudwatch_metric_alarm.billing_alarm[0].arn : null
}

# ----- S3 Outputs -----

output "artifacts_bucket" {
  description = "S3 artifacts bucket name"
  value       = var.create_artifacts_bucket ? aws_s3_bucket.artifacts[0].id : null
}

# ----- Connection Info -----

output "connection_info" {
  description = "Connection information for VectorFlow"
  value = <<-EOT

    ============================================
    VectorFlow AWS Infrastructure Deployed!
    ============================================

    EKS Cluster: ${module.eks.cluster_name}
    Region: ${var.aws_region}

    Configure kubectl:
      aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}

    Push images to ECR:
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com

    Deploy to Kubernetes:
      kubectl apply -k k8s/

    IMPORTANT - To destroy and avoid charges:
      terraform destroy -auto-approve
      OR
      ./scripts/cleanup.sh

    EOT
}
