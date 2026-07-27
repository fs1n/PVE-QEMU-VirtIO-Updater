# Architecture

PatchMox is a host-side Bash orchestrator for Proxmox VE. It discovers Windows VMs, checks installed VirtIO driver and QEMU Guest Agent versions against the Fedora People Archive, and renders SVG update banners inside the Proxmox UI.

## High-level flow

```
Trigger (cron / manual / webhook)
    │
    ▼
Source: virtio.source — discover VMs, query guest-agent, fetch latest versions
    │
    ▼
Event Bus: dispatch_event("update.available", payload)
    │
    ├──▶ Policy Evaluator: evaluate_policy(event) → decision JSON
    │
    ├──▶ Channels: notification_send (if decision.notify == true)
    │
    └──▶ Actions: enqueue_job (if decision.action == "auto-update")
              │
              ▼
         Queue: queue/pending/ → patchmox worker → queue/done/
```

- **Detection never mutates.** `patchmox check` only inspects and dispatches events.
- **Decision is data-driven.** Policies decide whether to notify, enqueue an update, or both. First match wins; `99-default.policy` is the catch-all fallback.
- **Action is isolated.** `show-nag.action`, `remove-nag.action`, `enqueue-update.action`, and `apply-update.action` are separate modules.
- **Events are the bus.** `dispatch_event` in `events.func` is the single entry point that routes to policy, channels, and actions.

## Modules

### Core (`lib/core/`)

| File | Responsibility |
|------|--------------|
| `logger.func` | File, console, and journal logging |
| `events.func` | `build_event`, `emit_event`, `dispatch_event` — event pipeline entry point, payload builders |
| `policy.func` | Load and evaluate policy files (`load_policies`, `evaluate_policy`, `_policy_matches_event`) |
| `state.func` | Per-VM persistent state, guest-agent cache |
| `queue.func` | Filesystem job queue primitives |
| `progress.func` | Interactive spinner and progress output |
| `utils.func` | Dependency checks with caching |
| `webhook.func` | Maintain `webhook/hooks.json` for inbound clicks |

### Sources (`lib/sources/`)

| File | Responsibility |
|------|--------------|
| `virtio.source` | VM discovery (Windows only), version fetch with cache, guest-agent queries |

### Actions (`lib/actions/`)

| File | Responsibility |
|------|--------------|
| `show-nag.action` | Render SVG and update VM description |
| `remove-nag.action` | Remove SVG banner from VM description |
| `enqueue-update.action` | Write auto-update jobs to the queue (called by `dispatch_event`) |
| `apply-update.action` | Execute an update inside a VM (Phase 2 stub) |

### Channels (`lib/channels/`)

| File | Responsibility |
|------|--------------|
| `_dispatcher.channel` | `notification_send` — routes to enabled channels via `NOTIFICATION_CHANNELS` |
| `smtp.channel` | SMTP notifications via curl |
| `msgraph.channel` | MS Graph notifications (stub) |
| `webhook.channel` | Outgoing webhook notifications (stub) |

## Event pipeline

`dispatch_event` is the core of the system. When `patchmox check` finds an update:

1. `build_event` creates a canonical JSON event with `event_id`, `timestamp`, `type`, and `payload`.
2. `evaluate_policy` tests the event against each loaded `.policy` file in alphabetical order. First match wins. If no policy matches, the default decision is `{"notify":true,"action":"none"}`.
3. If `decision.notify == true`, `notification_send` dispatches to all configured channels (`NOTIFICATION_CHANNELS`).
4. If `decision.action == "auto-update"`, `enqueue_job` writes a job to `queue/pending/`.

Informational events (`check.started`, `vm.checked`, `nag.shown`, `nag.removed`, `check.completed`) use `emit_event` (log only, no policy dispatch).

## Policy matching

Policy files in `policies/` are JSON. The `match` object supports:

| Key | Match logic |
|-----|------------|
| `type` | Event type (e.g. `"update.available"`) |
| `vmid` | VM ID (string) |
| `node` | Proxmox node name |
| `components` | All specified components must be present in the event's components list (subset match) |

Empty `match` = matches everything. The `99-default.policy` file has an empty match and serves as the catch-all.

## State

PatchMox keeps durable state in two places:

- `.state/vm-${vmid}.state` — vmgenid, last seen versions, nag status, last checked timestamp.
- `queue/{pending,claimed,running,done,failed}/${job_id}.json` — durable audit trail of actions.

Events are emitted to stdout for logging. They are not persisted to a separate journal; queue files are the source of truth for "what happened and when".

## Queue and worker

`patchmox check` detects and enqueues; `patchmox worker` executes separately. The worker:

1. Scans `queue/pending/` for jobs whose `next_attempt_at` has passed.
2. Atomically moves eligible jobs to `queue/claimed/`.
3. Writes a `queue/running/${job_id}.meta` file.
4. Calls `apply-update.action`.
5. Moves the job to `queue/done/` or back to `queue/pending/` with exponential backoff (5m, 15m, 45m, ...).

## Performance notes

- Version fetch is cached (default 60 minutes, configurable via `VERSION_CACHE_TTL_MINUTES`).
- VM discovery uses a single `/cluster/resources` call; per-VM config fetches are limited to running VMs only.
- Guest-agent queries are cached per-VM based on vmgenid + status + TTL (`GUEST_AGENT_CACHE_TTL_MINUTES`).
- Optional node-level concurrency (`--max-node-concurrency`) is deferred to Phase 4.
