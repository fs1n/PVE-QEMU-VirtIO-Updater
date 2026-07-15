# PatchMox Architecture & Modularization Plan

> **Project rename in progress.** The repository may still be named `PVE-QEMU-VirtIO-Updater` on GitHub, but the project, CLI, and all runtime identities must use **PatchMox** from now on. See the [Rename checklist](#rename-checklist) for every location that must change.

## Guiding principle

Build an **event-driven pipeline with a policy engine**, stay in Bash, stay filesystem-based, and strictly separate **detection** from **decision** from **action**. Each new feature (Windows Updates, template freshness, auto-update) must become a new source/action/channel module, not another `if` block in the main script.

## Architecture layers

```
Trigger ──▶ Source ──▶ Event Bus ──▶ Policy Evaluator ──▶ Actions + Channels
```

| Layer | Responsibility | Example units |
|---|---|---|
| **Trigger** | When to run | cron, systemd timer, webhook, manual CLI |
| **Source** | What to inspect | VirtIO/QEMU-GA check, Windows Update scan, template freshness check |
| **Event Bus** | Canonical facts emitted as JSON events | `vm.checked`, `update.available`, `nag.shown`, `update.queued`, `update.applied`, `template.stale` |
| **Policy Evaluator** | Decides if an action is allowed | notify-only, auto-approve in maintenance window, never-auto-update production |
| **Actions** | Mutates Proxmox / guests | show nag, remove nag, enqueue update, apply update, refresh template |
| **Channels** | Sends notifications outward | SMTP, MS Graph, webhook, Teams |

The key insight: **policies and channels consume events**, they are not wired directly into `check-vm-updates.sh`.

## Why not a DAG

DAGs solve **execution-order complexity** (e.g. step B needs A and C, D needs B, retry B 3×). PatchMox workflows are mostly sequential per VM:

```
detect → decide → notify → optionally act
```

The real complexity is **conditional branching** (maintenance window, VM tags, risk class, cluster vs. single node). A DAG tool like Dagu forces you to express conditionals as graph edges and adds a database, UI, and upgrade surface you do not need. If Bash is ever outgrown, prefer a single static binary workflow engine or a small SQLite-backed job queue — not today.

## Module layout

```
patchmox/
├── bin/patchmox                # single entry point
├── lib/
│   ├── core/                   # engine: events, policy eval, state, queue
│   │   ├── events.func         # emit_event, event_log, event_filter
│   │   ├── policy.func         # evaluate_policy, load_policies
│   │   ├── state.func          # state files + derived cache
│   │   └── queue.func          # job queue primitives
│   ├── sources/                # detection modules
│   │   ├── virtio.source
│   │   ├── windows-update.source
│   │   └── template.source
│   ├── actions/                # mutators
│   │   ├── show-nag.action
│   │   ├── remove-nag.action
│   │   ├── enqueue-update.action
│   │   └── apply-update.action
│   └── channels/               # notification adapters
│       ├── smtp.channel
│       ├── msgraph.channel
│       └── webhook.channel
├── policies/
│   ├── 00-default.policy
│   ├── 10-maintenance-window.policy
│   └── 20-templates.policy
├── queue/                      # runtime job queue (or .state/queue/)
│   ├── pending/
│   ├── claimed/
│   ├── running/
│   ├── done/
│   └── failed/
└── templates/
```

## CLI surface

```bash
patchmox check [--vmid ID]
patchmox notify [--channel smtp]
patchmox worker [--once] [--max-jobs N]
patchmox apply --vmid ID [--component virtio|qemu-ga]
patchmox policy --dry-run [--vmid ID]
patchmox state --vmid ID
```

## Module interface contracts

Every module must implement one of these minimal contracts.

### Source

```bash
# Receives the global context, emits one JSON event per line to stdout.
source_emit() {
  # inputs:  global config, vm list, optional --vmid filter
  # outputs: newline-delimited JSON events
}
```

Example event:

```json
{
  "event_id": "<uuid>",
  "timestamp": "2026-07-15T02:00:01Z",
  "type": "update.available",
  "vmid": 100,
  "node": "pve-01",
  "components": ["virtio", "qemu-ga"],
  "current": {"virtio": "0.1.283", "qemu_ga": "9.0.0"},
  "latest": {"virtio": "0.1.285", "qemu_ga": "9.1.0"},
  "vmgenid": "uuid-or-fallback"
}
```

### Action

```bash
# Receives an event and the policy decision, executes the mutation.
action_run() {
  # input:  event JSON + policy decision JSON on stdin or as args
  # output: new event(s) to stdout (e.g. update.applied, nag.shown)
}
```

### Channel

```bash
# Receives an event and sends it out.
channel_send() {
  # input:  event JSON + channel config
  # output: nothing on success, error to stderr
}
```

### Policy

Policy files are ordered data, not code. A policy is evaluated top-down; the first matching policy wins.

```json
{
  "name": "maintenance-window-auto-update",
  "match": {
    "tags": ["lab"],
    "components": ["virtio", "qemu-ga"]
  },
  "decision": {
    "notify": true,
    "action": "auto-update",
    "maintenance_window": "02:00-04:00",
    "max_concurrent": 2,
    "require_snapshot": true
  }
}
```

Default decision if no policy matches:

```json
{"notify": true, "action": "none"}
```

## Concurrency model

The slow part is not the orchestrator CPU; it is the **per-VM guest-agent round-trip**. Do not use an unbounded fork bomb.

### Default: serial per Proxmox node

Group discovered VMs by node and serialize checks within a node. This respects the QEMU guest-agent socket and avoids lock contention on the node.

```bash
for node in $(echo "$windows_vms" | jq -r '.[].node' | sort -u); do
  # run each node's batch in a background process
  process_node "$node" "$windows_vms" &
done
wait
```

### Optional: `--max-node-concurrency=N`

Within a node, optionally allow up to `N` parallel VM checks. Use a small Bash worker pool only when measured throughput demands it.

### Avoid

- GNU `parallel` or external orchestrators as default dependencies.
- Running updates and checks in the same process. Detection must be decoupled from execution.

## Queue and worker split

The orchestrator (`patchmox check`) must **detect and enqueue**, then exit. The actual update execution happens in a separate `patchmox worker` process. This separation is critical because:

- check and update have different cadences and risk profiles,
- a failed update must not abort the discovery run,
- retries/backoffs live in the worker, not the check script.

### Queue directory layout

```
queue/
├── pending/        # jobs waiting
├── claimed/        # atomically moved here by a worker to prevent double-execution
├── running/        # contains pid + start time metadata
├── done/           # completed jobs, kept for audit
└── failed/         # exceeded retry limit, requires human attention
```

### Job file schema

```json
{
  "event_id": "uuid",
  "type": "auto-update",
  "vmid": 100,
  "node": "pve-01",
  "components": ["virtio", "qemu-ga"],
  "policy": "maintenance-window-auto",
  "queued_at": "2026-07-15T02:00:01Z",
  "attempts": 0,
  "max_attempts": 3,
  "next_attempt_at": "2026-07-15T02:00:01Z"
}
```

### Worker behavior

```bash
patchmox worker --once            # process one eligible job and exit
patchmox worker --max-jobs 5      # process up to 5 eligible jobs and exit
patchmox worker                   # run as daemon, sleep between polls
```

The worker:

1. Scans `queue/pending/` for jobs whose `next_attempt_at` has passed.
2. Atomically moves the oldest eligible job into `queue/claimed/<job-id>` using `mv` on the same filesystem.
3. Writes a `queue/running/<job-id>.meta` file with PID and start time.
4. Executes the update.
5. On success, moves to `queue/done/`. On failure, increments `attempts`, updates `next_attempt_at` with exponential backoff, and returns to `queue/pending/` or `queue/failed/` if retries exhausted.

### Auto-update gating

A policy with `action: auto-update` is **not** "execute immediately". It still passes through gates:

1. **Maintenance window** — is now inside the allowed window?
2. **Safety gate** — VM running? guest-agent responsive? required snapshot present?
3. **Rate gate** — does the number of currently running updates for this node/cluster exceed `max_concurrent`?
4. **Retry gate** — has this job already failed too many times?

If a gate rejects execution, the job stays in `pending/` with `next_attempt_at` set to the next maintenance window or backoff interval.

## State as an event journal

Replace the single snapshot `.state/vm-${vmid}.state` with:

- `.state/vm-${vmid}.log` — append-only event journal for this VM,
- `.state/vm-${vmid}.state` — small derived cache rebuilt from the journal.

Benefits:

- reproducibility: "why did this update happen at 3 AM?",
- retry/idempotency: "was the action already attempted?",
- audit trail: critical for auto-updates.

## Multi-host and HA (documented, deferred)

Default deployment is a **single orchestrator node**. Running on multiple active nodes requires either `flock` on a shared POSIX filesystem or a SQLite WAL-backed state store. This is explicitly out of scope for the first implementation phase; design the queue/state primitives so the storage backend can be swapped later without rewriting consumers.

## Rename checklist

The GitHub repository rename is deferred, but everything **inside** the repository must switch to PatchMox now. Update these locations during the refactoring.

### Project identity

| Old | New |
|---|---|
| `PVE-QEMU-VirtIO-Updater` | `PatchMox` |
| `PVE-VirtIO-Updater` | `PatchMox` |
| `pve-virtio-updater` (directory/package) | `patchmox` |

### CLI and runtime paths

| Old | New |
|---|---|
| `bin/pve-virtio` | `bin/patchmox` |
| `/opt/pve-qemu-virtio-updater/` | `/opt/patchmox/` |
| `/opt/pve-virtio-updater/` | `/opt/patchmox/` |
| `/var/log/pve-virtio-updater/` | `/var/log/patchmox/` |

### systemd units

| Old | New |
|---|---|
| `pve-virtio-webhook.service` | `patchmox-webhook.service` |
| *(new)* check timer | `patchmox-check.timer` |
| *(new)* check service | `patchmox-check.service` |
| *(new)* worker service | `patchmox-worker.service` |

### Environment and log identifiers

| Old | New |
|---|---|
| `JOURNAL_TAG=PVE-VirtIO-Updater` | `JOURNAL_TAG=PatchMox` |
| `WEBHOOK_SERVICE=pve-virtio-webhook.service` | `WEBHOOK_SERVICE=patchmox-webhook.service` |
| Default log file `proxmox_virtio_updater.log` | `patchmox.log` |

### File header / author lines

Update the top-of-file comment in every `.sh` and `.func` file:

```
# Module: <file> (PatchMox)
# Author: Frederik S. (fs1n) and PatchMox Contributors
```

### README, CONTRIBUTING, email templates

- `README.md` title and body: `PVE-QEMU-VirtIO-Updater` → `PatchMox`.
- `CONTRIBUTING.md`: `PVE-QEMU-VirtIO-Updater` → `PatchMox`.
- `templates/html/email-template.html`: footer GitHub links and copyright text.
- Git clone instructions: keep the old GitHub URL until the repo is actually renamed, but add a note that the project name is now PatchMox.

### Code references

- `check-vm-updates.sh`: rename to a thin wrapper `bin/patchmox check`.
- `vm-update.sh`: rename to `lib/actions/apply-update.action` or a thin wrapper `bin/patchmox apply`.
- `lib/webhook.func`: default service name and all comments referencing `pve-virtio-webhook.service`.
- Any remaining string literals in `.env.example`.

### What does NOT change

- Component/source names like `virtio.source`, `windows-update.source`, `template.source` stay descriptive of what they check.
- The word "VirtIO" in user-facing banners and email templates remains correct because it names the driver package.
- Function names should be generic where possible (`get_windows_vms`, `build_svg_update_nag`) rather than project-branded.

## Implementation roadmap

### Phase 1 — Core engine and rename

1. Define the canonical event JSON schema.
2. Introduce `lib/core/events.func` and convert `check-vm-updates.sh` to emit events instead of mutating state directly.
3. Introduce `lib/core/policy.func` and load ordered policy files from `policies/`.
4. Introduce `lib/core/queue.func` with `enqueue_job`, `claim_job`, `finish_job`, `fail_job`.
5. Split detection from action: `patchmox check` enqueues, `patchmox worker` executes.
6. Rename project strings, CLI entrypoint, systemd names, journal tag, and default paths to PatchMox.

### Phase 2 — Modules

7. Move current VirtIO/QEMU-GA logic into `sources/virtio.source`.
8. Move SVG/description mutation into `actions/show-nag.action` and `actions/remove-nag.action`.
9. Move notification logic into `channels/*.channel` with a standard `send_event` interface.
10. Create `enqueue-update.action` that writes jobs to `queue/pending/` based on policy decisions.
11. Create `apply-update.action` as a stub that logs the trigger; wire it into the worker.

### Phase 3 — CLI and packaging

12. Create `bin/patchmox` with subcommands `check`, `notify`, `worker`, `apply`, `policy`, `state`.
13. Add systemd service/timer templates for `patchmox-check` and `patchmox-worker`.
14. Deprecate `check-vm-updates.sh` and `vm-update.sh` or make them thin wrappers calling `bin/patchmox`.

### Phase 4 — New features

15. Add `windows-update.source` and `template.source`.
16. Add policy rules for Windows Updates and template refresh.
17. Add `refresh-template.action`.
18. Harden worker retry/backoff and maintenance-window enforcement.

## Design rules

- No external orchestrator dependency.
- Detection never mutates; mutation only through actions triggered by policy.
- Every mutation produces an event.
- Every event is written to the journal before any action is taken.
- Auto-update must pass all gates; a rejected gate updates `next_attempt_at`, it does not crash.
- One command surface (`bin/patchmox`) over a directory of modules.
- Flat-file state is the default; SQLite-backed state is a future pluggable backend.
- All project-branded strings inside the repo must read PatchMox; component names stay descriptive.
