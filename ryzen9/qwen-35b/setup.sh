#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
model_dir="${LLAMA_MODEL_DIR:-$HOME/llama-models}"
model_file="Hermes3.6-35B-A3B-Uncensored-Genesis-V3-APEX-Compact.gguf"
model_path="$model_dir/$model_file"
partial_model_path="$model_path.part"
model_url="https://huggingface.co/LuffyTheFox/Qwen3.6-35B-A3B-Uncensored-Genesis-Hermes-V3-GGUF/resolve/main/${model_file}?download=true"
expected_model_size=17327724672
expected_model_sha256="50594a0b81d4c951e6925b0e4e6804d2d9d3ce060cabfdf3c697e552415fed0f"
model_size_gib="17.3"

build_tag="b9986"
runtime_root="${LLAMA_RUNTIME_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/llama-server-kit/runtime}"
runtime_dir="$runtime_root/${build_tag}-vulkan"
runtime_archive="$runtime_root/llama-${build_tag}-bin-ubuntu-vulkan-x64.tar.gz"
runtime_url="https://github.com/ggml-org/llama.cpp/releases/download/${build_tag}/$(basename "$runtime_archive")"
expected_runtime_sha256="6ec4c41dbb17590cf0dfbb21ccb842b8e235dc72d9e9556c1db9fe3bc390e768"

log() { printf '[setup] %s\n' "$*"; }
die() { trap - ERR; printf '[setup] FAILED: %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[setup] FAILED with exit code %s\n" "$rc" >&2' ERR

sha256() {
    sha256sum -- "$1" | awk '{print tolower($1)}'
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command '$1' is missing. Install it with: sudo dnf install curl tar coreutils"
}

ensure_model() {
    mkdir -p "$model_dir"

    if [[ -f "$model_path" ]]; then
        if [[ "$(stat -c '%s' "$model_path")" -eq "$expected_model_size" ]]; then
            log "Verifying existing model SHA-256..."
            if [[ "$(sha256 "$model_path")" == "$expected_model_sha256" ]]; then
                log "Model verified: $model_path"
                return
            fi
        fi
        log "Existing model is incomplete or has the wrong SHA-256; repairing it."
        if [[ "$(stat -c '%s' "$model_path")" -lt "$expected_model_size" && ! -e "$partial_model_path" ]]; then
            mv -- "$model_path" "$partial_model_path"
        else
            rm -f -- "$model_path"
        fi
    fi

    if [[ -f "$partial_model_path" && "$(stat -c '%s' "$partial_model_path")" -ge "$expected_model_size" ]]; then
        rm -f -- "$partial_model_path"
    fi

    log "Downloading the verified ${model_size_gib} GiB Qwen model. This is resumable..."
    curl_args=(-L --fail --retry 5 --retry-delay 5 --retry-all-errors -o "$partial_model_path")
    if [[ -s "$partial_model_path" ]]; then
        curl_args+=(-C -)
    fi
    curl "${curl_args[@]}" "$model_url"

    [[ "$(stat -c '%s' "$partial_model_path")" -eq "$expected_model_size" ]] || die "Downloaded model has the wrong size; re-run to resume."
    actual_sha256="$(sha256 "$partial_model_path")"
    [[ "$actual_sha256" == "$expected_model_sha256" ]] || die "Model SHA-256 mismatch. Expected $expected_model_sha256, got $actual_sha256."
    mv -- "$partial_model_path" "$model_path"
    log "Model downloaded and verified: $model_path"
}

ensure_runtime() {
    mkdir -p "$runtime_root" "$runtime_dir"

    if [[ -f "$runtime_archive" ]]; then
        log "Verifying cached llama.cpp Vulkan runtime..."
        if [[ "$(sha256 "$runtime_archive")" != "$expected_runtime_sha256" ]]; then
            rm -f -- "$runtime_archive"
        fi
    fi
    if [[ ! -f "$runtime_archive" ]]; then
        log "Downloading the pinned llama.cpp Vulkan runtime ($build_tag)..."
        curl -L --fail --retry 5 --retry-delay 5 --retry-all-errors -o "$runtime_archive" "$runtime_url"
    fi
    [[ "$(sha256 "$runtime_archive")" == "$expected_runtime_sha256" ]] || die "llama.cpp runtime SHA-256 mismatch."

    runtime_server="$runtime_dir/llama-server"
    runtime_bench="$runtime_dir/llama-bench"
    if [[ ! -f "$runtime_server" || ! -f "$runtime_bench" ]]; then
        log "Extracting the llama.cpp Vulkan runtime..."
        tar -xzf "$runtime_archive" -C "$runtime_dir" --overwrite
    fi
    runtime_server="$(find "$runtime_dir" -type f -name llama-server -print -quit)"
    runtime_bench="$(find "$runtime_dir" -type f -name llama-bench -print -quit)"
    [[ -n "$runtime_server" && -n "$runtime_bench" ]] || die "Runtime extraction is missing llama-server or llama-bench."
    chmod +x "$runtime_server" "$runtime_bench"

    log "Running Vulkan device check..."
    "$runtime_bench" --list-devices
    log "Runtime ready: $runtime_server"
}

log "Profile: Ryzen 9 8945HS / Radeon 780M / Qwen 3.6 35B"
require_command curl
require_command sha256sum
require_command stat
require_command tar
ensure_model
ensure_runtime
chmod +x "$script_dir/start.sh"
log "Setup complete. Start with: bash ./start.sh"
