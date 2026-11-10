#!/usr/bin/env bash
# Usage: zig-busybox-make.sh <zig-target-triple> [extra-cflags...]
# Env: ZIG (default: zig), DEFCONFIG (default: configs/lavaxx_defconfig),
#      FORCE_DEFCONFIG=1 to always reinstall defconfig, JOBS
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${ZIG:-zig}"
TARGET="${1:?zig target triple required}"
shift
DEFCONFIG="${DEFCONFIG:-configs/lavaxx_defconfig}"
if command -v nproc >/dev/null 2>&1; then
  JOBS="${JOBS:-$(nproc)}"
elif command -v sysctl >/dev/null 2>&1; then
  JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
else
  JOBS="${JOBS:-4}"
fi

if [[ ! -f .config ]] || [[ "${FORCE_DEFCONFIG:-}" == "1" ]]; then
  if [[ "$DEFCONFIG" == "configs/lavaxx_defconfig" ]] || [[ "$DEFCONFIG" == */lavaxx_defconfig ]]; then
    make HOSTCC="$ZIG cc" lavaxx_defconfig
  else
    cp "$DEFCONFIG" .config
    # Avoid SIGPIPE (141) from `yes` under pipefail when conf closes stdin.
    set +o pipefail
    yes '' | make HOSTCC="$ZIG cc" oldconfig >/dev/null
    set -o pipefail
  fi
fi

# Optional clang/lld patches (idempotent via --forward / -N).
if [[ -d patches/zig ]]; then
  shopt -s nullglob
  for p in patches/zig/*.patch; do
    patch -p1 --forward --batch <"$p" >/dev/null 2>&1 || true
  done
  shopt -u nullglob
fi

EXTRA_CFLAGS=("$@")
# BusyBox Make expects CC as one shell word-split string.
CC_STR="$ZIG cc -target $TARGET -static"
for f in "${EXTRA_CFLAGS[@]}"; do
  CC_STR+=" $f"
done

export SKIP_STRIP=y
make -j"$JOBS" \
  HOSTCC="$ZIG cc" \
  CC="$CC_STR" \
  AR="$ZIG ar" \
  RANLIB="$ZIG ranlib" \
  busybox
