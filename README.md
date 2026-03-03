# PVE-QEMU-VirtIO-Updater

![Proxmox](https://img.shields.io/badge/proxmox-proxmox?style=for-the-badge&logo=proxmox&logoColor=%23E57000&labelColor=%232b2a33&color=%232b2a33)
![Bash Script](https://img.shields.io/badge/bash_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white)

Keep your VirtIO drivers and QEMU Guest Agent up to date on Proxmox VE. Inspired by how vCenter shows "VMware Tools update available"

## What is this?

I got tired of manually checking if my Windows VMs on Proxmox had outdated VirtIO drivers and QEMU Guest Agent versions. VMware's vCenter does this elegantly with a nice warning in the VM Overview, so I decided to build something similar for Proxmox VE.

**PVE-QEMU-VirtIO-Updater** is a host-side monitoring system that:

- **Discovers Windows VMs** on your Proxmox cluster automatically
- **Detects installed versions** of VirtIO drivers and QEMU Guest Agent via QEMU Guest Agent queries
- **Fetches latest releases** from Fedora People Archive
- **Displays update banners** in the Proxmox UI when updates are available (SVG nags)
- **Tracks state persistently** to avoid duplicate notifications and detect VM clones/restores
- **Optional guest-side updater** (PowerShell script) for in-VM automated updates

## Current Status

⚠️ **Work in Progress** - I'm building this as I have time.

**What works:**
- Host-side version detection (VirtIO + QEMU GA)
- SVG update notifications in Proxmox UI (Kind of 🙃)
- VM description updates (won't (shouldn't) break your existing VM notes)
- State tracking with vmgenid clone detection
- PowerShell guest updater script for VirtIO
- Logging framework (journal/syslog)

**Not Implemented Yet:**
- Notification channels (SMTP, webhook, MS Graph) - placeholders only
- Self-update mechanism - stub only
- Documentation may be ahead of actual code

## How it Works

```mermaid
graph LR
    A["main.sh<br/>(Cron/Timer)"] -->|load libs| B["lib/default.func<br/>lib/pve-interact.func<br/>lib/state.func<br/>lib/logger.func"]
    A -->|init| C["Logging<br/>State Dir"]
    A -->|query| D["Proxmox API<br/>pvesh/qm"]
    D -->|VM list<br/>Windows VMs| E["lib/pve-interact.func<br/>get_windows_vms"]
    E -->|guest exec| F["Windows VM<br/>QEMU Guest Agent"]
    F -->|version info| E
    E -->|current versions| A
    A -->|fetch| G["Fedora Archive<br/>VirtIO/QEMU GA"]
    G -->|latest versions| A
    A -->|compare versions| H["Version Logic"]
    H -->|check state| I["lib/state.func<br/>.state files"]
    I -->|load history| H
    H -->|updates needed?| J{"Show Nag?"}
    J -->|yes| K["lib/svg-nag.func<br/>render SVG"]
    K -->|write| L["/usr/share/pve-manager/images/<br/>update-VMID.svg"]
    K -->|link in desc| A
    A -->|update description| D
    D -->|UI displays banner| M["Proxmox UI<br/>VM Description"]
    A -->|persist state| I
    A -->|notify| N["lib/notification.func<br/>SMTP/Webhook/Graph"]
```

**Workflow:**

1. **Initialization**: `main.sh` sources libraries, initializes logging, creates state directory
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
7. **State Persistence**: Track vmgenid, versions, nag status per VM

## Visual Examples

### Update Banner in Proxmox UI

*Update Banner - Single Component*: SVG banner for VirtIO or QEMU GA update (single component).

*Update Banner - Both Components*: SVG banner when both VirtIO and QEMU GA updates are available.

> **Note:** Screenshots will be added in a future update. Banners appear in the VM Summary/Description area of the Proxmox web UI.

## Requirements

### Host Requirements (Proxmox Node)

- Proxmox VE 8.0+ (tested on 8.x and 9.x)
- Bash 4.0+
- Required utilities: `jq`, `curl`, `pvesh`, `qm`, `sed`, `awk`, `grep`

### Guest Requirements (Optional - for guest-side updater)

- Windows 10/11 or Windows Server 2016+ -> I don't have older systems to test on...
- PowerShell 7.0+
- QEMU Guest Agent installed and running

## Configuration

All configuration is managed via `.env` file. Copy `.env.example` to `.env` and customize as needed:

```bash
cp .env.example .env
```

Key configuration options:
- **Logging**: `LOG_LEVEL`, `LOG_FORMAT`, `LOG_DIR`
- **State Management**: `STATE_DIR`
- **SVG Templates**: `SVG_IMAGE_PATH`, `SVG_IMAGE_TEMPLATE`
- **Notifications** (not implemented): `NOTIFICATION_CHANNELS`, SMTP/webhook/MS Graph settings

# Installation

## Automated Installation (Recommended)

The easiest way to install and keep the tool updated. Runs as root, handles all setup automatically.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/fs1n/PVE-QEMU-VirtIO-Updater/main/install.sh)"
```

This will:
- ✓ Install to `/opt/pve-qemu-virtio-updater/`
- ✓ Backup and preserve existing configuration (`.env`, `.state/`, `logs/`)
- ✓ Set proper file permissions
- ✓ Check dependencies
- ✓ Work for both new installations and updates

## Manual Installation

If you prefer to install manually or modify the installation process:

### Clone the repository
```bash
git clone https://github.com/fs1n/PVE-QEMU-VirtIO-Updater.git
cd PVE-QEMU-VirtIO-Updater
```

### Create configuration
```bash
cp .env.example .env
```

### Edit configuration (optional - defaults work for most setups)
```bash
nano .env
```

### Make scripts executable
```bash
chmod +x main.sh lib/*.func
```

### Run manually for testing
```bash
./main.sh
```

# Quick Start / Running

## Run manually for testing
```bash
cd /opt/pve-qemu-virtio-updater
./main.sh
```

## Schedule automatic execution

Choose one of the following methods to run the updater regularly (e.g., daily):

### Option A: Cron Job
```bash
# Runs daily at 2 AM
echo "0 2 * * * /opt/pve-qemu-virtio-updater/main.sh" | crontab -
```

### Option B: Systemd Timer (Recommended)

Create the service file:
```bash
sudo tee /etc/systemd/system/pve-virtio-updater.service > /dev/null << 'EOF'
[Unit]
Description=PVE-QEMU-VirtIO-Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/pve-qemu-virtio-updater/main.sh
StandardOutput=journal
StandardError=journal
EOF
```

Create the timer file:
```bash
sudo tee /etc/systemd/system/pve-virtio-updater.timer > /dev/null << 'EOF'
[Unit]
Description=Run PVE-QEMU-VirtIO-Updater daily
Requires=pve-virtio-updater.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
```

Enable and start the timer:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now pve-virtio-updater.timer
```

Check status:
```bash
sudo systemctl status pve-virtio-updater.timer
sudo journalctl -u pve-virtio-updater.service -f
```

# Known Limitations

⚠️ **Current WIP Limitations:**

- **Notification Channels**: SMTP, MS Graph, and webhook integrations are placeholder code only (see `lib/notification.func`)
- **Self-Update**: `update.sh` is a stub header with no implementation
- **All Features**: Treat everything as work-in-progress and subject to change

# Roadmap

> **Note:** These are planned features, not commitments. Timelines are uncertain.

- [ ] **Notification Implementation**: Complete SMTP, webhook, and MS Graph notification channels
- [ ] **Self-Update Mechanism**: Implement `update.sh` for script auto-updates
- [ ] **Enhanced Clone Detection**: Improve vmgenid tracking and state validation
- [ ] **Error Handling**: Better error recovery and logging granularity


# License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
