#!/bin/bash
set -euo pipefail

# It supports three installation modes:
#
# MODE 1: Prebuilt Wheel Only (VLLM_PREBUILT=1)
#   - Downloads and installs wheel from wheels.vllm.ai/$commit/vllm
#   - Fails if wheel doesn't exist for specified commit
#
# MODE 2: Editable Install with Precompiled Binaries (VLLM_USE_PRECOMPILED=1)
#   - Falls back to Mode 3 if precompiled wheel doesn't exist
#   - Otherwise, clones vLLM source repo but uses precompiled C++/CUDA binaries from wheel
#
# MODE 3: Full Build from Source (VLLM_PREBUILT=0, VLLM_USE_PRECOMPILED=0)
#   - Do not care about wheel, just compiles all C++/CUDA code from vLLM source code from scratch
#
# ============================================================================
# Required Environment Variables
# ============================================================================
#
# VLLM_REPO                       - vLLM git repository URL
# VLLM_COMMIT_SHA                 - vLLM commit SHA to checkout for source code
# VLLM_PREBUILT                   - Use Mode 1 if "1", otherwise Mode 2/3 (default: 0)
# VLLM_USE_PRECOMPILED            - Use Mode 2 if "1", Mode 3 if "0" (default: 1)
# VLLM_PRECOMPILED_WHEEL_COMMIT   - Commit SHA for precompiled binary lookup
#                                   (defaults to VLLM_COMMIT_SHA if not set)
#                                   Allows using binaries from one commit with source from another
# CUDA_MAJOR                      - CUDA major version (e.g., 12)
# CUDA_MINOR                      - CUDA minor version (e.g., 9)
# FLASHINFER_VERSION              - FlashInfer version for flashinfer-cubin and flashinfer-jit-cache (e.g., v0.5.2)
# BUILD_NIXL_FROM_SOURCE          - Whether NIXL was built from source ("true"/"false")
# SUPPRESS_PYTHON_OUTPUT          - Suppress verbose pip output ("true"/"1", optional)
# NVSHMEM_DIR                      - Path to compiled NVSHMEM installation (optional; triggers uninstall of vLLM's NVSHMEM wheel)
#
# ============================================================================

: "${SUPPRESS_PYTHON_OUTPUT:=}"

. /opt/vllm/bin/activate

VLLM_PRECOMPILED_WHEEL_COMMIT="${VLLM_PRECOMPILED_WHEEL_COMMIT:-${VLLM_COMMIT_SHA}}"
VLLM_PRECOMPILED_WHEEL_VARIANT="${VLLM_PRECOMPILED_WHEEL_VARIANT:-cu${CUDA_MAJOR}${CUDA_MINOR}}"

