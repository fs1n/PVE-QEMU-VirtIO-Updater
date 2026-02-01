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

