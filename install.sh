#!/usr/bin/env bash

################################################################################
# PVE-QEMU-VirtIO-Updater Installation Script
# 
# This script installs or updates the PVE-QEMU-VirtIO-Updater tool.
# Usage: bash install.sh
#        curl -fsSL https://raw.githubusercontent.com/fs1n/PVE-QEMU-VirtIO-Updater/main/install.sh | bash
#
# Requirements:
#   - Root privileges
#   - Debian/Proxmox system
#   - git (optional, but recommended for updates)
#
################################################################################

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

INSTALL_DIR="/opt/pve-qemu-virtio-updater"
REPO_URL="https://github.com/fs1n/PVE-QEMU-VirtIO-Updater.git"
SCRIPT_NAME="$(basename "$0")"
BACKUP_DIR=$(mktemp -d)

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_step() {
    echo -e "\n${BLUE}→${NC} $1"
}

cleanup_backup_dir() {
    if [[ -d "$BACKUP_DIR" ]]; then
        rm -rf "$BACKUP_DIR"
    fi
}

trap cleanup_backup_dir EXIT

# ============================================================================
# Pre-Flight Checks
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Run with: sudo bash $SCRIPT_NAME"
        exit 1
    fi
    print_success "Running as root"
}

check_os_compatibility() {
    if [[ ! -f /etc/os-release ]]; then
        print_warning "Could not determine OS type"
        return
    fi
    
    . /etc/os-release
    if [[ "$ID" == "debian" ]] || [[ "$ID" == "proxmox" ]] || grep -q "Debian\|Proxmox" /etc/issue 2>/dev/null; then
        print_success "Debian/Proxmox-based system detected"
    else
        print_warning "System is not Debian/Proxmox-based (detected: $ID). This tool is optimized for Proxmox VE on Debian."
    fi
}

check_proxmox_environment() {
    if [[ -f /etc/pve/version ]] || command -v pveversion &>/dev/null; then
        print_success "Proxmox VE environment detected"
    else
        print_warning "Proxmox VE does not appear to be installed. This tool requires Proxmox VE to function."
        echo "    Continuing anyway - ensure this system is a Proxmox VE host."
    fi
}

check_git_availability() {
    if ! command -v git &>/dev/null; then
        print_error "git is required but not installed"
        echo ""
        echo "Install git with:"
        echo "  apt update && apt install -y git"
        echo ""
        exit 1
    fi
    print_success "git is available ($(git --version))"
}

# ============================================================================
# Installation/Update Logic
# ============================================================================

backup_existing_config() {
    print_step "Backing up existing user data..."
    
    if [[ ! -d "$INSTALL_DIR" ]]; then
        return 0  # Nothing to backup
    fi
    
    # Backup .env if it exists
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        cp "$INSTALL_DIR/.env" "$BACKUP_DIR/.env"
        print_success "Backed up .env"
    fi
    
    # Backup .state directory if it exists
    if [[ -d "$INSTALL_DIR/.state" ]]; then
        cp -r "$INSTALL_DIR/.state" "$BACKUP_DIR/.state"
        print_success "Backed up .state directory"
    fi
    
    # Backup logs directory if it exists
    if [[ -d "$INSTALL_DIR/logs" ]]; then
        cp -r "$INSTALL_DIR/logs" "$BACKUP_DIR/logs"
        print_success "Backed up logs directory"
    fi
}

is_new_installation() {
    [[ ! -d "$INSTALL_DIR" ]]
}

install_from_git() {
    print_step "Cloning repository..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    print_success "Repository cloned to $INSTALL_DIR"
}

update_from_git() {
    print_step "Updating existing installation..."
    cd "$INSTALL_DIR"
    git fetch origin
    git reset --hard origin/main
    print_success "Repository updated from origin/main"
}

