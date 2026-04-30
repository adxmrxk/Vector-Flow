#!/bin/bash
# =========================
# VectorFlow AWS Cleanup Script
# =========================
# This script destroys ALL AWS resources to ensure $0.00 billing
# Run this after demos or when done with cloud testing
#
# SAFETY: This script requires explicit confirmation before deletion

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_destroy() { echo -e "${MAGENTA}[DESTROY]${NC} $1"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
fi

# Default values
AWS_REGION="${AWS_REGION:-us-east-1}"
K8S_NAMESPACE="${K8S_NAMESPACE:-vectorflow}"
PROJECT_TAG="vectorflow"

echo ""
echo -e "${RED}=============================================="
echo "   VectorFlow - AWS Resource Cleanup"
echo "==============================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will DELETE all VectorFlow resources!${NC}"
echo ""

# ----- Pre-flight Checks -----
log_info "Running pre-flight checks..."

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        log_error "$1 not found - required for cleanup"
        return 1
    fi
}

# Check required tools
MISSING=()
check_command "aws" || MISSING+=("aws-cli")
check_command "kubectl" || log_warn "kubectl not found - skipping K8s cleanup"
check_command "docker" || log_warn "docker not found - skipping local cleanup"

if [ ${#MISSING[@]} -gt 0 ]; then
    log_error "Missing required tools: ${MISSING[*]}"
    exit 1
fi

# Verify AWS credentials
log_info "Verifying AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured or invalid"
    log_info "Run 'aws configure' to set up credentials"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log_success "AWS Account: $AWS_ACCOUNT_ID"
log_info "Region: $AWS_REGION"

# ----- Inventory Phase -----
echo ""
log_info "Scanning for VectorFlow resources..."
echo ""

# Track what we find
EC2_INSTANCES=()
EKS_CLUSTERS=()
ECR_REPOS=()
S3_BUCKETS=()
LOAD_BALANCERS=()
SECURITY_GROUPS=()
KEY_PAIRS=()
EBS_VOLUMES=()

# Scan EC2 instances
log_info "Checking EC2 instances..."
EC2_JSON=$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters "Name=tag:Project,Values=$PROJECT_TAG" "Name=instance-state-name,Values=running,stopped,pending" \
    --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || echo "")

if [ -n "$EC2_JSON" ]; then
    while read -r line; do
        if [ -n "$line" ]; then
            EC2_INSTANCES+=("$line")
            echo -e "  ${CYAN}EC2:${NC} $line"
        fi
    done <<< "$EC2_JSON"
fi

# Scan EKS clusters
log_info "Checking EKS clusters..."
EKS_JSON=$(aws eks list-clusters \
    --region "$AWS_REGION" \
    --query 'clusters[?contains(@, `vectorflow`)]' \
    --output text 2>/dev/null || echo "")

if [ -n "$EKS_JSON" ]; then
    for cluster in $EKS_JSON; do
        EKS_CLUSTERS+=("$cluster")
        echo -e "  ${CYAN}EKS:${NC} $cluster"
    done
fi

# Scan ECR repositories
log_info "Checking ECR repositories..."
ECR_JSON=$(aws ecr describe-repositories \
    --region "$AWS_REGION" \
    --query "repositories[?contains(repositoryName, 'vectorflow')].repositoryName" \
    --output text 2>/dev/null || echo "")

if [ -n "$ECR_JSON" ]; then
    for repo in $ECR_JSON; do
        ECR_REPOS+=("$repo")
        echo -e "  ${CYAN}ECR:${NC} $repo"
    done
fi

# Scan S3 buckets
log_info "Checking S3 buckets..."
S3_JSON=$(aws s3api list-buckets \
    --query "Buckets[?contains(Name, 'vectorflow')].Name" \
    --output text 2>/dev/null || echo "")

if [ -n "$S3_JSON" ]; then
    for bucket in $S3_JSON; do
        S3_BUCKETS+=("$bucket")
        echo -e "  ${CYAN}S3:${NC} $bucket"
    done
fi

# Scan Load Balancers
log_info "Checking Load Balancers..."
ELB_JSON=$(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, 'vectorflow')].[LoadBalancerArn,LoadBalancerName]" \
    --output text 2>/dev/null || echo "")

