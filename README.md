# Qwen3.6 35B on Intel Arc 130V: llama.cpp tuning kit

This kit targets the following laptop:

- Windows 11
- Intel Core Ultra 5 228V, 8 logical processors
- Intel Arc 130V integrated GPU
- 32 GB LPDDR5X shared by Windows, the CPU, and the iGPU
- `huihui_ai/Qwen3.6-abliterated:35b`, roughly 24 GB, Q4_K_M GGUF

## Recommended architecture

Use the native Windows SYCL build as the primary path. The official llama.cpp Windows package includes the SYCL runtime, and the SYCL backend supports built-in Intel Arc GPUs. Native Windows avoids the extra WSL/Docker memory boundary and is both simpler and easier to benchmark on this 32 GB machine.

Docker/WSL remains available as a reproducible fallback, but it is not the best default for this laptop. Its 26 GB WSL ceiling leaves too little room for normal VMware guests.

One important observation from this machine: `ollama ps` reports this model as `100% CPU`, and the Ollama-launched `llama-server.exe` has no GPU offload or MoE split flags. Its roughly 22.9 GB peak is therefore a CPU-only baseline, not the optimized Arc result.

## What we keep from the videos

| Video idea | Treatment on this laptop |
|---|---|
| `--n-gpu-layers 99` | Keep. Offer all always-active layers to the Arc GPU. |
| `--n-cpu-moe N` | Keep and benchmark. Lower `N` moves more experts to the shared-memory iGPU and can improve decode speed, but raises memory pressure. |
| `--no-mmap` | Optional. The `video-fast` profile and `tune.ps1 -NoMmap` test it; it is not assumed to win. |
| `--mlock` | Opt-in only with `-Mlock`. It can prevent paging but may starve Windows and VMware. |
| Cache reuse | Keep `--cache-prompt --cache-reuse 256`; this matters for coding agents with changing tool prompts. |
| Threads | Benchmark 4, 5, 6, and 7. Eight logical processors does not mean eight is fastest. |
| Physical batch | Benchmark 256, 512, 1024, and 2048. Larger values mainly help prompt processing and consume more memory. |
| KV compression | Use stable `q8_0/q8_0` or `q4_0/q4_0`. The video’s TurboQuant names are not stable llama.cpp server flags. |
| Speculative decoding | Omit. The transcript reports it was slower for this MoE/SSM model. |
| REAP pruning | Not applied. It requires a separately pruned model and is not a runtime flag for this Ollama GGUF. |

The central rule is to optimize two different workloads separately: token generation (`tg`) for conversational speed and prompt processing (`pp`) for coding-agent time-to-first-token.

## Plug-and-play native Windows setup

Open PowerShell in this directory:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\native-windows\setup.ps1
```

The setup script:

1. Downloads and SHA-256 verifies the pinned official llama.cpp Windows SYCL build.
2. Hard-links the already-downloaded Ollama GGUF to `C:\Users\<you>\llama-models`.
3. Checks that the Arc 130V is visible to the SYCL backend.

Start the first GPU test:

```powershell
.\native-windows\start-server.ps1 -Profile safe
```

Test the OpenAI-compatible API from another PowerShell window:

```powershell
.\scripts\test-api.ps1
```

The local API is `http://localhost:8080/v1`. A VMware guest should call the Windows host’s reachable IP address, not assume that its own `localhost` is the host. Windows Firewall may need an inbound rule for TCP port 8080.

If the model is not managed by Ollama, skip export and provide a GGUF path yourself:

```powershell
.\native-windows\setup.ps1 -SkipModelExport
.\native-windows\start-server.ps1 -ModelPath "D:\models\qwen3.6-35b.gguf" -Profile safe
```

## One-click production startup

For a new machine, first double-click `setup-production.cmd` or run the setup
script below. It downloads the exact tested 21.7 GB Q4_K GGUF with resume
support, verifies its SHA-256, and installs the pinned SYCL runtime:

```powershell
.\setup-production.ps1
```

After the one-time setup, use the native Windows launcher. It starts the tested
128K q4/q4 profile on TCP port 11434, preserving the Pi configuration below,
and keeps the server logs visible:

```powershell
.\start-production.ps1
```

You can also double-click `start-production.cmd`. If the GGUF is stored
elsewhere, pass it explicitly:

```powershell
.\start-production.ps1 -ModelPath "D:\models\qwen36-35b-q4_k.gguf"
```

Native Windows is the recommended production path for this laptop because it
does not add Docker/WSL memory overhead. The Docker Desktop fallback remains:

```bash
bash scripts/start-sycl.sh balanced
```

The launcher sets the important server flags: `--n-gpu-layers 99`, `--n-cpu-moe`, `--flash-attn auto`, one slot, prompt caching, `--cache-reuse 256`, tuned logical/physical batch sizes, and stable KV types. It intentionally does not enable speculative decoding.

## Starting profiles

These are starting points, not claimed universal optima. The benchmark must choose the final `N_CPU_MOE`, threads, and physical batch for this exact model and build.

| Profile | Context | CPU MoE | Physical batch | KV | mmap |
|---|---:|---:|---:|---|---|
| `safe` | 64K | 36 | 512 | q8/q8 | on |
| `balanced` | 128K | 36 | 1024 | q4/q4 | on |
| `speed` | 64K | 28 | 2048 | q8/q8 | on |
| `video-fast` | 64K | 28 | 1024 | q8/q8 | off |
| `long` | 256K | 36 | 1024 | q4/q4 | on |

Use `balanced` as the normal production profile when VMware guests are running: it provides 128K context with q4/q4 KV compression. Use `safe` first for initial validation, then try `speed` for shorter-context throughput. Use `long` only when the full 256K context is required. Use `video-fast` only to measure whether no-mmap helps on this machine. Use `-Mlock` only after confirming the model fits with all other host applications closed.

Examples:

```powershell
.\native-windows\start-server.ps1 -Profile speed
.\native-windows\start-server.ps1 -Profile speed -NCPUMOE 24 -Threads 6 -ThreadsBatch 7 -UBatch 2048
.\native-windows\start-server.ps1 -Profile video-fast -Mlock
```

## Benchmark the actual sweet spot

Stop Ollama and any running llama-server first. The 35B model needs most of the laptop’s physical memory, so do not benchmark with VMware guests or Chrome consuming substantial RAM.

Run the native sweep:

```powershell
.\native-windows\tune.ps1
```

Then compare the `avg_ts` column in `results/native/*.csv`:

- For decode speed, choose the lowest `N_CPU_MOE` that remains stable and does not cause paging.
- For coding-agent prompt processing, choose the largest physical batch whose `pp` result improves without an out-of-memory failure.
- Choose threads independently; leave scheduling headroom for the GPU runtime and Windows.
- Re-run with `-NoMmap` to compare the video’s no-mmap idea.

The sweep tests:

1. MoE split: 40, 36, 32, 28, 24 CPU-MoE layers.
2. Decode threads: 4, 5, 6, 7.
3. Physical batch: 256, 512, 1024, 2048.

`llama-bench` measures prompt processing and token generation separately, so it is more useful than choosing flags from a discrete-GPU video or from Ollama’s CPU-only run.

## Docker/WSL fallback

Use this only when the native Windows binary is unavailable or a containerized environment is specifically required.

1. Copy `.wslconfig.example` to `C:\Users\<you>\.wslconfig` and run `wsl --shutdown`.
2. In WSL, run `cp .env.example .env`.
3. Check `/dev/dxg` with `bash scripts/check-wsl-gpu.sh`.
4. Start with `bash scripts/start-sycl.sh safe`.

The example caps WSL at 26 GB. That is a model-friendly Docker ceiling based on the observed 22.9 GB native CPU peak, but it leaves only about 6 GB outside WSL and is not compatible with two normal VMware guests. Native Windows is the correct path for that workload.

If SYCL-over-WSL fails, the experimental Vulkan path is available:

```bash
bash scripts/start-vulkan.sh safe
bash scripts/tune.sh vulkan
```

## Memory reality

The Arc 130V’s reported 16 GB GPU memory is shared system memory, not 16 GB in addition to the laptop’s 32 GB. Model weights, GPU buffers, KV cache, Windows, Docker/WSL, VMware, and Chrome all compete for the same pool. A lower `N_CPU_MOE` may improve tokens per second while making the machine unusable through paging.

The practical tuning order is:

1. Keep one slot and start with `safe`.
2. Lower `N_CPU_MOE` until the next step causes instability or paging.
3. Tune decode threads.
4. Increase physical batch for agent prompt processing.
5. Increase context only when the speed profile is stable.
6. Test no-mmap and then mlock as separate experiments.

If both VMware guests must run with meaningful memory, no llama.cpp flag can make a 23 GB model fit comfortably in the remaining RAM. Use a smaller model, a smaller quantization, or reduce the guest allocations.
