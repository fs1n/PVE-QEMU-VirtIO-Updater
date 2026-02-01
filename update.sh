#!/usr/bin/env bash
#
# Module: update.sh (PVE-QEMU-VirtIO-Updater)
# Description: Self-update mechanism for fetching and applying latest version from GitHub repository
# Author: Frederik S. (fs1n) and PVE-QEMU-VirtIO-Updater Contributors
# Date: 2025-01-31
#
# Dependencies: git, curl
# Environment: SCRIPT_DIR, GITHUB_REPO_URL
# Usage: ./update.sh
#
# Description:
#   This script provides a self-update mechanism for the PVE-QEMU-VirtIO-Updater.
#   It fetches the latest version from the GitHub repository, validates changes,
#   and updates local files while preserving user configurations (.env).

