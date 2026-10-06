#!/usr/bin/env bash
# ==============================================================================
# switch_model.sh - 3-Tier Dynamic Model Switcher for LocalHarness
# ==============================================================================
# Optimized for AMD Ryzen 7 / Radeon 780M (Fedora, 16GB RAM / 4GB iGPU UMA).
#
# Hardware Constraint:
#   Because unified memory is shared (16GB total), running multiple heavy local
#   LLMs simultaneously triggers memory pressure and severe swap thrashing.
#   This script enforces single-heavy lifecycle: it gracefully terminates any
#   incumbent model, waits for AMDGPU unified memory to settle and reclaim,
#   and launches the selected tier on demand.
#
# Available Tiers:
#   1. ling  | ling-tiny | fast  -> Ling-3.0-tiny (4.5GB, ~35 t/s, 16k ctx)
#   2. gemma | gemma-4   | daily -> Gemma-4-E4B-it-qat (4.0GB, ~13 t/s, 16k ctx)
#   3. qwen  | qwen-9b   | heavy -> Qwen3.5-9B (5.3GB, ~7 t/s, 8k ctx)
#
# Commands:
#   ./scripts/switch_model.sh [ling|gemma|qwen]
#   ./scripts/switch_model.sh status
#   ./scripts/switch_model.sh stop
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
LLAMA_BIN="${LLAMA_BIN:-$LLAMA_DIR/build/bin/llama-server}"
MODELS_DIR="${MODELS_DIR:-$LLAMA_DIR/models}"

HOST="127.0.0.1"
PORT="8080"
GPU_FREE_SETTLE_SECONDS=3

PID_FILE="$HOME/.localharness/llama-server.pid"
VLLM_PID_DIR="$HOME/.localharness/vllm"
VLLM_PID_FILE="$VLLM_PID_DIR/server.pid"
LOG_FILE="$HOME/.localharness/llama-server.log"

mkdir -p "$HOME/.localharness" "$VLLM_PID_DIR"

show_usage() {
    cat <<EOF
Usage: $(basename "$0") <command|tier>

Tiers:
  ling  | ling-tiny | fast   Switch to Ling-3.0-tiny (~35 t/s, 16k ctx)
                             Best for rapid tool loops, triage, web & doc lookups
  gemma | gemma-4   | daily  Switch to Gemma-4-E4B-it-qat (~13 t/s, 16k ctx)
                             General daily driver, balanced agent workflows
  qwen  | qwen-9b   | heavy  Switch to Qwen3.5-9B (~7 t/s, 8k ctx)
                             Heavy reasoning, complex coding, hard algorithmic tasks

Management:
  status                     Show current active model, port 8080 status, and RAM/VRAM
  stop                       Gracefully terminate running llama-server and free GPU memory
  help                       Show this help message
EOF
}

is_server_listening() {
    curl -s --connect-timeout 1 "http://${HOST}:${PORT}/health" >/dev/null 2>&1
}

get_active_model_id() {
    if is_server_listening; then
        curl -s --connect-timeout 2 "http://${HOST}:${PORT}/v1/models" 2>/dev/null | \
            python3 -c "import sys, json; data=json.load(sys.stdin); print(data['data'][0]['id'] if 'data' in data and data['data'] else 'unknown')" 2>/dev/null || echo "unknown"
    else
        echo "none"
    fi
}

get_active_pid() {
    pgrep -x "llama-server" 2>/dev/null | head -n 1 || echo ""
}

show_status() {
    echo "======================================================================"
    echo " LocalHarness Dynamic Model Stack Status"
    echo "======================================================================"
    local active_model
    active_model="$(get_active_model_id)"
    local active_pid
    active_pid="$(get_active_pid)"

    if [ "$active_model" != "none" ] && [ -n "$active_pid" ]; then
        echo " Status:         ACTIVE (Serving on http://${HOST}:${PORT}/v1)"
        echo " Active Model:   ${active_model}"
        echo " Process PID:    ${active_pid}"
        if [[ "$active_model" =~ [Ll]ing ]]; then
            echo " Active Tier:    Tier 1 (Fast Executor · ~35 t/s)"
        elif [[ "$active_model" =~ [Gg]emma ]]; then
            echo " Active Tier:    Tier 2 (Daily Driver · ~13 t/s)"
        elif [[ "$active_model" =~ [Qq]wen ]]; then
            echo " Active Tier:    Tier 3 (Heavy Reasoner · ~7 t/s)"
        else
            echo " Active Tier:    Custom / Other"
        fi
    elif [ -n "$active_pid" ]; then
        echo " Status:         STARTING or UNRESPONSIVE (PID ${active_pid} running)"
    else
        echo " Status:         STOPPED (No model server running on port ${PORT})"
    fi

    echo "----------------------------------------------------------------------"
    echo " System Memory & UMA Status:"
    free -h | awk 'NR<=2 {print "   " $0}'
    echo "======================================================================"
}

