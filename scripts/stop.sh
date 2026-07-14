#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
backend="${1:-sycl}"
case "$backend" in
  sycl) compose=compose.sycl.yml ;;
  vulkan) compose=compose.vulkan-wsl.yml ;;
  *) echo "Usage: $0 [sycl|vulkan]" >&2; exit 2 ;;
esac
docker compose --env-file .env -f "$compose" down
