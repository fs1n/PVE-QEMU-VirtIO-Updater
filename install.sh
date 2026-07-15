#!/usr/bin/env bash
#
# PatchMox installer
# Copies the current checkout to /opt/patchmox and links the CLI into /usr/local/bin.

set -euo pipefail

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SOURCE_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
TARGET_DIR="/opt/patchmox"
BIN_LINK="/usr/local/bin/patchmox"

echo "Installing PatchMox from $SOURCE_DIR to $TARGET_DIR ..."

# Ensure target directory exists
sudo mkdir -p "$TARGET_DIR"

# Copy tracked/top-level files and directories explicitly
for item in bin lib policies templates webhook check-vm-updates.sh vm-update.sh \
            .env.example .gitignore LICENSE README.md CLAUDE.md PLAN.md; do
    if [[ -e "$SOURCE_DIR/$item" ]]; then
        sudo cp -a "$SOURCE_DIR/$item" "$TARGET_DIR/$item"
    fi
done

# Create config from example if missing
if [[ ! -f "$TARGET_DIR/.env" && -f "$TARGET_DIR/.env.example" ]]; then
    echo "Creating default .env from .env.example ..."
    sudo cp "$TARGET_DIR/.env.example" "$TARGET_DIR/.env"
fi

# Ensure executables are executable
sudo chmod +x "$TARGET_DIR/bin/patchmox"
sudo chmod +x "$TARGET_DIR/check-vm-updates.sh"
sudo chmod +x "$TARGET_DIR/vm-update.sh"

# Link the CLI into /usr/local/bin
sudo ln -sf "$TARGET_DIR/bin/patchmox" "$BIN_LINK"

echo "PatchMox installed. Test with: patchmox check"
