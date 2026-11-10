# Zig build + release binaries for lavaxx/busybox

**Date:** 2026-11-10  
**Status:** approved approach; awaiting spec review  
**Repo:** `lavaxx/busybox` (fork of `vda-linux/busybox_mirror`)  
**Model:** mirror dropbear’s Zig UX (`~/git/barry/dropbear`), not a pure-Zig rewrite of BusyBox Kbuild

## Problem

We need reproducible, cross-compiled **static BusyBox** binaries for appliance /
embedded Linux use, published the same way as dropbear:

- one command locally: `zig build -Dtarget=… -Doptimize=…`
- GitHub Releases on `zig/v*` tags with musl linux packages + checksums

BusyBox’s official build is GNU Make + Kconfig. Re-implementing that in Zig
(like dropbear’s autoconf-free `build.zig`) is a large ongoing maintenance cost.
We need a practical first version that still feels like the dropbear workflow.

## Goals

- Add `build.zig` / `build.zig.zon` (Zig **0.17+**) as the primary local entry.
- Ship a committed lean static defconfig: `configs/lavaxx_defconfig`.
- Cross-compile static binaries for:
  - `x86_64-linux-musl` → artifact label `linux_amd64`
  - `aarch64-linux-musl` → `linux_arm64`
  - `arm-linux-musleabihf` → `linux_armv7`
- Add `.github/workflows/release-zig.yml` aligned with dropbear’s release job
  (self-hosted `barrymini` runner, `zig/v*` tags, `workflow_dispatch`).
- Produce archives named `busybox_<version>_<label>.tar.gz` containing the
  `busybox` binary, plus `checksums.txt` (sha256).
- Prefer size-optimized prod builds (`ReleaseSmall` / `-Os` equivalent).

## Non-goals

- Windows / busybox-w32.
- macOS or other BSD as **release** targets (Unix-like host may build; only
  Linux musl packages are published).
- Full applet / `make defconfig` feature set.
- Pure Zig replacement of Kconfig / applet table generation (defer).
- UPX packing (optional later; not required for v1).
- Changing BusyBox runtime behaviour beyond build/config/packaging.

## Decision: approach

**Chosen: `build.zig` orchestrates upstream Makefile with `zig cc` as CC.**

Rejected for v1:

1. **Pure Zig compile of all `.c` files** — highest fidelity to dropbear’s
   internals, but BusyBox needs generated headers, applet tables, and
   Kconfig-driven source sets; too much for first ship.
2. **CI/script only** — fastest binary, but breaks the `zig build` UX we want
   to match.

Community precedent: BusyBox + `zig cc -target … -static` via Make works; clang
needs a small set of known workarounds (lld flags, a few configs, occasional
inline-asm).

## Architecture

```
zig build -Dtarget=<triple> -Doptimize=<mode>
        │
        ▼
  build.zig
        │  1. copy configs/lavaxx_defconfig → .config (if missing/forced)
        │  2. make oldconfig / silentoldconfig (non-interactive)
        │  3. make with:
        │       CC="zig cc -target <triple> …"
        │       HOSTCC=… (native zig cc for host tools)
        │       CONFIG_STATIC=y (from defconfig)
        │  4. install busybox → zig-out/bin/busybox
        │
        ▼
  release-zig.yml (on zig/v* or dispatch)
        │  loop triples → tar.gz + checksums → gh release
```

### `build.zig` surface

| Option | Meaning |
|--------|---------|
| `-Dtarget=` | Zig target triple (required for cross builds) |
| `-Doptimize=` | Map to BusyBox CFLAGS (`Debug` / `ReleaseSafe` / `ReleaseFast` / `ReleaseSmall`) |
| `-Ddefconfig=` | Optional path; default `configs/lavaxx_defconfig` |

Install step must leave a single executable at `zig-out/bin/busybox`.

Host tools that BusyBox’s Make runs (applet table generators, etc.) use the
**native** toolchain (`HOSTCC=zig cc` without cross `-target`), while target
objects use the cross `CC`.

