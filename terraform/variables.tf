# =========================
# VectorFlow Terraform Variables
# =========================

# ----- General -----

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# ----- VPC Configuration -----

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets (costs money!)"
  type        = bool
  default     = false # Keep false for $0 budget
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway (cost optimization)"
  type        = bool
  default     = true
}

# ----- EKS Node Configuration -----

variable "node_instance_types" {
  description = "Instance types for general node group"
  type        = list(string)
  default     = ["t3.medium"] # Free tier eligible
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "use_spot_instances" {
  description = "Use Spot instances for cost savings (can be interrupted)"
  type        = bool
  default     = true # 60-90% cost savings
}

# ----- Inference Node Configuration -----

variable "inference_instance_types" {
  description = "Instance types for inference workloads"
  type        = list(string)
  default     = ["t3.large", "t3.xlarge"]
}

variable "inference_max_size" {
  description = "Maximum inference nodes"
  type        = number
  default     = 2
}

variable "inference_desired_size" {
  description = "Desired inference nodes (set to 0 for dev)"
  type        = number
  default     = 0 # Start with 0 for cost savings
}

# ----- Security -----

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict in production
}

variable "aws_auth_roles" {
  description = "Additional IAM roles to add to aws-auth configmap"
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

# ----- Cost Protection -----

variable "create_billing_alarm" {
  description = "Create CloudWatch billing alarm"
  type        = bool
  default     = true
}

variable "billing_alarm_threshold" {
  description = "Billing alarm threshold in USD"
  type        = number
  default     = 0.01 # $0.01 - immediate notification
}

variable "billing_alarm_sns_topic" {
  description = "SNS topic ARN for billing alarm notifications"
  type        = string
  default     = ""
}

# ----- Optional Resources -----

variable "create_artifacts_bucket" {
  description = "Create S3 bucket for build artifacts"
  type        = bool
  default     = false # Keep false for minimal setup
}