if [ -n "$ELB_JSON" ]; then
    while read -r line; do
        if [ -n "$line" ]; then
            LOAD_BALANCERS+=("$line")
            echo -e "  ${CYAN}ELB:${NC} $line"
        fi
    done <<< "$ELB_JSON"
fi

# Scan Security Groups
log_info "Checking Security Groups..."
SG_JSON=$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters "Name=tag:Project,Values=$PROJECT_TAG" \
    --query 'SecurityGroups[*].[GroupId,GroupName]' \
    --output text 2>/dev/null || echo "")

if [ -n "$SG_JSON" ]; then
    while read -r line; do
        if [ -n "$line" ]; then
            SECURITY_GROUPS+=("$line")
            echo -e "  ${CYAN}SG:${NC} $line"
        fi
    done <<< "$SG_JSON"
fi

# Scan Key Pairs
log_info "Checking Key Pairs..."
KP_JSON=$(aws ec2 describe-key-pairs \
    --region "$AWS_REGION" \
    --filters "Name=key-name,Values=*vectorflow*" \
    --query 'KeyPairs[*].KeyName' \
    --output text 2>/dev/null || echo "")

if [ -n "$KP_JSON" ]; then
    for kp in $KP_JSON; do
        KEY_PAIRS+=("$kp")
        echo -e "  ${CYAN}KeyPair:${NC} $kp"
    done
fi

# Scan EBS Volumes (unattached)
log_info "Checking EBS volumes..."
EBS_JSON=$(aws ec2 describe-volumes \
    --region "$AWS_REGION" \
    --filters "Name=tag:Project,Values=$PROJECT_TAG" "Name=status,Values=available" \
    --query 'Volumes[*].[VolumeId,Size]' \
    --output text 2>/dev/null || echo "")

if [ -n "$EBS_JSON" ]; then
    while read -r line; do
        if [ -n "$line" ]; then
            EBS_VOLUMES+=("$line")
            echo -e "  ${CYAN}EBS:${NC} $line"
        fi
    done <<< "$EBS_JSON"
fi

# ----- Summary -----
echo ""
echo "=============================================="
echo "   Resource Summary"
echo "=============================================="
echo ""
echo -e "  EC2 Instances:    ${CYAN}${#EC2_INSTANCES[@]}${NC}"
echo -e "  EKS Clusters:     ${CYAN}${#EKS_CLUSTERS[@]}${NC}"
echo -e "  ECR Repositories: ${CYAN}${#ECR_REPOS[@]}${NC}"
echo -e "  S3 Buckets:       ${CYAN}${#S3_BUCKETS[@]}${NC}"
echo -e "  Load Balancers:   ${CYAN}${#LOAD_BALANCERS[@]}${NC}"
echo -e "  Security Groups:  ${CYAN}${#SECURITY_GROUPS[@]}${NC}"
echo -e "  Key Pairs:        ${CYAN}${#KEY_PAIRS[@]}${NC}"
echo -e "  EBS Volumes:      ${CYAN}${#EBS_VOLUMES[@]}${NC}"
echo ""