FLASHINFER_WHEEL_VERSION="${FLASHINFER_VERSION#v}"  # Strip 'v' prefix
INSTALL_PACKAGES=(
  cuda-python
  'huggingface_hub[hf_xet]'
  flashinfer-cubin=="${FLASHINFER_WHEEL_VERSION}"
  flashinfer-jit-cache=="${FLASHINFER_WHEEL_VERSION}"
  /tmp/wheels/*.whl  # Custom built wheels from dockerfile step(DeepEP, DeepGEMM, pplx-kernels, LMCache)
)

# Add NIXL if it wasn't built from source in the dockerfile builder stage (build-nixl.sh)
if [ "${BUILD_NIXL_FROM_SOURCE}" = "false" ]; then
  INSTALL_PACKAGES+=(nixl)
fi

# resolve VLLM_PRECOMPILED_WHEEL_COMMIT and detect precompiled wheel
# MODE 1 (Prebuilt) and MODE 2 (Precompiled)
WHEEL_URL=""
if [ "${VLLM_PREBUILT}" = "1" ] || [ "${VLLM_USE_PRECOMPILED}" = "1" ]; then
  # git ls-remote resolves named refs (tags/branches) to full SHAs
  # if it's already a full SHA, ls-remote won't match and we keep it as-is
  # note: short SHAs are not supported — always pass full 40-char SHAs or ref names
  # this is different than clone and rev-parse
  RESOLVED_SHA=$(git ls-remote "${VLLM_REPO}" "${VLLM_PRECOMPILED_WHEEL_COMMIT}" | cut -f1)
  if [ -n "${RESOLVED_SHA}" ]; then
    VLLM_PRECOMPILED_WHEEL_COMMIT="${RESOLVED_SHA}"
    echo "DEBUG: Resolved wheel commit SHA: ${VLLM_PRECOMPILED_WHEEL_COMMIT}"
  fi

  echo "DEBUG: Looking for precompiled wheel at: https://wheels.vllm.ai/${VLLM_PRECOMPILED_WHEEL_COMMIT}/${VLLM_PRECOMPILED_WHEEL_VARIANT}/vllm/"
  WHEEL_INDEX_HTML=$(curl -sf "https://wheels.vllm.ai/${VLLM_PRECOMPILED_WHEEL_COMMIT}/${VLLM_PRECOMPILED_WHEEL_VARIANT}/vllm/" || echo "")

  if [ -z "${WHEEL_INDEX_HTML}" ]; then
    echo "DEBUG: Failed to fetch wheel index or index does not exist"
  else
    echo "DEBUG: Architecture: $(uname -m), Python: $(python3 --version)"
    MACHINE=$(uname -m)
    case "${MACHINE}" in
      x86_64|amd64) PLATFORM_TAG="manylinux_2_35_x86_64" ;;
      aarch64|arm64) PLATFORM_TAG="manylinux_2_35_aarch64" ;;
      *) echo "ERROR: Unsupported architecture: ${MACHINE}"; exit 1 ;;
    esac

    # If no wheel found, set to empty string and fall to WHEEL_URL=""
    WHEEL_FILENAME=$(echo "${WHEEL_INDEX_HTML}" | { grep -oE "vllm-[^\"]+${PLATFORM_TAG}\.whl" || true; } | head -1)

    if [ -n "${WHEEL_FILENAME}" ]; then
      # note: vllm wheel index structure isn't pip-compatible, so we scrape the HTML directly
      # construct full URL (wheels are in parent directory)
      # URL-encode the + sign in the wheel filename
      WHEEL_URL="https://wheels.vllm.ai/${VLLM_PRECOMPILED_WHEEL_COMMIT}/${WHEEL_FILENAME}"
      echo "DEBUG: Found wheel: ${WHEEL_FILENAME}"
      WHEEL_URL=$(echo "${WHEEL_URL}" | sed -E 's/\+/%2B/g')
      echo "DEBUG: Wheel URL: ${WHEEL_URL}"
    else
      echo "DEBUG: No wheel found for platform: ${PLATFORM_TAG}"
    fi
  fi
fi

if [ "${VLLM_PREBUILT}" = "1" ]; then
  # MODE 1: Prebuilt Wheel
  if [ -z "${WHEEL_URL}" ]; then
    echo "ERROR: VLLM_PREBUILT set to 1 but no platform compatible wheel exists for: https://wheels.vllm.ai/${VLLM_PRECOMPILED_WHEEL_COMMIT}/${VLLM_PRECOMPILED_WHEEL_VARIANT}/vllm/"
    exit 1
  fi

  INSTALL_PACKAGES+=("${WHEEL_URL}")

else
  # MODE 2 or MODE 3: Clone vLLM source
  echo "Cloning vLLM repository from: ${VLLM_REPO}, checking out commit: ${VLLM_COMMIT_SHA}"

  git clone "${VLLM_REPO}" /opt/vllm-source
  git -C /opt/vllm-source config --system --add safe.directory /opt/vllm-source
  git -C /opt/vllm-source fetch --depth=1 origin "${VLLM_COMMIT_SHA}" || true
  git -C /opt/vllm-source checkout -q "${VLLM_COMMIT_SHA}"

  # Apply cherry-pick commits if specified (for python-only patches on top of main)
  apply_cherrypick() {
    local commit="$1"
    local remote="$2"
    if [ -z "${commit}" ]; then
      return
    fi
    echo "DEBUG: Cherry-picking commit ${commit} from ${remote}"
    if [ "${remote}" != "origin" ] && [ -n "${remote}" ]; then
      git -C /opt/vllm-source remote add cherrypick_remote "${remote}" 2>/dev/null || true
      git -C /opt/vllm-source fetch --depth=50 cherrypick_remote
      git -C /opt/vllm-source cherry-pick --no-commit "${commit}"
      git -C /opt/vllm-source remote remove cherrypick_remote
    else
      git -C /opt/vllm-source fetch --depth=50 origin
      git -C /opt/vllm-source cherry-pick --no-commit "${commit}"
    fi
    echo "DEBUG: Successfully applied ${commit}"
  }

  apply_cherrypick "${VLLM_CHERRYPICK_1:-}" "${VLLM_CHERRYPICK_1_REMOTE:-origin}"
  apply_cherrypick "${VLLM_CHERRYPICK_2:-}" "${VLLM_CHERRYPICK_2_REMOTE:-origin}"

  # MODE 2
  if [ "${VLLM_USE_PRECOMPILED}" = "1" ] && [ -n "${WHEEL_URL}" ]; then
    echo "Using precompiled binaries from commit: ${VLLM_PRECOMPILED_WHEEL_COMMIT} (with source code from: ${VLLM_COMMIT_SHA})."
    export VLLM_USE_PRECOMPILED=1      # Do not really need to set it here as it is done in vllm envs.py by VLLM_PRECOMPILED_WHEEL_LOCATION
    export VLLM_PRECOMPILED_WHEEL_LOCATION="${WHEEL_URL}"
    INSTALL_PACKAGES+=(-e /opt/vllm-source)

    bash /opt/warn-vllm-precompiled.sh

  else # MODE 3
    echo "Compiling fully from source. Either precompile disabled or wheel not found in index"
    unset VLLM_USE_PRECOMPILED VLLM_PRECOMPILED_WHEEL_LOCATION || true
    INSTALL_PACKAGES+=(-e /opt/vllm-source)
  fi
fi

# Install all packages in one command with verbose output to prevent GitHub Action timeouts
# Use flashinfer wheel index for jit-cache pre-built binaries
echo "DEBUG: Installing packages: ${INSTALL_PACKAGES[*]}"
CUDA_SHORT_VERSION="cu${CUDA_MAJOR}${CUDA_MINOR}"
VERBOSE_FLAG="-v"
if [ "${SUPPRESS_PYTHON_OUTPUT}" = "true" ] || [ "${SUPPRESS_PYTHON_OUTPUT}" = "1" ]; then
  VERBOSE_FLAG=""
fi
# shellcheck disable=SC2086
uv pip install ${VERBOSE_FLAG} "${INSTALL_PACKAGES[@]}" \
  --extra-index-url "https://flashinfer.ai/whl/${CUDA_SHORT_VERSION}"

# Uninstall the NVSHMEM dependency brought in by vLLM if using a compiled NVSHMEM
# We built our own NVSHMEM in the dockerfile builder stage, so we don't need the one from vLLM as dependency
if [[ "${NVSHMEM_DIR-}" != "" ]]; then
  uv pip uninstall "nvidia-nvshmem-cu${CUDA_MAJOR}"
fi

# Clean up
rm -rf /tmp/wheels
rm -rf /opt/vllm-source/.deps
rm -rf /opt/vllm-source/.git
rm -rf /opt/vllm-source/docs
rm -rf /opt/vllm-source/tests
rm -f /opt/warn-vllm-precompiled.sh
