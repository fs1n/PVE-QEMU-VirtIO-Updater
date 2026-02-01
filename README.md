# PVE-QEMU-VirtIO-Updater

![PowerShell](https://img.shields.io/badge/PowerShell-%235391FE.svg?style=for-the-badge&logo=powershell&logoColor=white)
![Proxmox](https://img.shields.io/badge/proxmox-proxmox?style=for-the-badge&logo=proxmox&logoColor=%23E57000&labelColor=%232b2a33&color=%232b2a33)
![Bash Script](https://img.shields.io/badge/bash_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white)

Keep your VirtIO drivers and QEMU Guest Agent up to date on Proxmox VE. Inspired by how vCenter shows "VMware Tools update available"

## What is this?

I got tired of manually checking if my Windows VMs on Proxmox had outdated VirtIO drivers. VMware's vCenter does this elegantly with a nice warning in the VM Overview, so I decided to build something similar for ProxmoxVE.

## Current Status

⚠️ **Work in Progress** - I'm building this as I have time.

**What works:**
- PowerShell updater script for VirtIO
- SVG update notifications in Proxmox (Kind of 🙃)
- PVE description updates (won't (shouldn't) break your existing VM notes) -> Prepend Notification Banner

## Quick Start

### Option 1: Update from inside a Windows VM

```powershell
# Just run this in PowerShell 7
.\updater-win.ps1
