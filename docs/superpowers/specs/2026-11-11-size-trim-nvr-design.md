# Trim BusyBox toward ≤800KB (NVR applet set)

**Date:** 2026-11-11  
**Status:** approved to execute (“尽量去做”)  
**Constraint:** stripped ELF ≤ ~800KB on linux musl targets if achievable with `zig cc` + `-Os`

## Context

- Current `zig/v1.39.0-alpha.10` `linux_amd64` stripped ELF ≈ **1137 KiB**.
- Camera/NVR BusyBox `--list` ≈ **220 applets**; our `lavaxx_defconfig` enables ~830 `CONFIG_*=y` (many `FEATURE_*`).
- NVR size may also benefit from older gcc/`-Os` differences; zig/clang may not match exactly.

## Approach

1. Rebuild `configs/lavaxx_defconfig` as an **allowlist** of the NVR applet set (plus required deps).
2. Prefer **lean features**: no Unicode, no LS color, trim FIND/TAR extras, no AWK libm/GNU ext, quieter usage.
3. Keep both `ash` and `hush` (present on NVR); keep `wget` without TLS.
4. Measure stripped amd64/arm64/armv7; if still >800KB, cut next-largest optional features/applets and re-measure.
5. Do **not** use UPX; ship strip-only as today.

## Success

- Best-effort ≤800KB stripped per arch; if unreachable, document achieved size and remaining gap.
- `--list` remains a close match to the NVR set (document intentional drops).

## Result (local `zig cc` / musl / `-Os` + strip)

| Target | Stripped ELF |
|--------|--------------|
| `x86_64-linux-musl` | **722048** (~705 KiB) |
| `aarch64-linux-musl` | **734960** (~717 KiB) |
| `arm-linux-musleabihf` | **775896** (~757 KiB) |

Intentional deltas vs camera `--list`:

- Dropped **`hush`** (keep **`ash`** / `sh`) — second shell was the cheapest large cut to clear armv7 under 800KB.
- Trimmed many `FEATURE_*` (Unicode/LS color/AWK libm/extra FIND·TAR·syslog/vi/volume_id probes).
- Kept **`wget`** without TLS (lavaxx need; not on the pasted NVR `--list`).
- Disabled `FEATURE_VOLUMEID_LINUXSWAP` (zig/lld hit undefined `bb_SWAPSPACE2`).
