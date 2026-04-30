# =========================
# VectorFlow Terraform Configuration
# =========================
# Infrastructure-as-Code for AWS deployment
# Run: terraform init && terraform plan && terraform apply
# Destroy: terraform destroy (or use cleanup.sh)

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  # Backend configuration for state storage
  # Uncomment for production use with S3 backend
  # backend "s3" {
  #   bucket         = "vectorflow-terraform-state"
  #   key            = "terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "vectorflow-terraform-locks"
  # }
}

# ----- Provider Configuration -----

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "vectorflow"
      Environment = var.environment
      ManagedBy   = "terraform"
      CostCenter  = "vectorflow-${var.environment}"
    }
  }
}

# ----- Data Sources -----

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ----- Local Variables -----

locals {
  name            = "vectorflow-${var.environment}"
  cluster_version = "1.28"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project     = "vectorflow"
    Environment = var.environment
  }
}

# ----- VPC Module -----

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway # Cost optimization
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required for EKS
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${local.name}"       = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${local.name}"       = "shared"
  }

  tags = local.tags
}

# ----- EKS Cluster -----

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = local.name
  cluster_version = local.cluster_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # Node groups
  eks_managed_node_groups = {
    # General workloads
    general = {
      name           = "${local.name}-general"
      instance_types = var.node_instance_types
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      labels = {
        workload = "general"
      }

      tags = local.tags
    }

    # ML/Inference workloads (larger instances)
    inference = {
      name           = "${local.name}-inference"
      instance_types = var.inference_instance_types
      capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

      min_size     = 0
      max_size     = var.inference_max_size
      desired_size = var.inference_desired_size

      labels = {
        workload = "inference"
      }

      taints = var.inference_desired_size > 0 ? [] : [{
        key    = "workload"
        value  = "inference"
        effect = "NO_SCHEDULE"
      }]

      tags = local.tags
    }
  }

  # IRSA for service accounts
  enable_irsa = true

  # Cluster access
  manage_aws_auth_configmap = true

  aws_auth_roles = var.aws_auth_roles

  tags = local.tags
}

# ----- ECR Repositories -----

resource "aws_ecr_repository" "services" {
  for_each = toset(["gateway", "worker", "inference", "frontend"])

  name                 = "vectorflow/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

# ECR Lifecycle policy to manage costs
resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ----- Security Group for ALB -----

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Security group for VectorFlow ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name}-alb-sg"
  })
}

# ----- CloudWatch Billing Alarm ($0.01 threshold) -----

resource "aws_cloudwatch_metric_alarm" "billing_alarm" {
  count = var.create_billing_alarm ? 1 : 0

  alarm_name          = "vectorflow-billing-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600 # 6 hours
  statistic           = "Maximum"
  threshold           = var.billing_alarm_threshold
  alarm_description   = "Billing alarm for VectorFlow - triggers at $${var.billing_alarm_threshold}"

  dimensions = {
    Currency = "USD"
  }

  alarm_actions = var.billing_alarm_sns_topic != "" ? [var.billing_alarm_sns_topic] : []

  tags = local.tags
}

# ----- S3 Bucket for artifacts (optional) -----

resource "aws_s3_bucket" "artifacts" {
  count = var.create_artifacts_bucket ? 1 : 0

  bucket = "${local.name}-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = local.tags
}

resource "aws_s3_bucket_versioning" "artifacts" {
  count  = var.create_artifacts_bucket ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  count  = var.create_artifacts_bucket ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  count  = var.create_artifacts_bucket ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
