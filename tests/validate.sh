#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
bash -n scripts/build-rootfs.sh
bash -n scripts/setup-rootfs.sh
grep -q 'mainsail-crew/mainsail' scripts/setup-rootfs.sh
grep -q 'klipper.service' scripts/setup-rootfs.sh
grep -q 'moonraker.service' scripts/setup-rootfs.sh
if grep -RniE 'fluidd|fluidd\.xyz' README.md scripts; then
  echo "Fluidd reference found but this project must be Mainsail-only." >&2
  exit 1
fi
grep -q 'systemd systemd-sysv' scripts/setup-rootfs.sh
grep -q 'host: 127.0.0.1' scripts/setup-rootfs.sh
echo "Static validation passed."
