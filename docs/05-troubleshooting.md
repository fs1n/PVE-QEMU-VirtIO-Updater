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