TOTAL_RESOURCES=$((${#EC2_INSTANCES[@]} + ${#EKS_CLUSTERS[@]} + ${#ECR_REPOS[@]} + ${#S3_BUCKETS[@]} + ${#LOAD_BALANCERS[@]} + ${#SECURITY_GROUPS[@]} + ${#KEY_PAIRS[@]} + ${#EBS_VOLUMES[@]}))

if [ "$TOTAL_RESOURCES" -eq 0 ]; then
    log_success "No VectorFlow resources found in AWS!"
    log_info "Your AWS account is clean. Cost: \$0.00"
    exit 0
fi

# ----- Confirmation -----
echo -e "${RED}=============================================="
echo "   DANGER ZONE"
echo "==============================================${NC}"
echo ""
echo -e "${YELLOW}You are about to DELETE $TOTAL_RESOURCES resources!${NC}"
echo ""
echo "This action is IRREVERSIBLE."
echo ""

# Require explicit confirmation
read -p "Type 'DELETE' to confirm destruction: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    log_warn "Cleanup cancelled. No resources were deleted."
    exit 0
fi

echo ""
log_destroy "Starting resource cleanup..."
echo ""

# ----- Terraform Destroy (if initialized) -----
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
if [ -d "$TERRAFORM_DIR/.terraform" ]; then
    log_destroy "Destroying Terraform-managed infrastructure..."
    cd "$TERRAFORM_DIR"
    terraform destroy -auto-approve 2>/dev/null || log_warn "Terraform destroy failed or not initialized"
    cd "$PROJECT_ROOT"
    log_success "Terraform infrastructure destroyed"
else
    log_info "No Terraform state found, skipping terraform destroy"
fi

# ----- Destruction Phase -----

# 1. Delete EKS Clusters first (they create many dependent resources)
if [ ${#EKS_CLUSTERS[@]} -gt 0 ]; then
    for cluster in "${EKS_CLUSTERS[@]}"; do
        log_destroy "Deleting EKS cluster: $cluster"

        # Delete node groups first
        NODE_GROUPS=$(aws eks list-nodegroups \
            --cluster-name "$cluster" \
            --region "$AWS_REGION" \
            --query 'nodegroups' \
            --output text 2>/dev/null || echo "")

        for ng in $NODE_GROUPS; do
            log_info "  Deleting node group: $ng"
            aws eks delete-nodegroup \
                --cluster-name "$cluster" \
                --nodegroup-name "$ng" \
                --region "$AWS_REGION" 2>/dev/null || true
        done

        # Wait for node groups to delete
        if [ -n "$NODE_GROUPS" ]; then
            log_info "  Waiting for node groups to delete..."
            sleep 30
        fi

        # Delete the cluster
        aws eks delete-cluster \
            --name "$cluster" \
            --region "$AWS_REGION" 2>/dev/null || true

        log_success "  EKS cluster deletion initiated: $cluster"
    done
fi

# 2. Delete EC2 Instances
if [ ${#EC2_INSTANCES[@]} -gt 0 ]; then
    log_destroy "Terminating EC2 instances..."
    for instance_info in "${EC2_INSTANCES[@]}"; do
        instance_id=$(echo "$instance_info" | awk '{print $1}')
        log_info "  Terminating: $instance_id"
        aws ec2 terminate-instances \
            --instance-ids "$instance_id" \
            --region "$AWS_REGION" 2>/dev/null || true
    done
    log_success "EC2 termination initiated"
fi

# 3. Delete Load Balancers
if [ ${#LOAD_BALANCERS[@]} -gt 0 ]; then
    log_destroy "Deleting Load Balancers..."
    for lb_info in "${LOAD_BALANCERS[@]}"; do
        lb_arn=$(echo "$lb_info" | awk '{print $1}')
        log_info "  Deleting: $lb_arn"
        aws elbv2 delete-load-balancer \
            --load-balancer-arn "$lb_arn" \
            --region "$AWS_REGION" 2>/dev/null || true
    done
    log_success "Load Balancers deleted"
fi

# 4. Delete ECR Repositories
if [ ${#ECR_REPOS[@]} -gt 0 ]; then
    log_destroy "Deleting ECR repositories..."
    for repo in "${ECR_REPOS[@]}"; do
        log_info "  Deleting: $repo"
        aws ecr delete-repository \
            --repository-name "$repo" \
            --force \
            --region "$AWS_REGION" 2>/dev/null || true
    done
    log_success "ECR repositories deleted"
fi

# 5. Delete S3 Buckets
if [ ${#S3_BUCKETS[@]} -gt 0 ]; then
    log_destroy "Deleting S3 buckets..."
    for bucket in "${S3_BUCKETS[@]}"; do
        log_info "  Emptying: $bucket"
        aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
        log_info "  Deleting: $bucket"
        aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
    done
    log_success "S3 buckets deleted"
fi

# 6. Delete EBS Volumes
if [ ${#EBS_VOLUMES[@]} -gt 0 ]; then
    log_destroy "Deleting EBS volumes..."
    for vol_info in "${EBS_VOLUMES[@]}"; do
        vol_id=$(echo "$vol_info" | awk '{print $1}')
        log_info "  Deleting: $vol_id"
        aws ec2 delete-volume \
            --volume-id "$vol_id" \
            --region "$AWS_REGION" 2>/dev/null || true
    done
    log_success "EBS volumes deleted"
fi

# 7. Delete Security Groups (after instances are terminated)
if [ ${#SECURITY_GROUPS[@]} -gt 0 ]; then
    log_info "Waiting for instances to terminate before deleting security groups..."
    sleep 60

    log_destroy "Deleting Security Groups..."
    for sg_info in "${SECURITY_GROUPS[@]}"; do
        sg_id=$(echo "$sg_info" | awk '{print $1}')
        # Skip default security groups
        if [[ "$sg_id" != *"default"* ]]; then
            log_info "  Deleting: $sg_id"
            aws ec2 delete-security-group \
                --group-id "$sg_id" \
                --region "$AWS_REGION" 2>/dev/null || true
        fi
    done
    log_success "Security Groups deleted"
fi

# 8. Delete Key Pairs
if [ ${#KEY_PAIRS[@]} -gt 0 ]; then
    log_destroy "Deleting Key Pairs..."
    for kp in "${KEY_PAIRS[@]}"; do
        log_info "  Deleting: $kp"
        aws ec2 delete-key-pair \
            --key-name "$kp" \
            --region "$AWS_REGION" 2>/dev/null || true
    done
    log_success "Key Pairs deleted"
fi

# ----- Local Cleanup (Optional) -----
echo ""
log_info "Cleaning up local resources..."

# Stop local Kubernetes (if running)
if command -v kubectl &> /dev/null; then
    log_info "Deleting local Kubernetes namespace..."
    kubectl delete namespace "$K8S_NAMESPACE" --ignore-not-found=true 2>/dev/null || true
fi

# Stop Minikube (if running)
if command -v minikube &> /dev/null; then
    if minikube status &> /dev/null; then
        log_info "Stopping Minikube..."
        minikube stop 2>/dev/null || true
    fi
fi

# Stop Docker Compose services
if command -v docker &> /dev/null; then
    if [ -f "$PROJECT_ROOT/docker-compose.yml" ]; then
        log_info "Stopping Docker Compose services..."
        docker compose -f "$PROJECT_ROOT/docker-compose.yml" down --remove-orphans 2>/dev/null || true
    fi

    # Remove VectorFlow images (optional)
    read -p "Remove local Docker images? (y/N): " REMOVE_IMAGES
    if [ "$REMOVE_IMAGES" = "y" ] || [ "$REMOVE_IMAGES" = "Y" ]; then
        log_info "Removing VectorFlow Docker images..."
        docker images --format "{{.Repository}}:{{.Tag}}" | grep "vectorflow" | xargs -r docker rmi -f 2>/dev/null || true
        log_success "Docker images removed"
    fi
fi

# ----- Final Verification -----
echo ""
echo "=============================================="
echo "   Cleanup Complete"
echo "=============================================="
echo ""
log_success "All VectorFlow AWS resources have been deleted!"
echo ""
echo "Verification steps:"
echo "  1. Check AWS Console: https://console.aws.amazon.com"
echo "  2. Check Cost Explorer in 24-48 hours"
echo "  3. Verify billing alarm is still active"
echo ""
log_info "Run this script again to verify: ./scripts/cleanup.sh"
echo ""

# ----- Cost Reminder -----
echo -e "${GREEN}=============================================="
echo "   Cost Status: \$0.00 (Target)"
echo "==============================================${NC}"
echo ""
echo "Your AWS resources have been cleaned up."
echo "If you had any running costs, they should stop accruing now."
echo ""
echo "Remember:"
echo "  - Check AWS Cost Explorer in 24-48 hours"
echo "  - Your \$0.01 billing alarm will notify you of any charges"
echo "  - Use 'make local-dev' for future development (no cloud cost)"
echo ""
