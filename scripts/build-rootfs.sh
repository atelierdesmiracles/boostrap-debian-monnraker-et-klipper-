#!/usr/bin/env bash
set -Eeuo pipefail

# Build a Debian root filesystem for Miracle Klipper.
# This creates a rootfs archive, not a bootable disk image.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${ARCH:-arm64}"
SUITE="${DEBIAN_SUITE:-bookworm}"
OUT_DIR="${1:-$ROOT_DIR/dist}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/.build}"
ROOTFS="$WORK_DIR/rootfs"
MIRROR="${DEBIAN_MIRROR:-https://deb.debian.org/debian}"

case "$ARCH" in amd64|arm64|armhf) ;; *) echo "Unsupported ARCH=$ARCH (amd64, arm64, armhf)" >&2; exit 2 ;; esac
case "$SUITE" in bookworm) ;; *) echo "Only the tested suite 'bookworm' is currently enabled" >&2; exit 2 ;; esac
[[ "$(id -u)" -eq 0 ]] || { echo "Run with sudo: sudo env ARCH=arm64 $0" >&2; exit 1; }
for cmd in debootstrap tar xz sha256sum mount umount; do command -v "$cmd" >/dev/null || { echo "Missing host command: $cmd" >&2; exit 1; }; done

mkdir -p "$WORK_DIR" "$OUT_DIR"
# Never delete an arbitrary path. WORK_DIR is controlled by this script's root.
[[ "$ROOTFS" == "$WORK_DIR/rootfs" && "$WORK_DIR" == "$ROOT_DIR/.build" || "$WORK_DIR" == "$ROOT_DIR/.build" ]] || {
  echo "For safety, WORK_DIR must remain $ROOT_DIR/.build" >&2; exit 1;
}
rm -rf -- "$ROOTFS"
mkdir -p "$ROOTFS"

HOST_ARCH="$(dpkg --print-architecture)"
QEMU_BIN=""
case "$ARCH" in
  arm64) QEMU_BIN=qemu-aarch64-static ;;
  armhf) QEMU_BIN=qemu-arm-static ;;
  amd64) QEMU_BIN=qemu-x86_64-static ;;
esac

MOUNTS_ACTIVE=0
cleanup() {
  set +e
  if [[ "$MOUNTS_ACTIVE" == 1 ]]; then
    umount -lf "$ROOTFS/sys" 2>/dev/null
    umount -lf "$ROOTFS/proc" 2>/dev/null
    umount -lf "$ROOTFS/dev/pts" 2>/dev/null
    umount -lf "$ROOTFS/dev" 2>/dev/null
  fi
}
trap cleanup EXIT INT TERM

echo "==> Creating Debian $SUITE rootfs ($ARCH)"
if [[ "$ARCH" == "$HOST_ARCH" ]]; then
  debootstrap --variant=minbase --arch="$ARCH" "$SUITE" "$ROOTFS" "$MIRROR"
else
  if [[ "$ARCH" != amd64 && ! -x "/usr/bin/$QEMU_BIN" ]]; then
    echo "Missing /usr/bin/$QEMU_BIN; install qemu-user-static and configure binfmt_misc." >&2
    exit 1
  fi
  debootstrap --foreign --variant=minbase --arch="$ARCH" "$SUITE" "$ROOTFS" "$MIRROR"
  if [[ -x "/usr/bin/$QEMU_BIN" ]]; then
    install -m 0755 "/usr/bin/$QEMU_BIN" "$ROOTFS/usr/bin/$QEMU_BIN"
  fi
  mount --bind /dev "$ROOTFS/dev"
  mount --bind /dev/pts "$ROOTFS/dev/pts"
  mount -t proc proc "$ROOTFS/proc"
  mount -t sysfs sysfs "$ROOTFS/sys"
  MOUNTS_ACTIVE=1
  chroot "$ROOTFS" /debootstrap/debootstrap --second-stage
  cleanup
  MOUNTS_ACTIVE=0
fi

cp "$ROOT_DIR/scripts/setup-rootfs.sh" "$ROOTFS/tmp/miracle-setup-rootfs.sh"
chmod 0755 "$ROOTFS/tmp/miracle-setup-rootfs.sh"
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sysfs "$ROOTFS/sys"
MOUNTS_ACTIVE=1
chroot "$ROOTFS" /tmp/miracle-setup-rootfs.sh
rm -f "$ROOTFS/tmp/miracle-setup-rootfs.sh"
cleanup
MOUNTS_ACTIVE=0

printf '%s\n' "Miracle Klipper Debian bootstrap" "Suite: $SUITE" "Architecture: $ARCH" "Built: $(date -u +%FT%TZ)" > "$ROOTFS/etc/miracle-klipper-build.txt"
tar --numeric-owner --xattrs --acls -C "$ROOTFS" -c . | xz -T0 -6 > "$OUT_DIR/miracle-klipper-debian-$SUITE-$ARCH-rootfs.tar.xz"
sha256sum "$OUT_DIR/miracle-klipper-debian-$SUITE-$ARCH-rootfs.tar.xz" > "$OUT_DIR/miracle-klipper-debian-$SUITE-$ARCH-rootfs.tar.xz.sha256"
echo "==> Build finished: $OUT_DIR/miracle-klipper-debian-$SUITE-$ARCH-rootfs.tar.xz"
