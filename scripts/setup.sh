#!/bin/bash
# =========================
# VectorFlow Initial Setup
# =========================
# Run this script once to set up your development environment

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo ""
echo "=============================================="
echo "   VectorFlow - Initial Setup"
echo "=============================================="
echo ""

cd "$PROJECT_ROOT"

# ----- Check Dependencies -----
log_info "Checking required dependencies..."

check_command() {
    if command -v "$1" &> /dev/null; then
        log_success "$1 found: $($1 --version 2>/dev/null | head -n1 || echo 'installed')"
        return 0
    else
        log_error "$1 not found!"
        return 1
    fi
}

MISSING_DEPS=()

# Check core dependencies
check_command "git" || MISSING_DEPS+=("git")
check_command "docker" || MISSING_DEPS+=("docker")

# Check language runtimes
check_command "go" || MISSING_DEPS+=("go")
check_command "cargo" || MISSING_DEPS+=("rust/cargo")
check_command "python3" || MISSING_DEPS+=("python3")
check_command "node" || MISSING_DEPS+=("node")
check_command "npm" || MISSING_DEPS+=("npm")

# Check DevOps tools (optional but recommended)
check_command "kubectl" || log_warn "kubectl not found - needed for Kubernetes deployment"
check_command "ansible" || log_warn "ansible not found - needed for server provisioning"
check_command "minikube" || log_warn "minikube not found - needed for local K8s testing"

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo ""
    log_error "Missing required dependencies: ${MISSING_DEPS[*]}"
    log_info "Please install missing dependencies and run this script again."
    log_info "Run: ./scripts/install-tools.sh for installation help"
    exit 1
fi

# ----- Create Environment File -----
log_info "Setting up environment configuration..."

if [ ! -f ".env" ]; then
    cp .env.example .env
    log_success "Created .env file from .env.example"
    log_warn "Please edit .env with your configuration values!"
else
    log_info ".env file already exists, skipping..."
fi

# ----- Create Directory Structure -----
log_info "Creating project directory structure..."

# Create main service directories
mkdir -p go/cmd/gateway go/internal/{api,config,models,service} go/pkg/client go/tests
mkdir -p rust/src rust/tests rust/benches
mkdir -p python/app python/services python/tests
mkdir -p frontend/app frontend/components frontend/lib frontend/public

# Create infrastructure directories
mkdir -p k8s/{gateway,worker,inference,frontend,networking,storage,monitoring,secrets}
mkdir -p ansible/{inventory/group_vars,inventory/host_vars,roles,playbooks}
mkdir -p jenkins/{groovy/shared-library/vars,scripts,config}
mkdir -p infrastructure/chef/{cookbooks,roles,environments}

# Create support directories
mkdir -p scripts
mkdir -p docs
mkdir -p monitoring/{prometheus,grafana/dashboards,alertmanager}
mkdir -p models  # For ML model cache

# Create .gitkeep files for empty directories
touch k8s/secrets/.gitkeep
touch models/.gitkeep

log_success "Directory structure created!"

# ----- Initialize Git (if not already) -----
if [ ! -d ".git" ]; then
    log_info "Initializing Git repository..."
    git init
    git add .gitignore
    git commit -m "Initial commit: Project structure and configuration

- Add comprehensive .gitignore for multi-language project
- Add root Makefile for build orchestration
- Add environment configuration template
- Add setup scripts

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
    log_success "Git repository initialized!"
else
    log_info "Git repository already exists, skipping init..."
fi

# ----- Setup Go Module -----
log_info "Initializing Go module..."
if [ ! -f "go/go.mod" ]; then
    cd go
    go mod init github.com/vectorflow/gateway
    cd "$PROJECT_ROOT"
    log_success "Go module initialized!"
else
    log_info "Go module already exists, skipping..."
fi

# ----- Setup Rust Project -----
log_info "Initializing Rust project..."
if [ ! -f "rust/Cargo.toml" ]; then
    cd rust
    cargo init --name vectorflow_worker
    cd "$PROJECT_ROOT"
    log_success "Rust project initialized!"
else
    log_info "Rust project already exists, skipping..."
fi

# ----- Setup Python Virtual Environment -----
log_info "Setting up Python virtual environment..."
if [ ! -d "python/venv" ]; then
    cd python
    python3 -m venv venv
    source venv/bin/activate 2>/dev/null || source venv/Scripts/activate 2>/dev/null
    pip install --upgrade pip setuptools wheel
    deactivate 2>/dev/null || true
    cd "$PROJECT_ROOT"
    log_success "Python virtual environment created!"
else
    log_info "Python virtual environment already exists, skipping..."
fi

# ----- Setup Node.js Frontend -----
log_info "Setting up Next.js frontend..."
if [ ! -f "frontend/package.json" ]; then
    log_info "Run 'cd frontend && npx create-next-app@latest .' to initialize Next.js"
    log_warn "Skipping automatic Next.js setup - requires interactive prompts"
else
    log_info "Frontend package.json already exists, skipping..."
fi

# ----- Final Summary -----
echo ""
echo "=============================================="
echo "   Setup Complete!"
echo "=============================================="
echo ""
log_success "VectorFlow development environment is ready!"
echo ""
echo "Next steps:"
echo "  1. Edit .env with your configuration"
echo "  2. Run 'make dev' to start development servers"
echo "  3. Run 'make help' to see all available commands"
echo ""
echo "Directory structure created:"
echo "  go/        - Go gateway service"
echo "  rust/      - Rust worker service"
echo "  python/    - Python inference service"
echo "  frontend/  - Next.js frontend"
echo "  k8s/       - Kubernetes manifests"
echo "  ansible/   - Ansible playbooks"
echo "  jenkins/   - Jenkins pipeline config"
echo ""
