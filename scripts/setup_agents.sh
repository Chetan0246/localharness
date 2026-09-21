#!/usr/bin/env bash
# ==============================================================================
# setup_agents.sh - LocalHarness Multi-Agent Environment Setup
# ==============================================================================
# Sets up the 10-specialist suite + lean orchestrator on Linux/macOS.
# Copies agent YAML definitions to ~/.localharness/agents/ and verifies configuration.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="${HOME}/.localharness"

echo "=== LocalHarness 10-Specialist Setup ==="
echo "Target directory: ${TARGET_DIR}"

mkdir -p "${TARGET_DIR}/agents"

# 1. Install / Sync Agent YAML files
echo "--> Installing agent definitions into ${TARGET_DIR}/agents/..."
cp -v "${REPO_DIR}/agents/"*.yaml "${TARGET_DIR}/agents/"

# 2. Setup config.yaml if not present
if [ ! -f "${TARGET_DIR}/config.yaml" ]; then
    echo "--> Installing global config.yaml..."
    cp -v "${REPO_DIR}/config/config.yaml" "${TARGET_DIR}/config.yaml"
else
    echo "--> Existing ${TARGET_DIR}/config.yaml preserved."
fi

# 3. Setup overrides.yaml
echo "--> Installing global overrides.yaml (CPU resonance embedding model)..."
cp -v "${REPO_DIR}/config/overrides.yaml" "${TARGET_DIR}/overrides.yaml"

# 4. Validate configs
echo "--> Running configuration validation..."
cd "${REPO_DIR}"
uv run --no-sync localharness validate

# 5. Run doctor (health check)
echo "--> Running system health check..."
uv run --no-sync localharness doctor || true

echo ""
echo "=== Setup complete! ==="
echo "To start chatting with your agents:"
echo "  cd ${REPO_DIR}"
echo "  uv run localharness start"
