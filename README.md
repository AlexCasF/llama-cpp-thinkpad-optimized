# Optimized Qwen3.6 35B server for the ThinkPad Ultra 5 228V

This repository runs the tested Qwen3.6 35B A3B Q4_K model on the matching
ThinkPad with Intel Arc 130V graphics, 32 GB shared memory, and a 128K context.

## 1. One-time setup

Open PowerShell in this repository directory and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup-production.ps1
```

You can also double-click `setup-production.cmd`.

The setup script downloads the exact 21.7 GB Q4_K model, verifies it, and
installs the pinned llama.cpp Intel SYCL runtime. Allow time for the download
and make sure you have at least 25 GB of free disk space.

## 2. Everyday server startup

Stop Ollama first if it is running, because this server uses port `11434`.
Then open PowerShell in the repository directory and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\start-production.ps1
```

Or double-click `start-production.cmd`.

Keep the window open while using the server. Press `Ctrl+C` to stop it.

The server uses the tested stable configuration:

- 128K context
- q4/q4 KV cache
- 36 CPU MoE layers
- batch 1024 / ubatch 1024
- flash attention enabled
- mmap enabled

To test the benchmark-like batch size, stop the server and run:

```powershell
.\start-production.ps1 -BatchSize 2048 -FlashAttention on
```

Omit these options to use the stable batch-1024 default.

The local API is:

```text
http://127.0.0.1:11434/v1
```

A VMware guest must use the Windows host’s VMware-LAN IP instead of
`127.0.0.1`, for example:

```text
http://10.10.10.1:11434/v1
```

If the model is stored somewhere else, pass its path explicitly:

```powershell
.\start-production.ps1 -ModelPath "D:\models\qwen36-35b-q4_k.gguf"
```

## More detail

- [Complete Windows/Kali/Pi tutorial](docs/llama_cpp_pi_q4_128k_setup.html)
- [Benchmark plan and measured results](results/benchmark-q4-128k-2026-07-14.md)
- [Original tutorial](docs/ollama_pi_kali_q4_256k_setup_final.html)
