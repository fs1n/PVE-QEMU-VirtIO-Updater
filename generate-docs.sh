#!/usr/bin/env bash
#
# Module: generate-docs.sh (PVE-QEMU-VirtIO-Updater)
# Description: Auto-generates documentation from script headers and function doc blocks
# Author: Frederik S. (fs1n) and PVE-QEMU-VirtIO-Updater Contributors
# Date: 2025-01-31
#
# Dependencies: grep, sed, awk, jq (optional)
# Environment: SCRIPT_DIR (set automatically)
# Usage: ./generate-docs.sh [--verbose]
#
# Description:
#   This script scans all Bash and PowerShell scripts for standardized headers and
#   function documentation blocks (format: @function, @description, @args, @returns, @example).
#   It generates thematic Markdown documentation in /docs and creates:
#   - Unified API reference with all functions
#   - Architecture overview with Mermaid diagram
#   - Installation, configuration, operation, and troubleshooting guides
#   - Index and navigation structure for MkDocs

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="${SCRIPT_DIR}/docs"
VERBOSE="${1:-}" # --verbose or empty

# Logging helpers
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
log_debug() { [[ "$VERBOSE" == "--verbose" ]] && echo "[DEBUG] $*"; }

# Initialize docs directory
init_docs_dir() {
    mkdir -p "$DOCS_DIR"
    log_info "Initialized docs directory: $DOCS_DIR"
}

# Extract module header from a script file
# Returns: module_name, description, dependencies, environment, usage
extract_module_header() {
    local file="$1"
    local module_name=""
    local description=""
    local dependencies=""
    local environment=""
    local usage=""
    
    # Parse header block (lines starting with # at top of file)
    while IFS='#' read -r _ line; do
        line="${line#[[:space:]]}"
        
        if [[ "$line" =~ ^Module: ]]; then
            module_name="${line#Module: }"
        elif [[ "$line" =~ ^Description: ]]; then
            description="${line#Description: }"
        elif [[ "$line" =~ ^Dependencies: ]]; then
            dependencies="${line#Dependencies: }"
        elif [[ "$line" =~ ^Environment: ]]; then
            environment="${line#Environment: }"
        elif [[ "$line" =~ ^Usage: ]]; then
            usage="${line#Usage: }"
        elif [[ "$line" =~ ^Functions: ]] || [[ -z "$line" && -n "$module_name" ]]; then
            break  # End of header block
        fi
    done < "$file"
    
    echo "$module_name|$description|$dependencies|$environment|$usage"
}