stop_server() {
    if ! pgrep -x "llama-server" >/dev/null 2>&1; then
        echo "[INFO] No running llama-server process detected."
        rm -f "$PID_FILE" "$VLLM_PID_FILE"
        return 0
    fi

    echo "[STOP] Gracefully stopping llama-server..."
    pkill -TERM -x "llama-server" 2>/dev/null || true

    local timeout=10
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if ! pgrep -x "llama-server" >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    if pgrep -x "llama-server" >/dev/null 2>&1; then
        echo "[STOP] Server still alive after 5s grace period; sending SIGKILL..."
        pkill -KILL -x "llama-server" 2>/dev/null || true
        sleep 1
    fi

    rm -f "$PID_FILE" "$VLLM_PID_FILE"
    echo "[STOP] llama-server stopped."

    echo "[SETTLE] Waiting ${GPU_FREE_SETTLE_SECONDS}s for AMDGPU unified memory reclamation..."
    sleep "${GPU_FREE_SETTLE_SECONDS}"
    echo "[SETTLE] GPU accelerator free."
}

update_config_default_model() {
    local model_id="$1"
    python3 - <<EOF
from pathlib import Path

def update_file(path_str: str, model: str):
    p = Path(path_str)
    if not p.exists():
        return
    lines = p.read_text().splitlines()
    new_lines = []
    in_section = False
    for line in lines:
        stripped = line.strip()
        if stripped in ('provider:', 'org:'):
            in_section = True
        elif line and not line.startswith(' ') and not line.startswith('#'):
            in_section = False
        
        if in_section and stripped.startswith('default_model:'):
            indent = len(line) - len(line.lstrip())
            new_lines.append(f"{' ' * indent}default_model: {model}")
        else:
            new_lines.append(line)
    p.write_text('\n'.join(new_lines) + '\n')

update_file("${HOME}/.localharness/config.yaml", "${model_id}")
update_file("${REPO_DIR}/config/config.yaml", "${model_id}")
EOF
}

