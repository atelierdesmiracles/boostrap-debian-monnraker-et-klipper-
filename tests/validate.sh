#!/usr/bin/env bash
# Static, offline checks for Miracle Klipper build wiring and release hygiene.
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash -n scripts/build-rootfs.sh
bash -n scripts/setup-rootfs.sh

grep -q 'mainsail-crew/mainsail' scripts/setup-rootfs.sh
grep -q 'klipper.service' scripts/setup-rootfs.sh
grep -q 'moonraker.service' scripts/setup-rootfs.sh
grep -q 'systemd systemd-sysv' scripts/setup-rootfs.sh
grep -q 'host: 127.0.0.1' scripts/setup-rootfs.sh

if grep -RniE 'https?://[^ ]*fluidd|git clone[^\n]*fluidd|/var/www/fluidd' scripts; then
  echo "Fluidd installation reference found but this project must be Mainsail-only." >&2
  exit 1
fi

if grep -RniE 'gh run download [0-9]+' .github/workflows; then
  echo "Workflow must not download artifacts using a hard-coded run ID." >&2
  exit 1
fi
if grep -RniE 'TAG="v[0-9]+\.[0-9]+\.[0-9]+"' .github/workflows; then
  echo "Release version must come from the tag/event, not a hard-coded workflow constant." >&2
  exit 1
fi

grep -q 'KLIPPER_REF' scripts/setup-rootfs.sh
grep -q 'MOONRAKER_REF' scripts/setup-rootfs.sh
grep -q 'MAINSAIL_VERSION' scripts/setup-rootfs.sh

echo "Static validation passed."
