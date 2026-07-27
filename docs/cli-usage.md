# CLI Usage

PatchMox has one entry point: `bin/patchmox`.

```bash
patchmox check [--vmid ID] [--force-refresh]
patchmox notify [--channel smtp]
patchmox worker [--once] [--max-jobs N] [--daemon]
patchmox apply --vmid ID [--component virtio|qemu-ga]
patchmox policy --dry-run [--vmid ID]
patchmox state --vmid ID
patchmox help
```

## `patchmox check`

Main orchestration. Discovers Windows VMs, fetches latest versions, compares, shows/removes SVG nags, persists state, and enqueues auto-update jobs if the policy allows.

```bash
# All running Windows VMs
patchmox check

# Only VM 100
patchmox check --vmid 100

# Bypass version cache
patchmox check --force-refresh
```

Interactive terminals show a spinner and per-VM progress. Logs go to file and journal by default; set `PATCHMOX_CONSOLE_LOG=true` to also print to the terminal.

## `patchmox worker`

Processes update jobs from `queue/pending/`.

```bash
# Process one eligible job and exit
patchmox worker --once

# Process up to 5 jobs
patchmox worker --max-jobs 5

# Run as daemon
patchmox worker --daemon
```

## `patchmox notify`

Sends notifications through the configured channels (`NOTIFICATION_CHANNELS`).

```bash
# Send a test email to verify SMTP settings
patchmox notify --test

# Send a summary of currently active update nags
patchmox notify
```

The summary includes all VMs where the SVG nag is currently active. SMTP settings are read from `.env`.

## `patchmox apply`

Phase 1 stub. Manually trigger an update for a VM.

```bash
patchmox apply --vmid 100 --component virtio
```

## `patchmox policy`

Evaluate a sample event against loaded policies.

```bash
patchmox policy --dry-run --vmid 100
```

## `patchmox state`

Show persisted state for a VM.

```bash
patchmox state --vmid 100
```