launch_model() {
    local target_tier="$1"
    local model_file=""
    local model_id=""
    local ctx_size=""
    local tier_label=""
    local tier_rate=""
    local tier_desc=""
    local recommended_agents=""

    case "$target_tier" in
        ling|ling-tiny|fast|tier1)
            model_file="${MODELS_DIR}/Ling-3.0-tiny-Q4_K_M.gguf"
            model_id="Ling-3.0-tiny-Q4_K_M.gguf"
            ctx_size="16384"
            tier_label="Tier 1: Fast Executor"
            tier_rate="~35 t/s"
            tier_desc="Rapid tool loops, triage, web lookup & doc inspection"
            recommended_agents="web-researcher, news-scout, document-analyst"
            ;;
        gemma|gemma-4|daily|tier2|default)
            model_file="${MODELS_DIR}/gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf"
            model_id="gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf"
            ctx_size="16384"
            tier_label="Tier 2: General Purpose Daily Driver"
            tier_rate="~13 t/s"
            tier_desc="Standard agent workflows, balanced execution, instruction following"
            recommended_agents="orchestrator, dsa-mentor, study-tutor, career-agent, project-manager, system-agent"
            ;;
        qwen|qwen-9b|heavy|coder|tier3)
            model_file="${MODELS_DIR}/Qwen3.5-9B-Q4_K_M.gguf"
            model_id="Qwen3.5-9B-Q4_K_M.gguf"
            ctx_size="8192"
            tier_label="Tier 3: Heavy Reasoner / Code Specialist"
            tier_rate="~7 t/s"
            tier_desc="Deep reasoning, complex coding, algorithm design, heavy planning"
            recommended_agents="coding-engineer, data-engineer"
            ;;
        *)
            echo "Error: Unknown tier '$target_tier'" >&2
            show_usage
            exit 1
            ;;
    esac

    if [ ! -f "$model_file" ]; then
        echo "Error: Model file not found at ${model_file}" >&2
        exit 1
    fi

    if [ ! -x "$LLAMA_BIN" ]; then
        echo "Error: llama-server binary not found or not executable at ${LLAMA_BIN}" >&2
        exit 1
    fi

    # Check if this exact model is ALREADY running and healthy
    local current_model
    current_model="$(get_active_model_id)"
    if [ "$current_model" = "$model_id" ]; then
        echo "[INFO] Model '${model_id}' is ALREADY active and healthy on port ${PORT}."
        echo "  Tier:         ${tier_label} (${tier_rate})"
        echo "  Capabilities: ${tier_desc}"
        echo "  Recommended:  ${recommended_agents}"
        update_config_default_model "$model_id"
        return 0
    fi

    # Stop incumbent model to enforce single-heavy box rule
    stop_server

    echo "======================================================================"
    echo " Activating ${tier_label}"
    echo "======================================================================"
    echo " Model:        ${model_file}"
    echo " Context:      ${ctx_size} tokens (Q8 KV Cache, Flash Attention)"
    echo " Speed:        ${tier_rate}"
    echo " Target:       http://${HOST}:${PORT}/v1"
    echo " Specialists:  ${recommended_agents}"
    echo "----------------------------------------------------------------------"

    echo "[START] Spawning llama-server..."
    setsid "$LLAMA_BIN" \
        -m "$model_file" \
        -a "$model_id" \
        -c "$ctx_size" \
        --jinja \
        -np 1 \
        -ngl 99 \
        -t 8 \
        -tb 8 \
        --cache-type-k q8_0 \
        --cache-type-v q8_0 \
        --flash-attn on \
        --host "$HOST" \
        --port "$PORT" \
        >> "$LOG_FILE" 2>&1 &

    local new_pid=$!
    disown "$new_pid" 2>/dev/null || true
    echo "$new_pid" > "$PID_FILE"
    echo "$new_pid" > "$VLLM_PID_FILE"

    echo -n "[WAIT] Waiting for model to initialize and pass health check"
    local max_wait=60
    local waited=0
    local ready=false

    while [ "$waited" -lt "$max_wait" ]; do
        if curl -s "http://${HOST}:${PORT}/health" 2>/dev/null | grep -q '"status":"ok"'; then
            ready=true
            break
        fi
        if ! kill -0 "$new_pid" 2>/dev/null; then
            echo ""
            echo "[ERROR] llama-server crashed during startup!" >&2
            echo "--- Recent Log Tail (${LOG_FILE}) ---" >&2
            tail -n 25 "$LOG_FILE" >&2
            rm -f "$PID_FILE" "$VLLM_PID_FILE"
            exit 1
        fi
        sleep 0.5
        echo -n "."
        waited=$((waited + 1))
    done
    echo ""

    if [ "$ready" = true ]; then
        echo "[READY] ${model_id} successfully loaded and serving on http://${HOST}:${PORT}/v1"
        update_config_default_model "$model_id"
        echo "[CONFIG] Synced default_model in ~/.localharness/config.yaml and config/config.yaml"
        echo "======================================================================"
    else
        echo "[ERROR] Timeout waiting for model server to become ready after ${max_wait}s." >&2
        exit 1
    fi
}

# --- Main Dispatcher ---
if [ $# -eq 0 ]; then
    show_usage
    exit 0
fi

CMD="${1:-}"

case "$CMD" in
    status)
        show_status
        ;;
    stop)
        stop_server
        ;;
    help|-h|--help)
        show_usage
        ;;
    ling|ling-tiny|fast|tier1|gemma|gemma-4|daily|tier2|default|qwen|qwen-9b|heavy|coder|tier3)
        launch_model "$CMD"
        ;;
    *)
        echo "Error: Unrecognized option '$CMD'" >&2
        show_usage
        exit 1
        ;;
esac
