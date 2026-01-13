#!/bin/bash

# Script used as a readinessProbe to ensure the `cufile.json` exists and is valid

set -euo pipefail
TARGET="${1:-/etc/cufile.json}"

# Check if file is readable and not empty
if [ ! -r "$TARGET" ] || [ ! -s "$TARGET" ]; then
  echo "Error: $TARGET does not exist, is not readable, or is empty" >&2
  exit 1
fi

# TODO: Other verification on cufile.json goes here

exit 0
