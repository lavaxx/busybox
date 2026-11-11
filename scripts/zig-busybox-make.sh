#!/usr/bin/env bash
# Usage: zig-busybox-make.sh <zig-target-triple> [extra-cflags...]
# Env: ZIG (default: zig), DEFCONFIG (default: configs/lavaxx_defconfig),
#      FORCE_DEFCONFIG=1 to always reinstall defconfig, JOBS,
#      BUILD_DIR — BusyBox out-of-tree dir (make O=...); preferred for CI cache,
#      KEEP_OBJS=1 — skip wiping in-tree objects (implied when BUILD_DIR is set)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${ZIG:-zig}"
TARGET="${1:?zig target triple required}"
shift
DEFCONFIG="${DEFCONFIG:-configs/lavaxx_defconfig}"
BUILD_DIR="${BUILD_DIR:-}"
if command -v nproc >/dev/null 2>&1; then
  JOBS="${JOBS:-$(nproc)}"
elif command -v sysctl >/dev/null 2>&1; then
  JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
else
  JOBS="${JOBS:-4}"
fi

if command -v gcc >/dev/null 2>&1; then
  HOSTCC_BIN=gcc
else
  HOSTCC_BIN="$ZIG cc"
fi

IS_MACOS=0
case "$TARGET" in
  *-macos*|*-darwin*|*-ios*) IS_MACOS=1 ;;
esac
# Native macOS smoke builds use a Darwin-friendly defconfig (no full static).
if [[ "$IS_MACOS" == "1" && "$DEFCONFIG" == "configs/lavaxx_defconfig" ]]; then
  DEFCONFIG="configs/lavaxx_macos_defconfig"
fi

MAKE_O=()
CONFIG_FILE=".config"
BB_BIN="busybox"
if [[ -n "$BUILD_DIR" ]]; then
  mkdir -p "$BUILD_DIR"
  # Normalize to relative-or-absolute path BusyBox accepts for O=.
  MAKE_O=(O="$BUILD_DIR")
  CONFIG_FILE="$BUILD_DIR/.config"
  BB_BIN="$BUILD_DIR/busybox"
  # Out-of-tree objects are per-target; keep them for incremental / CI cache hits.
  KEEP_OBJS="${KEEP_OBJS:-1}"
fi

if [[ ! -f "$CONFIG_FILE" ]] || [[ "${FORCE_DEFCONFIG:-}" == "1" ]]; then
  case "$DEFCONFIG" in
    configs/lavaxx_defconfig|*/lavaxx_defconfig)
      make HOSTCC="$HOSTCC_BIN" "${MAKE_O[@]}" lavaxx_defconfig
      ;;
    configs/lavaxx_macos_defconfig|*/lavaxx_macos_defconfig)
      make HOSTCC="$HOSTCC_BIN" "${MAKE_O[@]}" lavaxx_macos_defconfig
      ;;
    *)
      if [[ -n "$BUILD_DIR" ]]; then
        cp "$DEFCONFIG" "$CONFIG_FILE"
      else
        cp "$DEFCONFIG" .config
      fi
      # Avoid SIGPIPE (141) from `yes` under pipefail when conf closes stdin.
      set +o pipefail
      yes '' | make HOSTCC="$HOSTCC_BIN" "${MAKE_O[@]}" oldconfig >/dev/null
      set -o pipefail
      ;;
  esac
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
if [[ "$IS_MACOS" == "1" ]]; then
  CC_STR="$ZIG cc -target $TARGET"
  # Keep Darwin macros out of the assembler command line (CC is also used for .S).
  MAKE_EXTRA_CFLAGS=(-D_DARWIN_C_SOURCE)
else
  CC_STR="$ZIG cc -target $TARGET -static"
  MAKE_EXTRA_CFLAGS=()
fi
for f in "${EXTRA_CFLAGS[@]}"; do
  CC_STR+=" $f"
done

export SKIP_STRIP=y
# Drop previous in-tree target objects, but keep host kconfig tools under scripts/.
# Skipped for BUILD_DIR / KEEP_OBJS=1 so CI object caches stay warm.
if [[ "${KEEP_OBJS:-0}" != "1" ]]; then
  find . \( -name '*.o' -o -name '*.a' -o -name 'busybox' -o -name 'busybox_unstripped' \) \
    ! -path './scripts/*' ! -path './.git/*' ! -path './.zig-cache/*' ! -path './zig-out/*' \
    ! -path './.build/*' \
    -delete 2>/dev/null || true
fi
rm -f busybox busybox_unstripped
[[ -n "$BUILD_DIR" ]] && rm -f "$BUILD_DIR/busybox" "$BUILD_DIR/busybox_unstripped"

make -j"$JOBS" \
  HOSTCC="$HOSTCC_BIN" \
  CC="$CC_STR" \
  AR="$ZIG ar" \
  RANLIB="$ZIG ranlib" \
  EXTRA_CFLAGS="${MAKE_EXTRA_CFLAGS[*]}" \
  "${MAKE_O[@]}" \
  busybox

# Stage binary at repo-root `busybox` for zig build install step.
if [[ "$BB_BIN" != "busybox" ]]; then
  cp -f "$BB_BIN" busybox
fi

# Strip debug symbols from the final ELF (SKIP_STRIP leaves them otherwise).
if "$ZIG" objcopy --strip-all busybox busybox.stripped 2>/dev/null; then
  mv busybox.stripped busybox
elif command -v llvm-strip >/dev/null 2>&1; then
  llvm-strip busybox
elif command -v strip >/dev/null 2>&1; then
  strip busybox 2>/dev/null || true
fi
