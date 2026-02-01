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

**Last Updated:** 2026-01-31  
**Version:** 1.0  
**License:** MIT LICENSE
