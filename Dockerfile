FROM debian:bookworm-slim

# Install runtime dependencies.
# curl + jq: used by check-vm-updates.sh and pve-api.func
# cron: schedules check-vm-updates.sh runs
# All other tools (grep, sed, gawk, sort, coreutils) are standard Debian slim packages.
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    jq \
    grep \
    sed \
    gawk \
    coreutils \
    cron \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy application source
COPY . /app/

# Copy the container-only API shim into lib/ so check-vm-updates.sh's
# "for lib_file in $LIB_DIR/*.func" glob picks it up automatically.
# On bare-metal installs this file never exists in lib/; no guards needed.
COPY docker/lib/pve-api.func /app/lib/pve-api.func

# Create runtime directories (these are also mounted as volumes in compose,
# but must exist for builds without mounts).
RUN mkdir -p /app/images /app/logs /app/.state

# Make all scripts executable
RUN chmod +x \
    /app/check-vm-updates.sh \
    /app/vm-update.sh \
    /app/entrypoint.sh \
    && chmod +x /app/lib/*.func 2>/dev/null || true

# SVG image server port (Caddy reverse-proxies to this)
EXPOSE 8080

ENTRYPOINT ["/app/entrypoint.sh"]
