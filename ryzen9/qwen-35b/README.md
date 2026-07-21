# Ryzen 9 / Qwen 3.6 35B

This profile targets Fedora Linux on the Ryzen 9 8945HS / Radeon 780M / 64 GB machine. It uses the official llama.cpp Linux Vulkan runtime and the Radeon iGPU as `Vulkan0`.

## Install and start

```bash
# Only needed if Fedora's Vulkan stack is not already installed:
sudo dnf install curl tar coreutils vulkan-loader mesa-vulkan-drivers vulkan-tools

cd ryzen9/qwen-35b
bash ./setup.sh
bash ./start.sh
```

The setup downloads and verifies the 17.3 GiB Q4 GGUF and the pinned llama.cpp Vulkan runtime. It also runs `llama-bench --list-devices`; the output should show the Radeon 780M. The server uses 64K context, q4/q4 KV cache, 36 CPU MoE layers, 8 decode threads, 16 prompt threads, and batch/ubatch 1024/1024.

The API listens on port `11434`. Check it from another terminal:

```bash
curl http://127.0.0.1:11434/health
```

If Vulkan numbers the Radeon differently, select the device explicitly:

```bash
LLAMA_DEVICE=Vulkan1 bash ./start.sh
```

For maximum CPU clocks while testing, use Fedora's Performance power profile if available:

```bash
powerprofilesctl set performance
```