restore_user_data() {
    print_step "Restoring user data..."
    
    # Restore .env (only if it existed before)
    if [[ -f "$BACKUP_DIR/.env" ]]; then
        cp "$BACKUP_DIR/.env" "$INSTALL_DIR/.env"
        print_success "Restored .env"
    fi
    
    # Restore .state directory (merge with any new state)
    if [[ -d "$BACKUP_DIR/.state" ]]; then
        mkdir -p "$INSTALL_DIR/.state"
        cp -r "$BACKUP_DIR/.state"/* "$INSTALL_DIR/.state/" 2>/dev/null || true
        print_success "Restored .state directory"
    fi
    
    # Restore logs directory
    if [[ -d "$BACKUP_DIR/logs" ]]; then
        mkdir -p "$INSTALL_DIR/logs"
        cp -r "$BACKUP_DIR/logs"/* "$INSTALL_DIR/logs/" 2>/dev/null || true
        print_success "Restored logs directory"
    fi
}

copy_env_example() {
    if [[ ! -f "$INSTALL_DIR/.env" ]] && [[ -f "$INSTALL_DIR/.env.example" ]]; then
        cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
        print_success "Created .env from .env.example"
    fi
}

set_permissions() {
    print_step "Setting file permissions..."
    
    # Make main.sh executable
    chmod +x "$INSTALL_DIR/main.sh"
    print_success "main.sh is executable"
    
    # Make lib functions executable
    if [[ -d "$INSTALL_DIR/lib" ]]; then
        chmod +x "$INSTALL_DIR/lib"/*.func 2>/dev/null || true
        print_success "Library functions are executable"
    fi
    
    # Ensure directory permissions for logs and state
    mkdir -p "$INSTALL_DIR/logs" "$INSTALL_DIR/.state"
    chmod 755 "$INSTALL_DIR/logs" "$INSTALL_DIR/.state"
    print_success "Log and state directories are ready"
}

check_svg_image_path() {
    SVG_PATH="/usr/share/pve-manager/images"
    
    if [[ -d "$SVG_PATH" ]]; then
        if [[ -w "$SVG_PATH" ]]; then
            print_success "SVG image path is writable: $SVG_PATH"
        else
            print_warning "SVG image path exists but is not writable: $SVG_PATH"
            echo "        The script will need write access when running. Consider using sudo or appropriate permissions."
        fi
    else
        print_warning "SVG image path does not exist: $SVG_PATH"
        echo "        This is expected on non-Proxmox systems."
    fi
}

# ============================================================================
# Dependency Checking
# ============================================================================

check_dependencies() {
    print_step "Checking dependencies..."
    
    local -a required_tools=("curl" "jq")
    local -a optional_tools=("pvesh" "qm" "logger")
    local -a missing_required=()
    local -a missing_optional=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_required+=("$tool")
        else
            print_success "$tool is available"
        fi
    done
    
    for tool in "${optional_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing_optional+=("$tool")
        else
            print_success "$tool is available"
        fi
    done
    
    # Report missing required dependencies
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_required[*]}"
        echo ""
        echo "Install them with:"
        echo "  apt update && apt install -y ${missing_required[*]}"
        echo ""
        exit 1
    fi
    
    # Report missing optional dependencies
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        print_warning "Missing Proxmox tools: ${missing_optional[*]}"
        echo "        This tool requires Proxmox VE to function fully."
        echo "        Install it on a Proxmox VE host, or install missing tools with:"
        echo "        apt update && apt install -y proxmox-ve"
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    print_header "PVE-QEMU-VirtIO-Updater Installation"
    
    # Pre-flight checks
    check_root
    check_os_compatibility
    check_proxmox_environment
    check_git_availability
    
    # Dependency check
    check_dependencies
    
    # Installation/update logic
    if is_new_installation; then
        print_header "New Installation"
        install_from_git
        copy_env_example
    else
        print_header "Updating Existing Installation"
        backup_existing_config
        update_from_git
        restore_user_data
        copy_env_example
    fi
    
    # Post-installation setup
    set_permissions
    check_svg_image_path
    
    # Success message
    print_header "Installation Complete"
    print_success "PVE-QEMU-VirtIO-Updater installed to: $INSTALL_DIR"
    echo ""
    print_warning "Next steps:"
    echo ""
    echo "1. Review and customize configuration:"
    echo "   nano $INSTALL_DIR/.env"
    echo ""
    echo "2. Test the installation:"
    echo "   cd $INSTALL_DIR && ./main.sh"
    echo ""
    echo "3. Set up automatic execution. Choose one:"
    echo ""
    echo "   a) Cron job (runs daily at 2 AM):"
    echo "      echo '0 2 * * * $INSTALL_DIR/main.sh' | crontab -"
    echo ""
    echo "   b) Systemd timer (more reliable on modern systems):"
    echo "      cat > /etc/systemd/system/pve-virtio-updater.service << 'EOF'"
    echo "      [Unit]"
    echo "      Description=PVE-QEMU-VirtIO-Updater"
    echo "      After=network-online.target"
    echo "      Wants=network-online.target"
    echo ""
    echo "      [Service]"
    echo "      Type=oneshot"
    echo "      ExecStart=$INSTALL_DIR/main.sh"
    echo "      StandardOutput=journal"
    echo "      StandardError=journal"
    echo "      EOF"
    echo ""
    echo "      cat > /etc/systemd/system/pve-virtio-updater.timer << 'EOF'"
    echo "      [Unit]"
    echo "      Description=Run PVE-QEMU-VirtIO-Updater daily"
    echo "      Requires=pve-virtio-updater.service"
    echo ""
    echo "      [Timer]"
    echo "      OnCalendar=daily"
    echo "      OnCalendar=02:00"
    echo "      Persistent=true"
    echo ""
    echo "      [Install]"
    echo "      WantedBy=timers.target"
    echo "      EOF"
    echo ""
    echo "      systemctl daemon-reload"
    echo "      systemctl enable --now pve-virtio-updater.timer"
    echo ""
    echo "Documentation: https://github.com/fs1n/PVE-QEMU-VirtIO-Updater"
    echo ""
}

# Execute main function
main "$@"
