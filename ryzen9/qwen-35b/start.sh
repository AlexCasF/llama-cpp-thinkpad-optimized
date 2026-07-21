#!/usr/bin/env bash
set -Eeuo pipefail

model_path="${LLAMA_MODEL_PATH:-${LLAMA_MODEL_DIR:-$HOME/llama-models}/Hermes3.6-35B-A3B-Uncensored-Genesis-V3-APEX-Compact.gguf}"
port="${LLAMA_PORT:-11434}"
vulkan_device="${LLAMA_DEVICE:-Vulkan0}"
runtime_root="${LLAMA_RUNTIME_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/llama-server-kit/runtime}"
runtime_dir="$runtime_root/b9986-vulkan"

profile_name="Ryzen 9 8945HS / Qwen 3.6 35B APEX Compact / 64K"
model_alias="qwen3.6-35b-ryzen9"
backend_name="AMD Radeon 780M / Vulkan"

ctx_size=65536
n_gpu_layers=99
n_cpu_moe=36
threads=8
threads_batch=16
batch_size=1024
ubatch_size=1024
cache_type_k="q4_0"
cache_type_v="q4_0"
flash_attention="auto"
parallel=1
cache_ram=128
cache_reuse=256
timeout=86400

log() { printf '[server] %s\n' "$*"; }
die() { trap - ERR; printf '[server] FAILED: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[server] FAILED with exit code %s\n" "$rc" >&2' ERR

[[ -f "$model_path" ]] || die "Qwen model not found at '$model_path'. Run bash ./setup.sh first."

if [[ -x "$runtime_dir/llama-server" ]]; then
    llama_server="$runtime_dir/llama-server"
else
    llama_server="$(find "$runtime_dir" -type f -name llama-server -perm -u+x -print -quit 2>/dev/null || true)"
fi
[[ -n "${llama_server:-}" && -x "$llama_server" ]] || die "Vulkan llama-server was not found. Run bash ./setup.sh first."

if command -v ss >/dev/null 2>&1 && ss -ltnH "sport = :$port" 2>/dev/null | grep -q .; then
    die "TCP port $port is already in use. Stop the existing server or set LLAMA_PORT."
fi

server_args=(
    --model "$model_path"
    --alias "$model_alias"
    --host 0.0.0.0
    --port "$port"
    --device "$vulkan_device"
    --ctx-size "$ctx_size"
    --n-gpu-layers "$n_gpu_layers"
    --n-cpu-moe "$n_cpu_moe"
    --threads "$threads"
    --threads-batch "$threads_batch"
    --batch-size "$batch_size"
    --ubatch-size "$ubatch_size"
    --cache-type-k "$cache_type_k"
    --cache-type-v "$cache_type_v"
    --flash-attn "$flash_attention"
    --parallel "$parallel"
    --cache-ram "$cache_ram"
    --cache-reuse "$cache_reuse"
    --timeout "$timeout"
    --cache-prompt
    --cont-batching
    --jinja
    --no-webui
    --metrics
    --mmap
)

log "Profile: $profile_name"
log "Runtime: $llama_server"
log "Model: $model_path"
log "Backend: $backend_name ($vulkan_device)"
log "Context: $ctx_size"
log "GPU layers: $n_gpu_layers / CPU MoE layers: $n_cpu_moe"
log "Threads: $threads decode / $threads_batch batch"
log "Batch: $batch_size / ubatch $ubatch_size"
log "KV cache: $cache_type_k / $cache_type_v"
log "Flash attention: $flash_attention"
log "mmap: enabled"
log "Keep this terminal open. Press Ctrl+C to stop the server."

exec "$llama_server" "${server_args[@]}"
