#!/bin/bash
# =========================
# VectorFlow Development Setup
# =========================
# Sets up the development environment with hot-reload capabilities

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo ""
echo "=============================================="
echo "   VectorFlow - Development Setup"
echo "=============================================="
echo ""

cd "$PROJECT_ROOT"

# ----- Load Environment -----
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
    log_success "Environment variables loaded from .env"
else
    log_error ".env file not found! Run ./scripts/setup.sh first"
    exit 1
fi

# ----- Go Development Tools -----
log_info "Setting up Go development tools..."

if command -v go &> /dev/null; then
    # Install air for hot-reload
    if ! command -v air &> /dev/null; then
        log_info "Installing air (Go hot-reload)..."
        go install github.com/air-verse/air@latest
    fi

    # Install golangci-lint
    if ! command -v golangci-lint &> /dev/null; then
        log_info "Installing golangci-lint..."
        go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
    fi

    log_success "Go development tools ready!"
else
    log_warn "Go not installed, skipping Go dev tools"
fi

# ----- Rust Development Tools -----
log_info "Setting up Rust development tools..."

if command -v cargo &> /dev/null; then
    # Install cargo-watch for hot-reload
    if ! cargo install --list | grep -q "cargo-watch"; then
        log_info "Installing cargo-watch..."
        cargo install cargo-watch
    fi

    # Install clippy and rustfmt
    rustup component add clippy rustfmt 2>/dev/null || true

    log_success "Rust development tools ready!"
else
    log_warn "Rust not installed, skipping Rust dev tools"
fi

# ----- Python Development Setup -----
log_info "Setting up Python development environment..."

if [ -d "python/venv" ]; then
    cd python

    # Activate virtual environment
    if [ -f "venv/bin/activate" ]; then
        source venv/bin/activate
    elif [ -f "venv/Scripts/activate" ]; then
        source venv/Scripts/activate
    fi

    # Install development dependencies
    if [ -f "requirements-dev.txt" ]; then
        pip install -r requirements-dev.txt
    fi

    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    fi

    deactivate 2>/dev/null || true
    cd "$PROJECT_ROOT"
    log_success "Python development environment ready!"
else
    log_warn "Python venv not found, run ./scripts/setup.sh first"
fi

# ----- Node.js Development Setup -----
log_info "Setting up Node.js development environment..."

if [ -d "frontend" ] && [ -f "frontend/package.json" ]; then
    cd frontend
    npm install
    cd "$PROJECT_ROOT"
    log_success "Node.js development environment ready!"
else
    log_info "Frontend not initialized yet"
fi

# ----- Docker Development Network -----
log_info "Creating Docker development network..."

if ! docker network ls | grep -q "vectorflow-dev"; then
    docker network create vectorflow-dev 2>/dev/null || true
    log_success "Docker network 'vectorflow-dev' created!"
else
    log_info "Docker network 'vectorflow-dev' already exists"
fi

# ----- Local Services Check -----
log_info "Checking local development services..."

check_port() {
    local port=$1
    local service=$2
    if lsof -i :$port &>/dev/null || netstat -an 2>/dev/null | grep -q ":$port "; then
        log_warn "Port $port ($service) is already in use"
    else
        log_success "Port $port ($service) is available"
    fi
}

check_port ${GO_GATEWAY_PORT:-8080} "Go Gateway"
check_port ${RUST_WORKER_PORT:-8081} "Rust Worker"
check_port ${PYTHON_INFERENCE_PORT:-8082} "Python Inference"
check_port ${FRONTEND_PORT:-3000} "Frontend"

# ----- Create Development Config Files -----
log_info "Creating development configuration files..."

# Go air config for hot-reload
if [ ! -f "go/.air.toml" ]; then
cat > go/.air.toml << 'EOF'
root = "."
tmp_dir = "tmp"

[build]
  cmd = "go build -o ./tmp/gateway ./cmd/gateway"
  bin = "tmp/gateway"
  full_bin = "./tmp/gateway"
  include_ext = ["go", "tpl", "tmpl", "html"]
  exclude_dir = ["tmp", "vendor", "node_modules"]
  exclude_file = []
  delay = 1000
  stop_on_error = true
  send_interrupt = false
  kill_delay = 500

[log]
  time = false

[color]
  main = "magenta"
  watcher = "cyan"
  build = "yellow"
  runner = "green"

[misc]
  clean_on_exit = true
EOF
    log_success "Created Go air configuration"
fi

# ----- Summary -----
echo ""
echo "=============================================="
echo "   Development Setup Complete!"
echo "=============================================="
echo ""
echo "Start individual services:"
echo "  Go:     cd go && air"
echo "  Rust:   cd rust && cargo watch -x run"
echo "  Python: cd python && source venv/bin/activate && uvicorn app.api:app --reload"
echo "  Frontend: cd frontend && npm run dev"
echo ""
echo "Or start everything with Docker:"
echo "  make dev"
echo ""
