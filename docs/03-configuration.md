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

