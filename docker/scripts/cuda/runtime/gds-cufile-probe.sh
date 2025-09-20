#!/bin/bash

# Script used as a readinessProbe to ensure the `cufile.json` exists

set -euo pipefail
TARGET="${1:-/etc/cufile.json}"
if [ -e "$TARGET" ]; then
  # Other verification on cufile.json goes here
  exit 0
else
  echo "Missing: $TARGET" >&2
  exit 1
fi
