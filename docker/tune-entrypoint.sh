#!/usr/bin/env bash
set -Eeuo pipefail

BENCH_BIN="${LLAMA_BENCH_BIN:-/app/llama-bench}"
MODEL_PATH="${MODEL_PATH:-}"
OUT_DIR="${OUT_DIR:-/results}"
REPETITIONS="${REPETITIONS:-2}"

if [[ ! -x "$BENCH_BIN" ]]; then
  echo "ERROR: llama-bench was not found at: $BENCH_BIN" >&2
  exit 2
fi
if [[ -z "$MODEL_PATH" || ! -f "$MODEL_PATH" ]]; then
  echo "ERROR: MODEL_PATH is unset or unreadable: ${MODEL_PATH:-<unset>}" >&2
  exit 2
fi
mkdir -p "$OUT_DIR"

if [[ -d /usr/lib/wsl/lib ]]; then
  export LD_LIBRARY_PATH="/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}"
fi
if [[ "${LLAMA_BACKEND:-}" == "vulkan-wsl" ]]; then
  export MESA_D3D12_DEFAULT_ADAPTER_NAME="${MESA_D3D12_DEFAULT_ADAPTER_NAME:-Intel}"
  if [[ -z "${VK_DRIVER_FILES:-}" && -z "${VK_ICD_FILENAMES:-}" ]]; then
    for icd in /usr/share/vulkan/icd.d/dzn_icd.x86_64.json /usr/share/vulkan/icd.d/dzn_icd.json; do
      [[ -f "$icd" ]] && export VK_DRIVER_FILES="$icd" && break
    done
  fi
fi

common=(
  -m "$MODEL_PATH"
  -ngl "${N_GPU_LAYERS:-99}"
  -fa "${FLASH_ATTN:-auto}"
  -ctk "${CACHE_TYPE_K:-q8_0}"
  -ctv "${CACHE_TYPE_V:-q8_0}"
  -r "$REPETITIONS"
  -o csv
)

run_case() {
  local label="$1"; shift
  local outfile="$OUT_DIR/${label}.csv"
  echo
  echo "=== $label ==="
  echo "$BENCH_BIN ${common[*]} $*"
  if "$BENCH_BIN" "${common[@]}" "$@" >"$outfile"; then
    echo "Saved: $outfile"
  else
    local rc=$?
    echo "FAILED (exit $rc): $label" | tee "$OUT_DIR/${label}.failed.txt" >&2
  fi
}

cat > "$OUT_DIR/README.txt" <<'INFO'
Each CSV is one llama-bench case. Compare avg_ts (tokens/second):
- tg-* files measure decode/token generation.
- pp-* files measure prompt processing/prefill.
Choose the lowest N_CPU_MOE that remains stable without memory pressure,
then the fastest thread count, then the largest ubatch that fits.
INFO

# Stage 1: find how many of the 40 MoE layers must remain on CPU.
# Lower N_CPU_MOE is faster but consumes more iGPU/shared memory.
for n in ${TUNE_MOE_VALUES:-40 36 32 28 24}; do
  run_case "tg-moe-${n}" -ncmoe "$n" -t "${THREADS:-6}" -ub 512 -p 0 -n 128
  run_case "pp-moe-${n}" -ncmoe "$n" -t "${THREADS:-6}" -ub 512 -p 2048 -n 0
 done

# Stage 2: tune decode threads. Eight logical CPUs are available on the 228V;
# 5-7 usually leaves scheduling headroom, but the benchmark decides.
for t in ${TUNE_THREAD_VALUES:-4 5 6 7 8}; do
  run_case "tg-threads-${t}" -ncmoe "${TUNE_N_CPU_MOE:-28}" -t "$t" -ub 512 -p 0 -n 128
 done

# Stage 3: tune physical prompt batch. Larger values can greatly improve agent
# prefill but need more transient shared memory.
for ub in ${TUNE_UBATCH_VALUES:-256 512 1024 2048}; do
  run_case "pp-ubatch-${ub}" -ncmoe "${TUNE_N_CPU_MOE:-28}" -t "${TUNE_THREADS:-6}" -ub "$ub" -p 4096 -n 0
 done

echo
echo "Tuning finished. Results are in: $OUT_DIR"
