# Optimized Qwen3.6 35B APEX server for the ThinkPad Ultra 5 228V

This repository runs the tested Qwen3.6 35B A3B Hermes APEX Compact model on the
matching ThinkPad with Intel Arc 130V graphics, 32 GB shared memory, and a 64K
daily context.

## 1. One-time setup

Open PowerShell in this repository directory and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup-production.ps1
```

You can also double-click `setup-production.cmd`.

The setup script downloads the exact 17.3 GB APEX Compact model, verifies it, and
installs the pinned llama.cpp Intel SYCL runtime. Allow time for the download
and make sure you have at least 22 GB of free disk space.

## 2. Recommended performance mode

For maximum inference speed, plug in the laptop and open **PowerShell as
Administrator**. Run this once before a performance-sensitive session:

```powershell
$processor = "54533251-82be-4824-96c1-47b60b740d00"
powercfg /setacvalueindex SCHEME_CURRENT $processor "36687f9e-e3a5-4dbf-b1dc-15eb381c6863" 0
powercfg /setacvalueindex SCHEME_CURRENT $processor "36687f9e-e3a5-4dbf-b1dc-15eb381c6864" 0
powercfg /setacvalueindex SCHEME_CURRENT $processor "36687f9e-e3a5-4dbf-b1dc-15eb381c6865" 0
powercfg /setactive SCHEME_CURRENT
```

This sets the AC processor energy-performance preference to maximum
performance for all processor efficiency classes. It is reversible and does
not force the CPU to stay at full clock speed when idle. Also select
**Performance mode** in Lenovo Vantage if that option is available; Windows
cannot directly control the ThinkPad fan curve through `powercfg`.

To return to the normal Windows preference, select **Recommended** or
**Balanced** in Windows Settings → System → Power & battery.

## 3. Everyday server startup

Stop Ollama first if it is running, because this server uses port `11434`.
Then open PowerShell in the repository directory and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\start-production.ps1
```

Or double-click `start-production.cmd`.

Keep the window open while using the server. Press `Ctrl+C` to stop it.

The server uses the tested stable configuration:

- Hermes APEX Compact model
- 64K context
- q4/q4 KV cache
- 36 CPU MoE layers
- batch 1024 / ubatch 1024
- flash attention auto
- mmap enabled

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
.\start-production.ps1 -ModelPath "D:\models\Hermes3.6-35B-A3B-Uncensored-Genesis-APEX-Compact.gguf"
```

## More detail

- [Complete Windows/Kali/Pi APEX 64K tutorial](docs/llama_cpp_pi_q4_64k_setup.html)
- [Legacy Ollama/Pi 64K tutorial](docs/ollama_pi_kali_q4_64k_setup_final.html)
