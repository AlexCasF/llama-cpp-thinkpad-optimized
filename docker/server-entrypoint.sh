#!/usr/bin/env bash
set -Eeuo pipefail

SERVER_BIN="${LLAMA_SERVER_BIN:-/app/llama-server}"
MODEL_PATH="${MODEL_PATH:-}"

if [[ ! -x "$SERVER_BIN" ]]; then
  echo "ERROR: llama-server was not found at: $SERVER_BIN" >&2
  exit 2
fi
if [[ -z "$MODEL_PATH" || ! -f "$MODEL_PATH" ]]; then
  echo "ERROR: MODEL_PATH is unset or not a readable file: ${MODEL_PATH:-<unset>}" >&2
  exit 2
fi

# Intel GPU access from a Windows 11 WSL2/Docker Desktop container.
if [[ -d /usr/lib/wsl/lib ]]; then
  export LD_LIBRARY_PATH="/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}"
fi

# The Vulkan fallback uses Mesa's D3D12 (dzn) driver over /dev/dxg.
if [[ "${LLAMA_BACKEND:-}" == "vulkan-wsl" ]]; then
  export MESA_D3D12_DEFAULT_ADAPTER_NAME="${MESA_D3D12_DEFAULT_ADAPTER_NAME:-Intel}"
  if [[ -z "${VK_DRIVER_FILES:-}" && -z "${VK_ICD_FILENAMES:-}" ]]; then
    for icd in \
      /usr/share/vulkan/icd.d/dzn_icd.x86_64.json \
      /usr/share/vulkan/icd.d/dzn_icd.json; do
      if [[ -f "$icd" ]]; then
        export VK_DRIVER_FILES="$icd"
        break
      fi
    done
  fi
fi

args=(
  --model "$MODEL_PATH"
  --alias "${MODEL_ALIAS:-huihui_ai/Qwen3.6-abliterated:35b}"
  --host "${LLAMA_HOST:-0.0.0.0}"
  --port "${LLAMA_PORT:-8080}"
  --ctx-size "${CTX_SIZE:-131072}"
  --n-gpu-layers "${N_GPU_LAYERS:-99}"
  --n-cpu-moe "${N_CPU_MOE:-28}"
  --threads "${THREADS:-6}"
  --threads-batch "${THREADS_BATCH:-7}"
  --batch-size "${BATCH_SIZE:-2048}"
  --ubatch-size "${UBATCH_SIZE:-512}"
  --cache-type-k "${CACHE_TYPE_K:-q8_0}"
  --cache-type-v "${CACHE_TYPE_V:-q8_0}"
  --flash-attn "${FLASH_ATTN:-auto}"
  --parallel "${N_PARALLEL:-1}"
  --cache-ram "${CACHE_RAM_MIB:-256}"
  --cache-reuse "${CACHE_REUSE:-256}"
  --timeout "${REQUEST_TIMEOUT_SECONDS:-86400}"
  --cache-prompt
  --cont-batching
  --jinja
  --metrics
)

# On this integrated GPU, mmap is intentionally the default. It lets the OS
# discard file-backed pages after weights are copied/offloaded. --no-mmap can
# force an additional full-model allocation in the same 32 GB shared pool.
if [[ "${LLAMA_NO_MMAP:-0}" == "1" ]]; then
  args+=(--no-mmap)
else
  args+=(--mmap)
fi

# mlock is off by default because Windows, WSL, CPU weights, and iGPU allocations
# all compete for the same physical RAM. Enable only after proving ample headroom.
if [[ "${LLAMA_MLOCK:-0}" == "1" ]]; then
  args+=(--mlock)
fi

if [[ "${NO_WEBUI:-0}" == "1" ]]; then
  args+=(--no-webui)
fi

# Optional expert-level overrides. Leave unset for layer-level --n-cpu-moe.
if [[ -n "${CPU_MOE_EXPERTS:-}" ]]; then
  args+=(--cpu-moe "${CPU_MOE_EXPERTS}")
fi

# Advanced escape hatch. Shell-style quoting is intentionally not interpreted;
# provide simple whitespace-separated flags only.
if [[ -n "${LLAMA_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra=( ${LLAMA_EXTRA_ARGS} )
  args+=("${extra[@]}")
fi

cat <<INFO
Starting llama-server
  backend:      ${LLAMA_BACKEND:-image-default}
  model:        $MODEL_PATH
  context:      ${CTX_SIZE:-131072}
  GPU layers:   ${N_GPU_LAYERS:-99}
  CPU MoE:      ${N_CPU_MOE:-28} of 40 layers
  threads:      ${THREADS:-6} decode / ${THREADS_BATCH:-7} batch
  batch:        ${BATCH_SIZE:-2048} logical / ${UBATCH_SIZE:-512} physical
  KV cache:     ${CACHE_TYPE_K:-q8_0} K / ${CACHE_TYPE_V:-q8_0} V
  mmap/mlock:   $([[ "${LLAMA_NO_MMAP:-0}" == "1" ]] && echo off || echo on) / $([[ "${LLAMA_MLOCK:-0}" == "1" ]] && echo on || echo off)
INFO

exec "$SERVER_BIN" "${args[@]}"
