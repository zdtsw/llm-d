#!/bin/bash
set -euo pipefail

# Enable NVIDIA GPU Direct Storage kernel modules for Weka

# Load nvidia_fs (GDS kernel module)
if ! modinfo nvidia_fs &>/dev/null; then
    echo "ERROR: nvidia_fs module not found" >&2
    exit 1
fi

if ! lsmod | grep -q nvidia_fs; then
    echo "Loading nvidia_fs..."
    modprobe nvidia_fs || { echo "ERROR: Failed to load nvidia_fs" >&2; exit 1; }
fi

# Load nvidia_peermem (PeerDirect for RDMA)
if ! modinfo nvidia_peermem &>/dev/null; then
    echo "ERROR: nvidia_peermem module not found" >&2
    exit 1
fi

if ! lsmod | grep -q nvidia_peermem; then
    echo "Loading nvidia_peermem..."
    modprobe nvidia_peermem || { echo "ERROR: Failed to load nvidia_peermem" >&2; exit 1; }
fi

exit 0
