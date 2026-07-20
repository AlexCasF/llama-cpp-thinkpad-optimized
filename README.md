# Optimized llama.cpp profiles

This repository contains ready-to-run llama.cpp setups for the two target machines and two models:

- ThinkPad Ultra 5 228V / Intel Arc 130V / 32 GB RAM
- HP Z6 G4 / dual Xeon Silver 4114 / Quadro P2200 / 64 GB RAM
- Qwen 3.6 35B A3B Hermes APEX Compact
- Huihui Ling-mini 2.0 abliterated

Each profile is self-contained. Run `setup` once to download the verified model and pinned llama.cpp runtime, then use `start` for everyday server startup.

## ThinkPad — Qwen 35B

```powershell
cd .\thinkpad\qwen-35b
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
.\start.ps1
```

The default profile uses the tested 64K context and Intel SYCL/Arc settings.

## ThinkPad — Ling-mini

```powershell
cd .\thinkpad\ling-mini
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
.\start.ps1
```

The 9.3 GB Q4_K_S model is offloaded entirely to the Arc GPU. The default profile uses 128K context through YaRN. Optional short-context speed profiles remain available with:

```powershell
.\start.ps1 -Profile fast
```

Use `setup.cmd` and `start.cmd` for double-click wrappers.

## HP Z6 G4 — Qwen 35B

```powershell
cd .\hp-xeon\qwen-35b
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
.\start.ps1
```

This is the existing CPU-only profile for the large Qwen GGUF.

## HP Z6 G4 — Ling-mini

```powershell
cd .\hp-xeon\ling-mini
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
.\start.ps1
```

This profile uses the CUDA llama.cpp runtime, keeps Ling's eligible layers available for GPU offload, and leaves the first 14 of Ling's 20 MoE layers on the Xeon CPUs. The final six layers and shared tensors are eligible for approximately 5 GB of Quadro GPU use. The exact allocation depends on the driver and should be checked on the workstation. If CUDA runs out of memory, increase `$nCpuMoe` in `start.ps1` to 16, 18, or 19.

Use `setup.cmd` and `start.cmd` for double-click wrappers.

## Test the API

The server listens on port `11434`:

```powershell
curl.exe http://127.0.0.1:11434/health
```

Stop Ollama or another server using that port first. Keep the server window open while using it and press `Ctrl+C` to stop it. A VMware guest should call the Windows host through its VMware-LAN IP instead of `127.0.0.1`.

For power-sensitive ThinkPad testing, plug in the laptop and use Lenovo Vantage Performance mode. The complete Windows/Kali/Pi tutorial is available at [full-tutorial.html](full-tutorial.html).
