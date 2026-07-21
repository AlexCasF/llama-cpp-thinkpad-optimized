# Ryzen 9 / Ling-mini 2.0

This profile targets Fedora Linux on the Ryzen 9 8945HS / Radeon 780M / 64 GB machine. It uses the official llama.cpp Linux Vulkan runtime and offloads Ling-mini completely to the Radeon iGPU.

## Install and start

```bash
# Only needed if Fedora's Vulkan stack is not already installed:
sudo dnf install curl tar coreutils vulkan-loader mesa-vulkan-drivers vulkan-tools

cd ryzen9/ling-mini
bash ./setup.sh
bash ./start.sh
```

The setup downloads and verifies the 9.3 GiB Q4_K_S GGUF and the pinned llama.cpp Vulkan runtime. It also runs `llama-bench --list-devices`; the output should show the Radeon 780M. The start profile uses 128K context through YaRN, q4/q4 KV cache, all GPU layers, 8 decode threads, 16 prompt threads, batch/ubatch 2048/1024, flash attention, and mmap.

The API listens on port `11434`. Check it from another terminal:

```bash
curl http://127.0.0.1:11434/health
```

If Vulkan numbers the Radeon differently, select the device explicitly:

```bash
LLAMA_DEVICE=Vulkan1 bash ./start.sh
```

For maximum CPU/GPU clocks while testing, use Fedora's Performance power profile if available:

```bash
powerprofilesctl set performance
```
