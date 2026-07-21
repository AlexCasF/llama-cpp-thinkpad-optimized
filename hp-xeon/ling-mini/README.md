# Ling-mini 2.0 — HP Z6 G4 hybrid profile

This folder targets the HP Z6 G4 with dual Xeon Silver 4114 CPUs, 64 GB system RAM, and an NVIDIA Quadro P2200. It downloads the same verified 9.3 GB Ling-mini Q4_K_S GGUF as the ThinkPad profile, but uses the pinned Windows CUDA 12.4 llama.cpp runtime.

The starting profile is intentionally conservative:

| Setting | Value | Reason |
|---|---:|---|
| Context | 131,072 | Full supported context through YaRN |
| GPU runtime | CUDA 12.4 | Matches the Quadro/P2200-era Windows driver path |
| GPU offload | all eligible layers | Allows llama.cpp to place non-MoE tensors on CUDA |
| CPU MoE | first 14 of 20 layers | Leaves the final six routed layers on the ~5 GB GPU budget |
| Threads | 20 / 40 | Decode / prompt threads across the two 10-core CPUs |
| Batch / ubatch | 1024 / 512 | Balanced hybrid CPU/GPU starting point |
| KV cache | q4_0 / q4_0 | Keeps GPU and system-memory pressure low |
| NUMA | distribute | Uses both Xeon sockets |
| mmap | enabled | Keeps CPU-resident expert weights demand-paged |

The start script applies YaRN from Ling's native 32K base and overrides `bailingmoe2.context_length` so the slot is actually initialized at 131,072 tokens. Device selection is automatic by default; this avoids depending on a backend-specific CUDA device label on different driver/runtime combinations. Prompt caching remains enabled so repeated prompts can reuse their common prefix; the profile now uses the newer b10075 runtime, which includes a prompt-cache state-ownership refactor.

This is a hardware-targeted starting profile, not a benchmarked result on the HP workstation. The exact CUDA allocation depends on the Quadro driver and llama.cpp's tensor sizes. If CUDA reports out-of-memory, increase `$nCpuMoe` in `start.ps1` to 16, 18, or 19; that moves more expert weights to CPU. If the GPU has headroom, 14 is the recommended starting value for using the workstation's full 5 GB VRAM budget.

## Install and start

From PowerShell in this folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
.\start.ps1
```

Or double-click `setup.cmd` once and `start.cmd` for daily use. Setup verifies both the GGUF and the CUDA runtime, then lists the detected CUDA devices.

The server automatically uses the workstation's CUDA adapter. If a machine has multiple CUDA adapters and needs an explicit selection, pass the exact name shown by the setup device listing, for example:

```powershell
.\start.ps1 -Device CUDA0
```

The server listens on `http://127.0.0.1:11434`. Test it from another PowerShell window with:

```powershell
curl.exe http://127.0.0.1:11434/health
```

Stop Ollama or another llama server first if port 11434 is occupied. Keep the server window open and press Ctrl+C to stop it.

## Model and runtime provenance

- Model: https://huggingface.co/mradermacher/Huihui-Ling-mini-2.0-abliterated-GGUF
- File: `Huihui-Ling-mini-2.0-abliterated.Q4_K_S.gguf`
- SHA-256: `f80fb22a69b33c019a7e127bd8aa2ee9607b885b1a9dccb9f7d00e9fec3274d2`
- Runtime: `llama-b10075-bin-win-cuda-12.4-x64.zip`
- Runtime SHA-256: `acb782eb7d82b7aefaab4ea4f92f84793d11fdddacf888299ef3af9a63054744`
