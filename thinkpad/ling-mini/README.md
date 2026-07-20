# Ling-mini 2.0 — Intel Arc 128K profile

This folder contains the plug-and-play setup for **Huihui-Ling-mini-2.0-abliterated-GGUF** on the ThinkPad Ultra 5 228V / Intel Arc 130V / 32 GB hardware.

The default profile is designed for the fastest general inference while keeping the model entirely in the 16 GB shared Intel GPU allocation:

| Setting | Fast default | Reason |
|---|---:|---|
| GGUF | Q4_K_S, 9.3 GB | Leaves room for KV and scratch buffers |
| Context | 131,072 | Full supported context through YaRN |
| GPU offload | all layers | Avoids CPU expert traffic |
| CPU MoE offload | 0 | The complete model fits in the GPU allocation |
| Batch / ubatch | 4096 / 2048 | Fast prompt processing candidate |
| KV cache | q8_0 / q8_0 | Quality-preserving speed-first setting |
| Flash attention | on | Speed-first SYCL setting |
| Threads | 6 / 7 | Decode / prompt threads |
| Prompt cache | enabled, reuse 256 | Helps repeated prefixes |

## Install and start

From PowerShell in this folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
.\start.ps1
```

Or double-click `setup.cmd` once and `start.cmd` for daily use. Setup downloads the verified Q4_K_S file and pinned Windows SYCL llama.cpp runtime. Model weights are stored in `%USERPROFILE%\llama-models`.

The default server listens on `http://127.0.0.1:11434`. Test it from another PowerShell window:

```powershell
curl.exe http://127.0.0.1:11434/health
```

Stop the server with Ctrl+C before starting another profile on the same port.

## Context and speed variants

The default start command uses the tested 128K profile. Ling supports this through YaRN from its native 32K base:

```powershell
.\start.ps1
```

It uses 131,072 context, YaRN, Q4 K/V cache, batch 2048, and ubatch 1024. If the Intel driver reports out-of-memory, retry with `-FlashAttention auto` or reduce ubatch to 512 in `start.ps1`.

The profile overrides `bailingmoe2.context_length` to 131,072 because the pinned llama-server build otherwise applies a 32K safety cap. Confirm `n_ctx_slot = 131072` in the startup log. See [llama.cpp issue #17459](https://github.com/ggml-org/llama.cpp/issues/17459).

For the optional short-context speed controls, use `-Profile fast` or `-Profile fast-q4`; those explicitly use 32K and are not the production default.

For code-heavy sessions, the optional n-gram speculative profile needs no draft model:

```powershell
.\start.ps1 -Profile ngram
```

It may help repeated code, tool output, or boilerplate, but is not guaranteed to improve normal chat.

## Why MTP, DFlash and TurboQuant are not enabled

- **MTP:** The published Ling configuration has no verified MTP draft head in this GGUF setup.
- **DFlash:** DFlash drafts are target-model-specific; no compatible Ling draft is included here.
- **TurboQuant:** The pinned stock llama.cpp build has no native TurboQuant KV-cache flag, so the profile uses standard llama.cpp KV types.

The default keeps `--mmap` enabled and CPU MoE offload at zero because this model fits the ThinkPad GPU.

## Model and runtime provenance

- Model repository: https://huggingface.co/mradermacher/Huihui-Ling-mini-2.0-abliterated-GGUF
- Selected file: `Huihui-Ling-mini-2.0-abliterated.Q4_K_S.gguf`
- SHA-256: `f80fb22a69b33c019a7e127bd8aa2ee9607b885b1a9dccb9f7d00e9fec3274d2`
- Runtime: official llama.cpp Windows SYCL release `b9986`
- Ling reference: https://huggingface.co/inclusionAI/Ling-mini-2.0