### Lean defconfig (`configs/lavaxx_defconfig`)

Intent: static, useful rescue / appliance shell toolkit — not allyesconfig.

Must include:

- `CONFIG_STATIC=y`
- Ash or hush shell (`CONFIG_ASH=y` preferred)
- Everyday recovery applets: at least `ls`, `cat`, `cp`, `mv`, `rm`, `mkdir`,
  `echo`, `printf`, `test`/`[`, `sleep`, `grep`, `find`, `tar`, `gzip`,
  `mount`/`umount`, `ping`, `wget` or `wget`-equivalent HTTP get if it stays
  static-clean

Generation rule for v1: start from upstream `make defconfig`, then turn **off**
large optional groups (SELinux, unnecessary filesystems, rare networking
applets, experimental features) until the three release triples build clean
and the binary stays clearly smaller than a full defconfig. The resulting
file is committed as `configs/lavaxx_defconfig` and is the only supported
config for Zig releases unless `-Ddefconfig=` overrides it.

Must disable (or keep off) options that commonly break under Zig/clang musl
cross builds:

- `CONFIG_TC` (kernel header / API fragility)
- Non-x86 hardware SHA accel where it fails off-x86
- Features that require unavailable host libraries for a fully static musl link

Defconfig is the source of truth; `.config` is generated/build-local and
gitignored if not already.

### Clang / lld compatibility

Expect a minimal patch set under `patches/zig/` (or equivalent committed
diffs), applied by `build.zig` before `make` when needed. Scope limited to
build-system / compiler incompatibilities, not feature changes. Known themes
from prior BusyBox+clang work:

- Drop or rewrite GCC-only linker flags that lld rejects
- Avoid UB / const attributes that clang optimizes differently from gcc
- Inline asm that fails register allocation under clang on some arches

If a patch is not needed after a clean build of the three release triples,
do not add it.

### Release workflow

Mirror `dropbear` `.github/workflows/release-zig.yml`:

- Triggers: `push` tags `zig/v*`, and `workflow_dispatch`
- Runner: `[self-hosted, barrymini]`
- Zig: prefer `/opt/toolchains/zig`, then `$HOME/.local/zig`, then `PATH`
- Prod channel (no `-alpha`/`-beta` in version): `ReleaseSmall`
- Non-prod: `ReleaseSafe`
- Build the three musl triples; archive each `busybox` binary; write
  `checksums.txt`; create/upload GitHub Release titled `busybox <version>`

Tag / version scheme: `zig/v1.37.0` (or fork-chosen version string); pre-releases
use `-alpha` / `-beta` suffixes like dropbear.

## Testing / verification

1. On a Zig 0.17 host:  
   `zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl`  
   → `zig-out/bin/busybox` exists, `file` reports statically linked ELF.
2. Smoke: `zig-out/bin/busybox --help` and a few applets (`echo`, `ls`, `sh -c`)
   under qemu-user or on native arch when available.
3. Repeat for `aarch64-linux-musl` and `arm-linux-musleabihf` (at least produce
   the ELF; runtime smoke where qemu exists).
4. Dry-run packaging locally the same way CI does (tar + sha256).
5. After merge: push a `zig/v…-alpha` tag or use `workflow_dispatch` to validate
   the release job once.

## Risks

| Risk | Mitigation |
|------|------------|
| Clang/lld Build failures | Small committed patches; disable brittle configs |
| Upstream Make assumes gcc | Force `CC`/`HOSTCC`/`CFLAGS` carefully; avoid `EXTRA_CFLAGS` fights |
| Defconfig too lean / too fat | Iterate `lavaxx_defconfig` after first green builds |
| Self-hosted runner / Zig missing | Same failure mode as dropbear; document Zig path |

## Out of scope follow-ups

- Optional `-Dupx`
- Broader target matrix (riscv64, mips, …)
- Native Zig Kconfig (dasimmet-style) if Make orchestration becomes a burden
- Symlink forest install (`busybox --install`) packaging
