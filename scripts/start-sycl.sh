#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

profile="${1:-balanced}"
profile_file="profiles/${profile}.env"
[[ -f .env ]] || { echo "Missing .env. Run: cp .env.example .env" >&2; exit 2; }
[[ -f "$profile_file" ]] || { echo "Unknown profile: $profile" >&2; exit 2; }
[[ -e /dev/dxg ]] || { echo "Missing /dev/dxg. Intel GPU is not exposed to this WSL distro." >&2; exit 2; }

export PROFILE_FILE="$profile_file"
docker compose --env-file .env -f compose.sycl.yml up --build -d
docker compose --env-file .env -f compose.sycl.yml logs -f llama
