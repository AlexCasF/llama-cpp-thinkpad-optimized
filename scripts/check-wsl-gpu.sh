#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ! -e /dev/dxg ]]; then
  cat >&2 <<'MSG'
/dev/dxg is missing. Update WSL (`wsl --update` in Windows PowerShell), make
sure Docker Desktop uses the WSL2 engine, and enable integration for this distro.
MSG
  exit 1
fi

echo "Found /dev/dxg"
echo "Testing the official llama.cpp Intel image..."
docker run --rm \
  --device /dev/dxg \
  --mount type=bind,src=/usr/lib/wsl,dst=/usr/lib/wsl,readonly \
  -e ONEAPI_DEVICE_SELECTOR=level_zero:gpu \
  --entrypoint /bin/bash \
  ghcr.io/ggml-org/llama.cpp:server-intel \
  -lc 'export LD_LIBRARY_PATH="/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}"; exec /app/llama-server --list-devices'
