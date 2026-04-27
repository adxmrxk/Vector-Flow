#!/bin/bash
# =========================
# VectorFlow Tools Installer
# =========================
# Installs required development tools based on your OS

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "\n${CYAN}=== $1 ===${NC}\n"; }

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)     OS="linux";;
        Darwin*)    OS="macos";;
        MINGW*|MSYS*|CYGWIN*) OS="windows";;
        *)          OS="unknown";;
    esac
    echo "$OS"
}

OS=$(detect_os)

echo ""
echo "=============================================="
echo "   VectorFlow - Tools Installation Guide"
echo "=============================================="
echo ""
log_info "Detected OS: $OS"
echo ""

# ----- Installation Instructions by OS -----

if [ "$OS" == "windows" ]; then
    log_header "Windows Installation (using winget/chocolatey)"

    echo "Option 1: Using winget (Windows Package Manager)"
    echo "----------------------------------------------"
    echo "# Core Tools"
    echo "winget install Git.Git"
    echo "winget install Docker.DockerDesktop"
    echo ""
    echo "# Programming Languages"
    echo "winget install GoLang.Go"
    echo "winget install Rustlang.Rustup"
    echo "winget install Python.Python.3.11"
    echo "winget install OpenJS.NodeJS.LTS"
    echo ""
    echo "# DevOps Tools"
    echo "winget install Kubernetes.kubectl"
    echo "winget install Kubernetes.minikube"
    echo ""
    echo ""
    echo "Option 2: Using Chocolatey"
    echo "--------------------------"
    echo "# Install Chocolatey first (Run as Admin in PowerShell):"
    echo "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    echo ""
    echo "# Then install tools:"
    echo "choco install git docker-desktop golang rust python nodejs-lts kubectl minikube -y"
    echo ""
    echo "# For Ansible (via pip after Python install):"
    echo "pip install ansible"

elif [ "$OS" == "macos" ]; then
    log_header "macOS Installation (using Homebrew)"

    echo "# Install Homebrew first (if not installed):"
    echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    echo ""
    echo "# Install all tools:"
    echo "brew install git"
    echo "brew install --cask docker"
    echo "brew install go"
    echo "brew install rust"
    echo "brew install python@3.11"
    echo "brew install node"
    echo "brew install kubectl"
    echo "brew install minikube"
    echo "brew install ansible"
    echo "brew install helm"
    echo ""
    echo "# Or install all at once:"
    echo "brew install git go rust python@3.11 node kubectl minikube ansible helm && brew install --cask docker"

elif [ "$OS" == "linux" ]; then
    log_header "Linux Installation"

    echo "Ubuntu/Debian:"
    echo "--------------"
    echo "# Update packages"
    echo "sudo apt update && sudo apt upgrade -y"
    echo ""
    echo "# Install core tools"
    echo "sudo apt install -y git curl wget build-essential"
    echo ""
    echo "# Install Docker"
    echo "curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh"
    echo "sudo usermod -aG docker \$USER"
    echo ""
    echo "# Install Go"
    echo "wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz"
    echo "sudo tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz"
    echo 'echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.bashrc'
    echo ""
    echo "# Install Rust"
    echo "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo ""
    echo "# Install Python"
    echo "sudo apt install -y python3.11 python3.11-venv python3-pip"
    echo ""
    echo "# Install Node.js (via nvm)"
    echo "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash"
    echo "nvm install --lts"
    echo ""
    echo "# Install kubectl"
    echo "curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    echo "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
    echo ""
    echo "# Install minikube"
    echo "curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
    echo "sudo install minikube-linux-amd64 /usr/local/bin/minikube"
    echo ""
    echo "# Install Ansible"
    echo "pip3 install ansible"
    echo ""
    echo ""
    echo "Fedora/RHEL/CentOS:"
    echo "-------------------"
    echo "sudo dnf install -y git docker golang rust cargo python3 nodejs kubectl ansible"
fi

echo ""
log_header "Verification Commands"
echo "After installation, verify with:"
echo "  git --version"
echo "  docker --version"
echo "  go version"
echo "  cargo --version"
echo "  python3 --version"
echo "  node --version"
echo "  kubectl version --client"
echo "  ansible --version"

echo ""
log_header "Version Requirements"
echo "Minimum versions for VectorFlow:"
echo "  Git:     2.30+"
echo "  Docker:  24.0+"
echo "  Go:      1.21+"
echo "  Rust:    1.70+"
echo "  Python:  3.10+"
echo "  Node.js: 18.0+ (LTS)"
echo "  kubectl: 1.27+"

echo ""
log_header "Post-Installation"
echo "After installing all tools, run:"
echo "  ./scripts/setup.sh"
echo ""