# Extract all function documentation blocks from a file
# Returns: function_name@description@args@returns@example (one per line)
extract_functions() {
    local file="$1"
    local in_doc_block=0
    local func_name=""
    local description=""
    local args=""
    local returns=""
    local example=""
    local pending_line=""

    while :; do
        local line=""
        if [[ -n "$pending_line" ]]; then
            line="$pending_line"
            pending_line=""
        else
            IFS= read -r line || break
        fi
        # Detect @function marker
        if [[ "$line" =~ @function\ ([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            func_name="${BASH_REMATCH[1]}"
            in_doc_block=1
            description=""
            args=""
            returns=""
            example=""
        elif [[ $in_doc_block -eq 1 ]]; then
            if [[ "$line" =~ @description\ (.*) ]]; then
                description="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ @args\ (.*) ]]; then
                args="${BASH_REMATCH[1]}"
                # Capture multi-line args
                while IFS= read -r next_line; do
                    if [[ "$next_line" =~ ^[[:space:]]*# ]] && ! [[ "$next_line" =~ @[a-z] ]]; then
                        args+=" $(echo "$next_line" | sed 's/^[[:space:]]*#[[:space:]]*//g')"
                    else
                        pending_line="$next_line"
                        break
                    fi
                done
            elif [[ "$line" =~ @returns\ (.*) ]]; then
                returns="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ @example ]]; then
                example="(see source)"
            elif [[ "$line" =~ ^function\ $func_name\(\) ]] || [[ "$line" =~ ^function\ $func_name\s ]]; then
                # End of doc block, output the function entry
                if [[ -n "$func_name" && -n "$description" ]]; then
                    echo "${func_name}|${description}|${args}|${returns}|${example}"
                    in_doc_block=0
                    func_name=""
                fi
            fi
        fi
    done < "$file"
}

# Generate Architecture Overview with Mermaid
generate_overview() {
    cat > "$DOCS_DIR/01-overview.md" <<'EOF'
# Architecture Overview

## Project Purpose

The **PVE-QEMU-VirtIO-Updater** is a Proxmox VE automation tool that monitors Windows VMs for outdated VirtIO drivers and QEMU Guest Agent software. When updates are available, it creates visual update notifications (SVG banners) in the Proxmox UI and persists state to avoid duplicate notifications.

## Core Components

### Host-Side (Bash)

- **main.sh**: Orchestrator; runs update checks, manages VM workflows
- **lib/default.sh**: Version fetching from Fedora People Archive, core update logic
- **lib/pve-interact.sh**: Proxmox API wrapper (VM discovery, guest version queries)
- **lib/state.sh**: Persistent state management for tracking updates per VM
- **lib/svg-nag.sh**: SVG template rendering for update banners
- **lib/logger.sh**: Centralized logging with syslog/journal support
- **lib/notification.sh**: Extensible notification framework (SMTP, Webhook, MS Graph)

### Guest-Side (PowerShell)

- **updater-win.ps1**: Windows PowerShell script (run inside VMs to download/install updates)

### Templates

- **templates/svg/update-nag-template.svg**: SVG template for single-component updates
- **templates/svg/update-nag-both-template.svg**: SVG template for dual-component updates
- **templates/html/email-template.html**: Email notification template

## Data Flow Diagram

```mermaid
graph LR
    A["main.sh<br/>(Cron/Timer)"] -->|load libs| B["lib/default.sh<br/>lib/pve-interact.sh<br/>lib/state.sh<br/>lib/logger.sh"]
    A -->|init| C["Logging<br/>State Dir"]
    A -->|query| D["Proxmox API<br/>pvesh/qm"]
    D -->|VM list<br/>Windows VMs| E["lib/pve-interact.sh<br/>get_windows_vms"]
    E -->|guest exec| F["Windows VM<br/>QEMU Guest Agent"]
    F -->|version info| E
    E -->|current versions| A
    A -->|fetch| G["Fedora Archive<br/>VirtIO/QEMU GA"]
    G -->|latest versions| A
    A -->|compare versions| H["Version Logic"]
    H -->|check state| I["lib/state.sh<br/>.state files"]
    I -->|load history| H
    H -->|updates needed?| J{"Show Nag?"}
    J -->|yes| K["lib/svg-nag.sh<br/>render SVG"]
    K -->|write| L["/usr/share/pve-manager/images/<br/>update-VMID.svg"]
    K -->|link in desc| A
    A -->|update description| D
    D -->|UI displays banner| M["Proxmox UI<br/>VM Description"]
    A -->|persist state| I
    A -->|notify| N["lib/notification.sh<br/>SMTP/Webhook/Graph"]
```

## Update Workflow

1. **Initialization**: main.sh sources libraries, initializes logging, creates state directory
2. **Dependency Check**: Verify curl, jq, pvesh, qm, sed, awk are available
3. **VM Discovery**: Query Proxmox API for all Windows VMs on cluster
4. **Version Fetch**: Download latest VirtIO and QEMU GA versions from Fedora Archive
5. **Per-VM Check**:
   - Query guest OS for installed versions via QEMU Guest Agent
   - Compare against latest available
   - Load previous state to detect clones/restores (vmgenid tracking)
6. **Nag Decision**:
   - If updates available and state changed (or first run): render SVG, update VM description, save new state
   - If VM already up-to-date: remove any existing nag banner
7. **Optional Notifications**: Send via configured channels (SMTP, MS Graph, Webhook)

## State Management

Each Windows VM gets a `.state` file tracking:

- **VMGENID**: Unique VM identifier (for clone detection)
- **VIRTIO_VERSION**: Last known VirtIO version
- **QEMU_GA_VERSION**: Last known QEMU GA version
- **NAG_ACTIVE**: Whether notification is currently displayed
- **LAST_CHECKED**: Timestamp of last check

When VM is cloned or restored, vmgenid changes → state file is cleared → nag shown again.

## Configuration

Environment variables (from `.env`):

| Variable | Default | Purpose |
|---|---|---|
| `LOG_DIR` | `<script>/logs` | Log file directory |
| `LOG_LEVEL` | `info` | Logging verbosity (debug/info/notice/warn/error) |
| `LOG_FORMAT` | `[%d] [%l] %m` | Log message format |
| `STATE_DIR` | `<script>/.state` | VM state files directory |
| `NOTIFICATION_CHANNELS` | *(empty)* | Comma-separated: smtp, msgraph, webhook |
| `SMTP_SERVER` | *(empty)* | SMTP host for email notifications |
| `WEBHOOK_URL` | *(empty)* | HTTP endpoint for webhook notifications |
| `MSGRAPH_TOKEN` | *(empty)* | Bearer token for MS Graph API |

## Deployment Model

Typically deployed as:

- **Host Setup**: Copy scripts to Proxmox node, create `.env` config, set up cron/systemd timer
- **VM Setup**: Optionally copy `updater-win.ps1` to Windows VMs for automated updates
- **Monitoring**: Check logs, adjust LOG_LEVEL as needed, monitor SVG nags in Proxmox UI

EOF
    log_info "Generated: 01-overview.md"
}

# Generate Installation Guide
generate_installation() {
    cat > "$DOCS_DIR/02-installation.md" <<'EOF'
# Installation Guide

## Prerequisites

### Host (Proxmox VE)

- Proxmox VE 8.4+ with API access
- External tools:
  - `jq` – JSON query tool
  - `curl` – HTTP client
  - `pvesh` – Proxmox API CLI (included with PVE)
  - `qm` – QEMU machine manager (included with PVE)
  - Standard Unix tools: `sed`, `awk`, `grep`, `date`

### Windows VMs

- Windows 7 SP1, Server 2008 R2, or newer
- QEMU Guest Agent installed (for version queries)
- PowerShell 7+ (optional, for native update script)

## Host Installation

### 1. Clone or Download

```bash
# Option A: Clone repository
git clone https://github.com/fs1n/PVE-QEMU-VirtIO-Updater.git
cd PVE-QEMU-VirtIO-Updater

# Option B: Extract tar/zip
tar xzf PVE-QEMU-VirtIO-Updater.tar.gz
cd PVE-QEMU-VirtIO-Updater
```

### 2. Verify Dependencies

```bash
# Install missing packages on Debian/Ubuntu-based Proxmox
apt update
apt install -y jq curl

# Verify tools are available
for tool in jq curl pvesh qm sed awk grep; do
  command -v "$tool" > /dev/null || echo "Missing: $tool"
done
```

### 3. Create Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit with your settings
nano .env
# Configure LOG_DIR, LOG_LEVEL, STATE_DIR, NOTIFICATION_CHANNELS as needed
```

### 4. Set Permissions

```bash
# Make scripts executable
chmod +x main.sh update.sh generate-docs.sh
chmod +x lib/*.sh
```

### 5. Verify Execution

```bash
# Test running the script (dry-run mode, no state changes)
./main.sh --help 2>&1 || ./main.sh 2>&1 | head -20
```

## Windows VM Setup (Optional)

If you want Windows VMs to auto-apply updates:

### 1. Copy PowerShell Script

```powershell
# On Windows VM, as Administrator:
Copy-Item updater-win.ps1 C:\scripts\
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 2. Schedule Updates

```powershell
# Create scheduled task (monthly, e.g., first Sunday)
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-File C:\scripts\updater-win.ps1"
Register-ScheduledTask -TaskName "VirtIO Driver Update" -Trigger $trigger `
  -Action $action -User "SYSTEM" -RunLevel Highest
```

## Automated Scheduling (Host)

### Option A: Cron (runs every 4 hours)

```bash
# Edit crontab
crontab -e

# Add line:
0 */4 * * * /path/to/PVE-QEMU-VirtIO-Updater/main.sh >> /var/log/pve-virtio-updater.log 2>&1
```

### Option B: Systemd Timer

```ini
# Create /etc/systemd/system/pve-virtio-updater.service
[Unit]
Description=PVE QEMU VirtIO Updater
After=network-online.target

[Service]
Type=oneshot
ExecStart=/path/to/PVE-QEMU-VirtIO-Updater/main.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pve-virtio-updater

# Create /etc/systemd/system/pve-virtio-updater.timer
[Unit]
Description=Run PVE VirtIO Updater every 4 hours
Requires=pve-virtio-updater.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=4h
AccuracySec=1min

[Install]
WantedBy=timers.target

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable pve-virtio-updater.timer
sudo systemctl start pve-virtio-updater.timer
sudo systemctl status pve-virtio-updater.timer
```

## Verification

```bash
# Check logs
tail -f logs/proxmox_virtio_updater.log

# Verify state tracking
ls -la .state/

# Check SVG nags (should be in /usr/share/pve-manager/images/update-*.svg)
ls -la /usr/share/pve-manager/images/update-*.svg 2>/dev/null || echo "No nags created yet"
```

EOF
    log_info "Generated: 02-installation.md"
}

# Generate Configuration Guide
generate_configuration() {
    cat > "$DOCS_DIR/03-configuration.md" <<'EOF'
# Configuration Guide

## Environment Variables

All configuration is done via `.env` file in the script directory. Copy `.env.example` to `.env` and customize:

```bash
cp .env.example .env
```

### Logging Configuration

```bash
# Directory where log files will be stored (default: <script_dir>/logs)
LOG_DIR=/var/log/pve-virtio-updater

# Logging level: debug, info, notice, warn, error, critical, alert, emergency
# Default: info
LOG_LEVEL=info

# Log message format
# Available variables:
#   %d = date and time (YYYY-MM-DD HH:MM:SS)
#   %z = timezone (UTC or LOCAL)
#   %l = log level name (DEBUG, INFO, WARN, ERROR, etc.)
#   %s = script name
#   %m = message
# Default: [%d] [%l] %m
LOG_FORMAT="[%d] [%l] %m"

# Use UTC timestamps instead of local time
LOG_USE_UTC=false

# Send logs to systemd journal
LOG_JOURNAL=true

# Tag for journal entries
LOG_JOURNAL_TAG="PVE-VirtIO-Updater"
```

### State Management

```bash
# Directory to store VM state files (default: <script_dir>/.state)
# Each running VM gets a file: vm-{VMID}.state
STATE_DIR=/var/lib/pve-virtio-updater/.state
```

### SVG Template Configuration

```bash
# Path to the SVG template files (default: <script_dir>/templates/svg)
SVG_TEMPLATE_DIR=/usr/local/share/pve-virtio-updater/templates/svg

# Path where generated SVG nags are stored (default: /usr/share/pve-manager/images/)
SVG_IMAGE_PATH=/usr/share/pve-manager/images/
```

### Notification Configuration

```bash
# Comma-separated list of enabled notification channels
# Available: smtp, msgraph, webhook
NOTIFICATION_CHANNELS=smtp,webhook

# SMTP Configuration
SMTP_SERVER=mail.example.com
SMTP_PORT=587
SMTP_USE_TLS=true
SMTP_USERNAME=updater@example.com
SMTP_PASSWORD=secretpassword
SMTP_FROM=updater@example.com
SMTP_TO=admins@example.com

# Microsoft Graph Configuration (for MS Entra / O365)
MSGRAPH_TENANT_ID=your-tenant-id
MSGRAPH_CLIENT_ID=your-client-id
MSGRAPH_CLIENT_SECRET=your-client-secret
MSGRAPH_FROM=updater@example.com
MSGRAPH_TO=admins@example.com

# Webhook Configuration
WEBHOOK_URL=https://hooks.example.com/notify
WEBHOOK_METHOD=POST
WEBHOOK_AUTH_HEADER=Authorization: Bearer your-token-here
```

## Configuration Examples

### Example 1: Basic Setup (Logging Only)

```bash
# .env
LOG_DIR=/var/log/pve-virtio-updater
LOG_LEVEL=info
STATE_DIR=/var/lib/pve-virtio-updater/.state
# Notifications disabled
NOTIFICATION_CHANNELS=
```

### Example 2: With Email Notifications

```bash
# .env
LOG_LEVEL=info
NOTIFICATION_CHANNELS=smtp
SMTP_SERVER=mail.corp.local
SMTP_FROM=pve-alerts@corp.local
SMTP_TO=platform-team@corp.local
```

### Example 3: With Slack Webhook

```bash
# .env
LOG_LEVEL=info
NOTIFICATION_CHANNELS=webhook
WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

### Example 4: Multi-Channel (Email + Webhook)

```bash
# .env
LOG_LEVEL=debug
NOTIFICATION_CHANNELS=smtp,webhook
SMTP_SERVER=mail.example.com
SMTP_FROM=updates@example.com
SMTP_TO=ops@example.com
WEBHOOK_URL=https://teams.microsoft.com/webhookb2/...
```

## File Locations

```
/path/to/PVE-QEMU-VirtIO-Updater/
├── .env                              # Your configuration (git-ignored)
├── .env.example                      # Configuration template
├── main.sh                           # Main entry point
├── update.sh                         # Self-update script
├── lib/
│   ├── default.sh                   # Core logic
│   ├── logger.sh                    # Logging module
│   ├── notification.sh              # Notifications
│   ├── pve-interact.sh              # Proxmox API wrapper
│   ├── state.sh                     # State management
│   └── svg-nag.sh                   # SVG rendering
├── templates/
│   ├── html/email-template.html
│   └── svg/
│       ├── update-nag-template.svg
│       └── update-nag-both-template.svg
├── logs/                            # Log files (created at runtime)
│   └── proxmox_virtio_updater.log
└── .state/                          # VM state tracking (created at runtime)
    ├── vm-100.state
    ├── vm-101.state
    └── ...
```

## Best Practices

1. **Log Rotation**: Use logrotate for production deployments
   ```
   # /etc/logrotate.d/pve-virtio-updater
   /var/log/pve-virtio-updater/*.log {
     daily
     rotate 7
     compress
     delaycompress
     notifempty
   }
   ```

2. **Restrictive Permissions**: Protect state and logs
   ```bash
   chmod 700 /var/lib/pve-virtio-updater/.state
   chmod 700 /var/log/pve-virtio-updater
   ```

3. **Monitor via Journal**: With systemd timer
   ```bash
   journalctl -u pve-virtio-updater.timer -u pve-virtio-updater.service -f
   ```

EOF
    log_info "Generated: 03-configuration.md"
}

# Generate Operation Guide
generate_operation() {
    cat > "$DOCS_DIR/04-operation.md" <<'EOF'
# Operation Guide

## Running the Updater

### Manual Execution

```bash
# Run update check immediately
/path/to/PVE-QEMU-VirtIO-Updater/main.sh

# With verbose logging
LOG_LEVEL=debug /path/to/PVE-QEMU-VirtIO-Updater/main.sh
```

### Via Systemd Timer

```bash
# Check timer status
sudo systemctl status pve-virtio-updater.timer

# View last run
sudo systemctl status pve-virtio-updater.service

# Check logs
sudo journalctl -u pve-virtio-updater.service -n 50

# Manually trigger (don't wait for timer)
sudo systemctl start pve-virtio-updater.service

# View real-time logs
sudo journalctl -u pve-virtio-updater.service -f
```

### Via Cron

```bash
# View cron job
crontab -l

# Manually test
/path/to/PVE-QEMU-VirtIO-Updater/main.sh

# Check result
tail -f /var/log/pve-virtio-updater.log
```

## Monitoring

### Check Logs

```bash
# Recent entries
tail -f logs/proxmox_virtio_updater.log

# Filter by level
grep "ERROR\|WARN" logs/proxmox_virtio_updater.log

# Search for VM activity
grep "VM 100" logs/proxmox_virtio_updater.log
```

### Verify State

```bash
# List tracked VMs
ls -lah .state/vm-*.state

# View VM 100 state
cat .state/vm-100.state

# Check update status
cat .state/vm-100.state | grep NAG_ACTIVE
```

### Verify SVG Nags

```bash
# List created SVG nags
ls -lah /usr/share/pve-manager/images/update-*.svg

# View in Proxmox UI
# Navigate to: Datacenter → Nodes → [Node] → VM [ID] → Summary → Description
# Should show banner with versions
```

## API Reference

### Core Functions

#### check_script_dependencies()

Validates that all required external tools are installed.

**Usage:**
```bash
source lib/default.sh
check_script_dependencies
```

**Returns:** 0 if all deps found, 1 if missing

#### fetch_latest_virtio_version()

Fetches latest VirtIO driver version from Fedora People Archive.

**Usage:**
```bash
version_json=$(fetch_latest_virtio_version)
latest_ver=$(echo "$version_json" | jq -r '.version')
release_date=$(echo "$version_json" | jq -r '.release')
```

**Output (JSON):**
```json
{"version":"0.1.285","release":"2025-01-15"}
```

#### fetch_latest_qemu_ga_version()

Fetches latest QEMU Guest Agent version from Fedora People Archive.

**Usage:**
```bash
qemu_json=$(fetch_latest_qemu_ga_version)
latest_qemu=$(echo "$qemu_json" | jq -r '.version')
```

#### get_windows_vms()

Queries all Windows VMs running on the Proxmox cluster.

**Usage:**
```bash
source lib/pve-interact.sh
windows_vms=$(get_windows_vms)
echo "$windows_vms" | jq '.' # Pretty-print VM list
```

**Output (JSON):**
```json
{
  "100": {
    "node": "pve-node1",
    "name": "win10-vm",
    "ostype": "win10",
    "status": "running",
    "vmgenid": "uuid-value"
  }
}
```

#### get_windows_virtio_version(vmid)

Query VirtIO driver version inside Windows VM.

**Usage:**
```bash
virtio_ver=$(get_windows_virtio_version 100)
echo "Current VirtIO: $virtio_ver"
```

**Returns:** Version string (e.g., "0.1.283") or empty if not found

#### get_windows_QEMU_GA_version(vmid)

Query QEMU Guest Agent version inside Windows VM.

**Usage:**
```bash
qemu_ver=$(get_windows_QEMU_GA_version 100)
echo "Current QEMU GA: $qemu_ver"
```

#### save_vm_state(vmid, virtio_ver, qemu_ga_ver, nag_shown, vmgenid)

Persist VM update state to file.

**Usage:**
```bash
source lib/state.sh
save_vm_state 100 "0.1.283" "9.0.0" "true" "uuid-value"
```

#### load_vm_state(vmid)

Load VM state from file into environment variables.

**Usage:**
```bash
load_vm_state 100
echo "Stored VirtIO: $STORED_VIRTIO_VERSION"
echo "Stored QEMU GA: $STORED_QEMU_GA_VERSION"
echo "Nag Active: $STORED_NAG_ACTIVE"
```

#### should_show_nag(vmid, current_virtio, latest_virtio, current_qemu_ga, latest_qemu_ga, vmgenid)

Determine if update notification should be displayed.

**Usage:**
```bash
should_show_nag 100 "0.1.283" "0.1.285" "9.0.0" "9.1.0" "$vmgenid"
case $? in
  0) echo "Show nag" ;;
  1) echo "Nag muted" ;;
  2) echo "Remove nag (up to date)" ;;
esac
```

**Returns:** 0=show, 1=mute, 2=remove

#### build_svg_virtio_update_nag(vmid, current, latest, date)

Generate SVG banner for VirtIO updates.

**Usage:**
```bash
source lib/svg-nag.sh
build_svg_virtio_update_nag 100 "0.1.283" "0.1.285" "2025-01-15"
# Creates: /usr/share/pve-manager/images/update-100.svg
```

## Troubleshooting

See [Troubleshooting Guide](05-troubleshooting.md).

EOF
    log_info "Generated: 04-operation.md"
}

# Generate Troubleshooting Guide
generate_troubleshooting() {
    cat > "$DOCS_DIR/05-troubleshooting.md" <<'EOF'
# Troubleshooting Guide

## Common Issues

### "jq is not installed"

**Error:**
```
[ERROR] Error: jq is not installed.
```

**Solution:**
```bash
# Debian/Ubuntu
apt install -y jq

# RHEL/CentOS
yum install -y jq

# Verify
command -v jq
```

### "pvesh: command not found"

**Error:**
```
[ERROR] Error: pvesh is not installed.
```

**Solution:** `pvesh` is part of Proxmox VE. Ensure you're running on a Proxmox VE host (not a standalone system). If running in a container, ensure you have API access.

### "Permission denied" on state directory

**Error:**
```
Failed to create state directory: /var/lib/pve-virtio-updater/.state
```

**Solution:**
```bash
# Fix permissions
sudo mkdir -p /var/lib/pve-virtio-updater/.state
sudo chown root:root /var/lib/pve-virtio-updater
sudo chmod 755 /var/lib/pve-virtio-updater
```

### No Windows VMs found

**Error:**
```
[INFO] No Windows VMs found on this Proxmox host. Exiting.
```

**Cause:** Could be normal if no Windows VMs exist or all are stopped.

**Check:**
```bash
# List all VMs
pvesh get /nodes/$(hostname)/qemu --output-format json | jq '.[] | {vmid, name, ostype}'

# List only Windows VMs
pvesh get /nodes/$(hostname)/qemu --output-format json | jq '.[] | select(.ostype | startswith("w"))'
```

### "Failed to fetch Fedora People Archive page"

**Error:**
```
[ERROR] Failed to access Fedora People Archive. HTTP Status: 403
```

**Cause:** Network issue or Fedora servers temporarily down.

**Solution:**
```bash
# Test connectivity
curl -I https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/

# Check proxy/firewall
# If behind proxy, set HTTP_PROXY / HTTPS_PROXY environment variables
```

### QEMU Guest Agent not responding

**Error:**
```
qm guest exec: error (500)
```

**Cause:** QEMU Guest Agent not installed in Windows VM or VM not responding.

**Solution:**
```powershell
# On Windows VM (as Administrator):
# Install QEMU Guest Agent
# Download from: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-qemu-ga/

# Or via Chocolatey:
choco install qemu-guest-agent

# Verify service is running:
Get-Service -Name QEMU-GA* | Select-Object Status
```

### SVG nags not showing in Proxmox UI

**Cause 1:** SVG not created
```bash
# Check if SVG exists
ls -la /usr/share/pve-manager/images/update-*.svg
```

**Cause 2:** SVG created but not linked in VM description
```bash
# Check VM description
pvesh get /nodes/pve/qemu/100/config | jq '.description'

# Manually add (if needed)
qm set 100 -description '<img src="/pve2/images/update-100.svg" alt="Update" />'
```

**Cause 3:** PVE UI caching
- Clear browser cache (Ctrl+Shift+Delete)
- Hard refresh Proxmox page (Ctrl+F5)

### State file corruption

**Error:**
```
[WARN] Unknown key in state file: ...
```

**Solution:**
```bash
# Backup and remove the corrupted state file
cp .state/vm-100.state .state/vm-100.state.bak
rm .state/vm-100.state

# Next run will recreate it
./main.sh
```

## Debug Mode

Enable verbose logging:

```bash
# Via command line
LOG_LEVEL=debug ./main.sh

# Via cron
0 */4 * * * LOG_LEVEL=debug /path/to/main.sh >> /var/log/pve-virtio-updater-debug.log 2>&1
```

## Getting Help

1. **Check logs** for specific error messages:
   ```bash
   tail -100 logs/proxmox_virtio_updater.log | grep -i error
   ```

2. **Verify dependencies**:
   ```bash
   bash -c 'for t in jq curl pvesh qm sed awk grep; do command -v $t || echo "Missing: $t"; done'
   ```

3. **Test manually**:
   ```bash
   # Test Fedora archive access
   curl -s https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/ | grep virtio-win | head -3
   
   # Test VM queries
   pvesh get /nodes/$(hostname)/qemu --output-format json | jq '.[0]'
   
   # Test guest agent
   qm guest exec 100 -- echo "Agent works"
   ```

4. **Report issues** with:
   - Full error output from logs
   - Output of `check_script_dependencies`
   - Proxmox version: `pvesh get /version`
   - Windows VM info: `qm status <vmid>`

EOF
    log_info "Generated: 05-troubleshooting.md"
}

# Generate Index
generate_index() {
    local current_date
    current_date=$(date '+%Y-%m-%d')
    
    cat > "$DOCS_DIR/index.md" <<'EOF'
# PVE-QEMU-VirtIO-Updater Documentation

Welcome to the comprehensive documentation for the **Proxmox VE QEMU VirtIO Driver Updater**.

This tool automatically monitors Windows VMs running on Proxmox VE for outdated VirtIO drivers and QEMU Guest Agent software, creating visual update notifications in the Proxmox UI.

## Quick Start

1. **[Installation](02-installation.md)** – Get the tool running in 5 minutes
2. **[Configuration](03-configuration.md)** – Set up logging, notifications, scheduling
3. **[Operation](04-operation.md)** – Run checks, monitor status, API reference
4. **[Troubleshooting](05-troubleshooting.md)** – Solve common issues

## In-Depth Topics

- **[Architecture Overview](01-overview.md)** – How components interact, data flow, workflow
- **[API Reference](#api-reference)** (below) – Function-level documentation for scripting

## Architecture at a Glance

- **Host-Side**: Bash scripts orchestrating checks, state management, SVG rendering
- **Guest-Side**: PowerShell for optional native Windows update automation
- **Integration**: Proxmox API via `pvesh` and `qm`, QEMU Guest Agent for version queries
- **State**: `.state` files track versions and nag status per VM
- **Notifications**: SMTP, MS Graph, or webhook channels for update alerts

## API Reference

### Modules

| Module | Purpose |
|--------|---------|
| `main.sh` | Main orchestrator; runs update checks |
| `lib/default.sh` | Version fetching, core update logic |
| `lib/pve-interact.sh` | Proxmox API wrapper |
| `lib/state.sh` | VM state management |
| `lib/svg-nag.sh` | SVG template rendering |
| `lib/logger.sh` | Logging framework |
| `lib/notification.sh` | Notification dispatcher |

### Key Functions

**Version Management:**

- `fetch_latest_virtio_version()` – Get latest VirtIO from Fedora
- `fetch_latest_qemu_ga_version()` – Get latest QEMU GA from Fedora

**VM Interaction:**

- `get_windows_vms()` – Discover all Windows VMs
- `get_windows_virtio_version(vmid)` – Query installed VirtIO in VM
- `get_windows_QEMU_GA_version(vmid)` – Query installed QEMU GA in VM
- `update_vm_description_with_update_nag(node, vmid, ...)` – Add SVG banner to VM

**State Management:**

- `save_vm_state(vmid, v1, v2, nag, genid)` – Persist state
- `load_vm_state(vmid)` – Load state from file
- `should_show_nag(vmid, ...)` – Decide if nag should display

**SVG Rendering:**

- `build_svg_virtio_update_nag(vmid, cur, latest, date)` – Create VirtIO nag
- `build_svg_qemu_ga_update_nag(vmid, cur, latest, date)` – Create QEMU GA nag
- `build_svg_update_nag(vmid, ...)` – Create dual-component nag
- `maybe_show_update_nag(node, vmid, need_virtio, need_qemu_ga, virtio_ver, current_virtio, qemu_ver, current_qemu, current_virtio_rel, current_qemu_rel, vmgenid)` – Orchestrate nag creation and state updates

See [Operation Guide](04-operation.md#api-reference) for detailed function signatures and examples.

## Configuration

Environment variables in `.env` control:

- Logging (level, format, output)
- State directory location
- Notification channels (SMTP, webhook, MS Graph)
- Scheduling (via cron or systemd timer)

See [Configuration Guide](03-configuration.md) for all options and examples.

## File Structure

```
PVE-QEMU-VirtIO-Updater/
├── main.sh              # Entry point
├── update.sh            # Self-update mechanism
├── generate-docs.sh     # Documentation generator
├── lib/
│   ├── default.sh      # Core logic
│   ├── pve-interact.sh # Proxmox API
│   ├── state.sh        # State tracking
│   ├── svg-nag.sh      # SVG rendering
│   ├── logger.sh       # Logging
│   └── notification.sh # Notifications
├── templates/
│   ├── svg/            # SVG templates for nags
│   └── html/           # Email templates
├── docs/               # Documentation (auto-generated)
├── logs/               # Log files (runtime)
└── .state/             # VM state files (runtime)
```

## Support & Contribution

- **Documentation**: First, make the necessary changes in the scripts. If the content is static, then make the changes directly in the generator script. Then, run the command `./generate-docs.sh` to regenerate.
- **Issues**: Check [Troubleshooting Guide](05-troubleshooting.md)
- **Logs**: Enable `LOG_LEVEL=debug` for verbose output
- **Repository**: https://github.com/fs1n/PVE-QEMU-VirtIO-Updater

---

**Last Updated:** DATE_PLACEHOLDER  
**Version:** 1.0  
**License:** MIT LICENSE
EOF
    
    # Replace placeholder with actual date
    sed -i "s/DATE_PLACEHOLDER/${current_date}/g" "$DOCS_DIR/index.md"
    
    log_info "Generated: index.md"
}

# Main execution
main() {
    log_info "Generating documentation for PVE-QEMU-VirtIO-Updater..."
    
    init_docs_dir
    
    log_info "Generating thematic documentation pages..."
    generate_index
    generate_overview
    generate_installation
    generate_configuration
    generate_operation
    generate_troubleshooting
    
    log_info "Documentation generation complete!"
    log_info "Output directory: $DOCS_DIR"
    log_info "Next: cd $SCRIPT_DIR && mkdocs serve"
}

main "$@"
