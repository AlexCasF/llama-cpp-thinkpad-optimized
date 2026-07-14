#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

backend="${1:-sycl}"
[[ -f .env ]] || { echo "Missing .env. Run: cp .env.example .env" >&2; exit 2; }
# shellcheck disable=SC1091
set -a; source ./.env; set +a

case "$backend" in
  sycl)
    dockerfile=Dockerfile.sycl
    image=local/llama-qwen36:intel-sycl
    backend_env=sycl-wsl
    ;;
  vulkan)
    dockerfile=Dockerfile.vulkan-wsl
    image=local/llama-qwen36:vulkan-wsl
    backend_env=vulkan-wsl
    ;;
  *) echo "Usage: $0 [sycl|vulkan]" >&2; exit 2 ;;
esac

mkdir -p results
docker build -f "$dockerfile" -t "$image" .

docker_args=(
  --rm
  --device /dev/dxg
  --mount type=bind,src=/usr/lib/wsl,dst=/usr/lib/wsl,readonly
  --mount "type=bind,src=${MODEL_DIR},dst=/models,readonly"
  --mount "type=bind,src=$(pwd)/results,dst=/results"
  -e "MODEL_PATH=/models/${MODEL_FILE}"
  -e "LLAMA_BACKEND=${backend_env}"
  -e N_GPU_LAYERS=99
  -e CACHE_TYPE_K=q8_0
  -e CACHE_TYPE_V=q8_0
  -e TUNE_N_CPU_MOE="${TUNE_N_CPU_MOE:-28}"
  -e TUNE_THREADS="${TUNE_THREADS:-6}"
  --entrypoint /usr/local/bin/tune-qwen36
)

if [[ "$backend" == sycl ]]; then
  docker_args+=( -e "ONEAPI_DEVICE_SELECTOR=${ONEAPI_DEVICE_SELECTOR:-level_zero:gpu}" )
else
  docker_args+=( -e MESA_D3D12_DEFAULT_ADAPTER_NAME=Intel )
fi

docker run "${docker_args[@]}" "$image"
