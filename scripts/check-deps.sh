#!/bin/bash
# =========================
# VectorFlow Dependency Checker
# =========================
# Validates all required tools are installed and meet version requirements

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo ""
echo "=============================================="
echo "   VectorFlow - Dependency Check"
echo "=============================================="
echo ""

# ----- Version Comparison Helper -----
version_gte() {
    # Returns 0 if $1 >= $2
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

extract_version() {
    # Extract version number from string
    echo "$1" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}

# ----- Core Tools -----
log_info "Checking core tools..."

# Git
if command -v git &> /dev/null; then
    GIT_VERSION=$(extract_version "$(git --version)")
    if version_gte "$GIT_VERSION" "2.30"; then
        log_pass "Git $GIT_VERSION (>= 2.30 required)"
    else
        log_warn "Git $GIT_VERSION (>= 2.30 recommended)"
    fi
else
    log_fail "Git not installed"
fi

# Docker
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(extract_version "$(docker --version)")
    if version_gte "$DOCKER_VERSION" "24.0"; then
        log_pass "Docker $DOCKER_VERSION (>= 24.0 required)"
    else
        log_warn "Docker $DOCKER_VERSION (>= 24.0 recommended)"
    fi

    # Check if Docker daemon is running
    if docker info &> /dev/null; then
        log_pass "Docker daemon is running"
    else
        log_warn "Docker daemon is not running"
    fi
else
    log_fail "Docker not installed"
fi

# ----- Programming Languages -----
echo ""
log_info "Checking programming languages..."

# Go
if command -v go &> /dev/null; then
    GO_VERSION=$(extract_version "$(go version)")
    if version_gte "$GO_VERSION" "1.21"; then
        log_pass "Go $GO_VERSION (>= 1.21 required)"
    else
        log_fail "Go $GO_VERSION (>= 1.21 required)"
    fi
else
    log_fail "Go not installed"
fi

# Rust
if command -v rustc &> /dev/null; then
    RUST_VERSION=$(extract_version "$(rustc --version)")
    if version_gte "$RUST_VERSION" "1.70"; then
        log_pass "Rust $RUST_VERSION (>= 1.70 required)"
    else
        log_fail "Rust $RUST_VERSION (>= 1.70 required)"
    fi
else
    log_fail "Rust not installed"
fi

# Cargo
if command -v cargo &> /dev/null; then
    CARGO_VERSION=$(extract_version "$(cargo --version)")
    log_pass "Cargo $CARGO_VERSION"
else
    log_fail "Cargo not installed"
fi

# Python
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(extract_version "$(python3 --version)")
    if version_gte "$PYTHON_VERSION" "3.10"; then
        log_pass "Python $PYTHON_VERSION (>= 3.10 required)"
    else
        log_fail "Python $PYTHON_VERSION (>= 3.10 required)"
    fi
else
    log_fail "Python3 not installed"
fi

# pip
if command -v pip3 &> /dev/null || command -v pip &> /dev/null; then
    PIP_VERSION=$(extract_version "$(pip3 --version 2>/dev/null || pip --version)")
    log_pass "pip $PIP_VERSION"
else
    log_fail "pip not installed"
fi

# Node.js
if command -v node &> /dev/null; then
    NODE_VERSION=$(extract_version "$(node --version)")
    if version_gte "$NODE_VERSION" "18.0"; then
        log_pass "Node.js $NODE_VERSION (>= 18.0 required)"
    else
        log_fail "Node.js $NODE_VERSION (>= 18.0 required)"
    fi
else
    log_fail "Node.js not installed"
fi

# npm
if command -v npm &> /dev/null; then
    NPM_VERSION=$(extract_version "$(npm --version)")
    log_pass "npm $NPM_VERSION"
else
    log_fail "npm not installed"
fi

# ----- DevOps Tools -----
echo ""
log_info "Checking DevOps tools..."

# kubectl
if command -v kubectl &> /dev/null; then
    KUBECTL_VERSION=$(kubectl version --client -o json 2>/dev/null | grep -oE '"gitVersion": "[^"]+"' | grep -oE 'v[0-9]+\.[0-9]+' | tr -d 'v' || echo "unknown")
    log_pass "kubectl $KUBECTL_VERSION"
else
    log_warn "kubectl not installed (needed for Kubernetes deployment)"
fi

# minikube
if command -v minikube &> /dev/null; then
    MINIKUBE_VERSION=$(extract_version "$(minikube version)")
    log_pass "minikube $MINIKUBE_VERSION"
else
    log_warn "minikube not installed (needed for local K8s testing)"
fi

# Ansible
if command -v ansible &> /dev/null; then
    ANSIBLE_VERSION=$(extract_version "$(ansible --version | head -1)")
    log_pass "Ansible $ANSIBLE_VERSION"
else
    log_warn "Ansible not installed (needed for server provisioning)"
fi

# Helm
if command -v helm &> /dev/null; then
    HELM_VERSION=$(extract_version "$(helm version --short)")
    log_pass "Helm $HELM_VERSION"
else
    log_warn "Helm not installed (useful for K8s package management)"
fi

# ----- Optional Tools -----
echo ""
log_info "Checking optional tools..."

# Make
if command -v make &> /dev/null; then
    log_pass "make available"
else
    log_warn "make not installed (used for build automation)"
fi

# curl
if command -v curl &> /dev/null; then
    log_pass "curl available"
else
    log_warn "curl not installed"
fi

# jq
if command -v jq &> /dev/null; then
    log_pass "jq available (JSON processing)"
else
    log_warn "jq not installed (useful for JSON processing)"
fi

# ----- Summary -----
echo ""
echo "=============================================="
echo "   Summary"
echo "=============================================="
echo ""
echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${RED}Failed:${NC}   $FAILED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Some required dependencies are missing!${NC}"
    echo "Run ./scripts/install-tools.sh for installation instructions."
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}Some optional dependencies are missing.${NC}"
    echo "The project will work, but some features may be unavailable."
    exit 0
else
    echo -e "${GREEN}All dependencies are installed correctly!${NC}"
    exit 0
fi
