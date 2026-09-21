#!/usr/bin/env bash
# ==============================================================================
# run_gemma.sh - Launch llama-server with Gemma 4 E4B QAT
# ==============================================================================
# Optimized for 16GB laptops with AMD Radeon 780M / integrated GPUs
# (4GB UMA allocated to iGPU).
# Context window: 16,384 tokens with Flash Attention & Q8 KV cache.
# ==============================================================================

set -euo pipefail

LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
MODEL_PATH="${MODEL_PATH:-$HOME/llama.cpp/models/gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf}"

if [ ! -d "${LLAMA_DIR}" ]; then
    echo "Error: llama.cpp directory not found at ${LLAMA_DIR}"
    echo "Set LLAMA_DIR to your llama.cpp clone path."
    exit 1
fi

cd "${LLAMA_DIR}"

echo "Starting llama-server with Gemma 4 E4B QAT..."
echo "Model: ${MODEL_PATH}"
echo "Context: 16,384 | Host: 127.0.0.1:8080"

./build/bin/llama-server \
  -m "${MODEL_PATH}" \
  -c 16384 \
  --jinja \
  -np 1 \
  -ngl 99 \
  -t 8 \
  -tb 8 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --flash-attn on \
  --host 127.0.0.1 \
  --port 8080 "$@"
