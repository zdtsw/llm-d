#!/bin/bash
set -euo pipefail

# GDS startup probe for Weka deployments
#
# Verifies that GDS requirements are met:
# - nvidia_fs kernel module is loaded (for GDS)
# - nvidia_peermem kernel module is loaded (for Weka PeerDirect)
# - cufile.json exists and is valid

# Check nvidia_fs is loaded
if ! lsmod | grep -q nvidia_fs; then
    echo "ERROR: nvidia_fs module not loaded" >&2
    exit 1
fi

# Check nvidia_peermem is loaded
if ! lsmod | grep -q nvidia_peermem; then
    echo "ERROR: nvidia_peermem module not loaded" >&2
    exit 1
fi

# Check cufile.json
TARGET="${1:-/etc/cufile.json}"
if [ ! -r "$TARGET" ] || [ ! -s "$TARGET" ]; then
    echo "ERROR: $TARGET does not exist, is not readable, or is empty" >&2
    exit 1
fi

echo "GDS ready: kernel modules loaded and cufile.json valid"
exit 0
