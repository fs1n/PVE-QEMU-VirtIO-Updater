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

