#!/usr/bin/env bash
set -Eeuo pipefail

# Build a Debian rootfs archive for Miracle Klipper.
# Usage: sudo ARCH=arm64 ./scripts/build-rootfs.sh [output-directory]
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${ARCH:-arm64}"
SUITE="${DEBIAN_SUITE:-bookworm}"
OUT_DIR="${1:-$ROOT_DIR/dist}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/.build}"
ROOTFS="$WORK_DIR/rootfs"

case "$ARCH" in
  amd64|arm64|armhf) ;;
  *) echo "Unsupported ARCH='$ARCH'. Use amd64, arm64, or armhf." >&2; exit 2 ;;
esac

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root, for example: sudo env ARCH=arm64 $0" >&2
  exit 1
fi

for cmd in debootstrap tar xz; do
  command -v "$cmd" >/dev/null || { echo "Missing host tool: $cmd" >&2; exit 1; }
done

rm -rf "$ROOTFS"
mkdir -p "$WORK_DIR" "$OUT_DIR"

echo "==> Creating Debian $SUITE rootfs ($ARCH)"
if [[ "$ARCH" == "$(dpkg --print-architecture)" ]]; then
  debootstrap --variant=minbase --arch="$ARCH" "$SUITE" "$ROOTFS" https://deb.debian.org/debian
else
  debootstrap --foreign --variant=minbase --arch="$ARCH" "$SUITE" "$ROOTFS" https://deb.debian.org/debian
  if [[ -x "/usr/bin/qemu-$([[ "$ARCH" == arm64 ]] && echo aarch64 || ([[ "$ARCH" == armhf ]] && echo arm || echo x86_64))-static" ]]; then
    cp "/usr/bin/qemu-$([[ "$ARCH" == arm64 ]] && echo aarch64 || ([[ "$ARCH" == armhf ]] && echo arm || echo x86_64))-static" "$ROOTFS/usr/bin/"
  fi
  mount --bind /dev "$ROOTFS/dev"
  mount --bind /dev/pts "$ROOTFS/dev/pts"
  mount -t proc proc "$ROOTFS/proc"
  mount -t sysfs sysfs "$ROOTFS/sys"
  cleanup_mounts() {
    umount -lf "$ROOTFS/sys" 2>/dev/null || true
    umount -lf "$ROOTFS/proc" 2>/dev/null || true
    umount -lf "$ROOTFS/dev/pts" 2>/dev/null || true
    umount -lf "$ROOTFS/dev" 2>/dev/null || true
  }
  trap cleanup_mounts EXIT
  chroot "$ROOTFS" /debootstrap/debootstrap --second-stage
  cleanup_mounts
  trap - EXIT
fi

cp "$ROOT_DIR/scripts/setup-rootfs.sh" "$ROOTFS/tmp/miracle-setup-rootfs.sh"
chmod +x "$ROOTFS/tmp/miracle-setup-rootfs.sh"

mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sysfs "$ROOTFS/sys"
cleanup_setup_mounts() {
  umount -lf "$ROOTFS/sys" 2>/dev/null || true
  umount -lf "$ROOTFS/proc" 2>/dev/null || true
  umount -lf "$ROOTFS/dev/pts" 2>/dev/null || true
  umount -lf "$ROOTFS/dev" 2>/dev/null || true
}
trap cleanup_setup_mounts EXIT

chroot "$ROOTFS" /tmp/miracle-setup-rootfs.sh
rm -f "$ROOTFS/tmp/miracle-setup-rootfs.sh"
cleanup_setup_mounts
trap - EXIT

printf '%s\n' "Miracle Klipper Debian bootstrap" "Suite: $SUITE" "Architecture: $ARCH" "Built: $(date -u +%FT%TZ)" > "$ROOTFS/etc/miracle-klipper-build.txt"
tar --numeric-owner --xattrs -C "$ROOTFS" -c . | xz -T0 -9e > "$OUT_DIR/miracle-klipper-debian-$SUITE-$ARCH-rootfs.tar.xz"
sha256sum "$OUT_DIR/miracle-klipper-debian-$SUITE-$ARCH-rootfs.tar.xz" > "$OUT_DIR/miracle-klipper-debian-$SUITE-$ARCH-rootfs.tar.xz.sha256"
echo "==> Built: $OUT_DIR/miracle-klipper-debian-$SUITE-$ARCH-rootfs.tar.xz"
