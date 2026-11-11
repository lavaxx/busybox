# Zig build + musl release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `zig build` orchestration over BusyBox’s Makefile (`zig cc` cross compiler), a lean static `configs/lavaxx_defconfig`, and a dropbear-aligned `release-zig.yml` that publishes three linux-musl BusyBox archives.

**Architecture:** `build.zig` does not reimplement Kbuild. It installs the lean defconfig, runs non-interactive `make oldconfig`, then `make` with `HOSTCC=zig cc` (native) and `CC=zig cc -target <triple> …` (cross), copies the resulting static `busybox` into `zig-out/bin/`, and the GitHub workflow loops the three release triples into tar.gz + checksums.

**Tech Stack:** Zig 0.17+, GNU Make, BusyBox upstream Kbuild, musl via Zig, GitHub Actions on self-hosted `barrymini`.

**Spec:** `docs/superpowers/specs/2026-11-10-zig-build-release-design.md`

## Global Constraints

- Zig minimum version: `0.17.0`
- Release targets only: `x86_64-linux-musl` (`linux_amd64`), `aarch64-linux-musl` (`linux_arm64`), `arm-linux-musleabihf` (`linux_armv7`)
- Static binary only (`CONFIG_STATIC=y`); no Windows / no macOS release artifacts
- Prod optimize: `ReleaseSmall`; non-prod (`-alpha`/`-beta`): `ReleaseSafe`
- Tags: `zig/v*`; archive name: `busybox_<version>_<label>.tar.gz`
- Do not rewrite applet generation in Zig; keep upstream Make
- Prefer minimal clang/lld patches under `patches/zig/` only when a release triple fails without them
- Reference UX: `~/git/barry/dropbear` `build.zig` + `.github/workflows/release-zig.yml`

## File structure

| Path | Responsibility |
|------|----------------|
| `build.zig` | Options, map optimize→CFLAGS, invoke Make, install `zig-out/bin/busybox` |
| `build.zig.zon` | Package metadata / Zig 0.17 floor |
| `configs/lavaxx_defconfig` | Committed lean static Kconfig |
| `scripts/zig-busybox-make.sh` | Shell helper: quoting-safe Make invocation (called by `build.zig`) |
| `patches/zig/*.patch` | Optional clang/lld fixes (add only if needed) |
| `.github/workflows/release-zig.yml` | Tag/dispatch release build + publish |
| `.gitignore` | Allow `.github/**`; ignore `zig-out/` (`.zig-cache` already via `.*`) |
| `README.lavaxx.md` or short `README` section | How to `zig build` / release (keep upstream README intact via additive file) |

---

### Task 1: Unblock `.github` and ignore Zig outputs

**Files:**
- Modify: `.gitignore`
- Test: `git check-ignore -v .github/workflows/x.yml zig-out/bin/busybox`

**Interfaces:**
- Consumes: none
- Produces: trackable `.github/` tree; untracked `zig-out/`

- [ ] **Step 1: Patch `.gitignore`**

After the existing “Never ignore these” block that has `!.gitignore`, add:

```gitignore
!.github
!.github/**

#
# Zig build
#
/zig-out/
```

Keep the existing `.*` rule (it still ignores `.config`, `.zig-cache`, etc.).

- [ ] **Step 2: Verify ignore rules**

Run:

```bash
git check-ignore -v .github/workflows/release-zig.yml || echo "NOT_IGNORED_OK"
git check-ignore -v zig-out/bin/busybox
```

Expected: first path prints `NOT_IGNORED_OK` (or no match); second path matches `/zig-out/`.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "$(cat <<'EOF'
chore: track .github and ignore zig-out

BusyBox's .* gitignore blocked GitHub Actions; Zig outputs stay local.
EOF
)"
```

---

### Task 2: Create lean `configs/lavaxx_defconfig`

**Files:**
- Create: `configs/lavaxx_defconfig`
- Test: `make lavaxx_defconfig` then `grep` key symbols

**Interfaces:**
- Consumes: upstream `make defconfig` machinery (`configs/%_defconfig` → copy to `.config`)
- Produces: committed defconfig with `CONFIG_STATIC=y` and recovery applets from the spec

- [ ] **Step 1: Generate a starting `.config` on the build host**

From repo root (needs `gcc` or `zig cc` as HOSTCC only for kconfig tools):

```bash
rm -f .config
make HOSTCC="zig cc" defconfig
cp .config /tmp/busybox-full.config
```

Expected: `.config` exists and contains many `CONFIG_*=y` lines.

- [ ] **Step 2: Apply lean + clang-safe edits**

Create `configs/lavaxx_defconfig` by copying `/tmp/busybox-full.config` and forcing at least:

```
CONFIG_STATIC=y
# CONFIG_TC is not set
# CONFIG_FEATURE_TC_INGRESS is not set
# CONFIG_SHA1_HWACCEL is not set
# CONFIG_SHA256_HWACCEL is not set
```

Also turn **off** large optional groups until the file is clearly leaner than full defconfig (examples to disable if present): SELinux, PAM, unnecessary filesystem helpers that pull complex kernel UAPI, rare networking (e.g. `CONFIG_TRACEROUTE6` ok to keep or drop; prefer keep `ping`, `wget`/`wget`-like if static-clean). Keep ash (`CONFIG_ASH=y`) and the recovery applet set from the spec: `ls`, `cat`, `cp`, `mv`, `rm`, `mkdir`, `echo`, `printf`, `test`/`[`, `sleep`, `grep`, `find`, `tar`, `gzip`, `mount`/`umount`, `ping`.

Save the result as `configs/lavaxx_defconfig` (BusyBox expects the `configs/<name>_defconfig` naming so `make lavaxx_defconfig` works).

- [ ] **Step 3: Install and resolve the defconfig**

```bash
make HOSTCC="zig cc" lavaxx_defconfig
grep -E '^CONFIG_STATIC=y$' .config
grep -E '^# CONFIG_TC is not set$' .config || grep -E '^CONFIG_TC=n' .config || ! grep -E '^CONFIG_TC=y$' .config
grep -E '^CONFIG_ASH=y$' .config
```

Expected: static on, TC not enabled, ash on. If `make lavaxx_defconfig` is not wired, use:

```bash
cp configs/lavaxx_defconfig .config
make HOSTCC="zig cc" oldconfig </dev/null
```

and keep the committed file identical to the post-`oldconfig` `.config` (or the fragment BusyBox’s `%_defconfig` rule expects — match whatever `make help` lists for other `configs/*_defconfig` files).

- [ ] **Step 4: Commit**

```bash
git add configs/lavaxx_defconfig
git commit -m "$(cat <<'EOF'
chore: add lavaxx lean static BusyBox defconfig

Static musl-oriented baseline with ash and recovery applets; TC/HW SHA off.
EOF
)"
```

---

### Task 3: Add `scripts/zig-busybox-make.sh` + `build.zig` / `build.zig.zon`

**Files:**
- Create: `scripts/zig-busybox-make.sh`
- Create: `build.zig`
- Create: `build.zig.zon`
- Test: `zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl`

**Interfaces:**
- Consumes: `configs/lavaxx_defconfig` (default); Zig target/optimize options
- Produces: `zig-out/bin/busybox` static ELF for the requested triple

- [ ] **Step 1: Write `build.zig.zon`**

```zig
.{
    .name = .busybox,
    .version = "1.39.0",
    .minimum_zig_version = "0.17.0",
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "configs",
        "scripts",
        "patches",
        // BusyBox sources are the rest of the tree; list is for packaging metadata only.
        "applets",
        "libbb",
        "include",
        "Makefile",
    },
}
```

If `zig build` complains about fingerprint, run once and accept the fingerprint Zig prints into `build.zig.zon`.

- [ ] **Step 2: Write `scripts/zig-busybox-make.sh`**

```bash
#!/usr/bin/env bash
# Usage: zig-busybox-make.sh <zig-target-triple> <cflag-extra...>
# Env: ZIG (default: zig), DEFCONFIG (default: configs/lavaxx_defconfig), JOBS
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${ZIG:-zig}"
TARGET="${1:?zig target triple required}"
shift
DEFCONFIG="${DEFCONFIG:-configs/lavaxx_defconfig}"
JOBS="${JOBS:-$(command -v nproc >/dev/null && nproc || sysctl -n hw.ncpu)}"

if [[ ! -f .config ]] || [[ "${FORCE_DEFCONFIG:-}" == "1" ]]; then
  cp "$DEFCONFIG" .config
fi
make HOSTCC="$ZIG cc" oldconfig </dev/null

# Apply optional patches once (idempotent via .zig-patches-applied stamp)
if [[ -d patches/zig ]] && [[ ! -f .zig-patches-applied ]]; then
  for p in patches/zig/*.patch; do
    [[ -e "$p" ]] || continue
    patch -p1 --forward <"$p" || true
  done
  touch .zig-patches-applied
fi

EXTRA_CFLAGS=("$@")
CC_CMD=("$ZIG" cc -target "$TARGET" -static)
# BusyBox Make expects CC as a single string with spaces.
export SKIP_STRIP=y
make -j"$JOBS" \
  HOSTCC="$ZIG cc" \
  CC="${CC_CMD[*]} ${EXTRA_CFLAGS[*]}" \
  AR="$ZIG ar" \
  RANLIB="$ZIG ranlib" \
  busybox
```

Make the script executable: `chmod +x scripts/zig-busybox-make.sh`.

- [ ] **Step 3: Write `build.zig`**

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const defconfig = b.option([]const u8, "defconfig", "Path to BusyBox defconfig") orelse "configs/lavaxx_defconfig";

    const triple = target.result.zigTriple(b.allocator) catch @panic("OOM");
    const cflags: []const []const u8 = switch (optimize) {
        .Debug => &.{ "-O0", "-g" },
        .ReleaseSafe => &.{ "-O2", "-g" },
        .ReleaseFast => &.{ "-O2" },
        .ReleaseSmall => &.{ "-Os" },
    };

    const make_step = b.addSystemCommand(&.{ "bash", "scripts/zig-busybox-make.sh", triple });
    make_step.setEnvironmentVariable("DEFCONFIG", defconfig);
    make_step.setEnvironmentVariable("FORCE_DEFCONFIG", "1");
    for (cflags) |f| make_step.addArg(f);

    const install_busybox = b.addInstallBinFile(b.path("busybox"), "busybox");
    install_busybox.step.dependOn(&make_step.step);
    b.getInstallStep().dependOn(&install_busybox.step);
}
```

Adjust API names if Zig 0.17 differs (`zigTriple`, `addInstallBinFile`); match whatever `zig build` reports. The important contract: default install step produces `zig-out/bin/busybox` and depends on a successful Make.

- [ ] **Step 4: Build x86_64 musl and smoke-check**

Run:

```bash
rm -rf zig-out .zig-cache busybox busybox_unstripped*
FORCE_DEFCONFIG=1 zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl
file zig-out/bin/busybox
# Prefer: statically linked, x86-64
./zig-out/bin/busybox 2>&1 | head -5 || true
# If host is not linux/x86_64, skip native exec; still require `file` OK.
```

Expected: build succeeds; `file` shows ELF x86-64, statically linked (or “static-pie”).

If the build fails with clang/lld errors, do **not** paper over in this task — capture the error log for Task 4.

- [ ] **Step 5: Commit**

```bash
git add build.zig build.zig.zon scripts/zig-busybox-make.sh
git commit -m "$(cat <<'EOF'
feat: add zig build orchestration for static BusyBox

Drive upstream Make with zig cc so release triples share one entrypoint.
EOF
)"
```

---

### Task 4: Clang/lld patches only if x86_64 (or later triples) fail

**Files:**
- Create: `patches/zig/*.patch` (only if needed)
- Modify: `scripts/zig-busybox-make.sh` only if apply logic needs tightening
- Test: re-run the failing `zig build` until green

**Interfaces:**
- Consumes: failure logs from Task 3 / Task 5
- Produces: minimal patches; green `x86_64-linux-musl` build

- [ ] **Step 1: Classify the failure**

If Task 3 already passed, create `patches/zig/.gitkeep` only if the directory must exist empty, **or skip this task entirely** (no commit required).

If failed, map error → fix:

| Symptom | Fix direction |
|---------|----------------|
| unknown linker arg (gcc ld) | Patch `Makefile.flags` / scripts to drop the flag under clang |
| `CONFIG_TC` / kernel header errors | Ensure TC disabled in defconfig (Task 2); rebuild |
| SHA HW accel asm fail | Ensure HW accel off in defconfig |
| BB_GLOBAL_CONST / rodata crash risk | Upstream-known clang attribute patch |
| x86 pstm inline asm | Soft-fail to C implementation patch |

- [ ] **Step 2: Add a forward-applicable patch**

```bash
# example workflow after editing tree
git diff > patches/zig/0001-describe-fix.patch
git checkout -- .
```

Re-run:

```bash
rm -f .zig-patches-applied
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl
```

Expected: PASS.

- [ ] **Step 3: Commit only if patches exist**

```bash
git add patches/zig
git commit -m "$(cat <<'EOF'
fix: add zig/clang compatibility patches for BusyBox Make

Unblock static musl builds under zig cc without changing applet behavior.
EOF
)"
```

---

### Task 5: Verify aarch64 and armv7 musl builds + local packaging

**Files:**
- Modify: none unless defconfig/script needs a fix
- Test: three triples + tar naming matching the release workflow

**Interfaces:**
- Consumes: working `zig build` from Tasks 3–4
- Produces: three archives under `release-artifacts/` locally

- [ ] **Step 1: Build remaining triples**

```bash
mkdir -p release-artifacts
version="v0.0.0-dev"
for entry in \
  "x86_64-linux-musl:linux_amd64" \
  "aarch64-linux-musl:linux_arm64" \
  "arm-linux-musleabihf:linux_armv7"
do
  target="${entry%%:*}"; label="${entry##*:}"
  rm -rf zig-out .zig-cache busybox busybox_unstripped* .zig-patches-applied
  # Re-apply patches via script stamp clear; sources must stay patched or re-apply each time
  zig build -Doptimize=ReleaseSmall -Dtarget="${target}"
  test -x zig-out/bin/busybox
  file zig-out/bin/busybox
  tar -czf "release-artifacts/busybox_${version}_${label}.tar.gz" -C zig-out/bin busybox
done
(cd release-artifacts && shasum -a 256 *.tar.gz | tee checksums.txt)
ls -la release-artifacts
```

Expected: three tar.gz files + checksums; each `file` matches the arch; all static.

Note on patches stamp: if clearing the tree between builds loses applied patches, change the script to `git apply --check` / always `patch -p1 --forward` safely, or keep patches applied in the working tree for the session. Prefer making patch apply idempotent (`patch -p1 -N` / `--forward`) and **remove** the early-exit stamp for release loops, or reset stamp every build intentionally after `git checkout` of patched files. Document the chosen behavior in the script comment when fixing.

- [ ] **Step 2: Commit any script/defconfig fixes required for green triples**

```bash
git add scripts/zig-busybox-make.sh configs/lavaxx_defconfig patches/zig
git commit -m "$(cat <<'EOF'
fix: make all three musl release triples build cleanly

Align defconfig and zig make helper with aarch64/armv7 clang needs.
EOF
)"
```

(Skip commit if nothing changed.)

---

### Task 6: Add `.github/workflows/release-zig.yml`

**Files:**
- Create: `.github/workflows/release-zig.yml`
- Create: `README.lavaxx.md` (short Zig/release notes; leave upstream `README` alone)
- Test: workflow YAML validates structurally; optional `workflow_dispatch` after push

**Interfaces:**
- Consumes: Task 5 local packaging contract (`busybox_<ver>_<label>.tar.gz`)
- Produces: CI release job mirroring dropbear

- [ ] **Step 1: Write the workflow**

Adapt from `~/git/barry/dropbear/.github/workflows/release-zig.yml`:

```yaml
name: Release (zig build)

on:
  push:
    tags:
      - "zig/v*"
  workflow_dispatch:
    inputs:
      version:
        description: "Version to build (e.g. v1.39.0); release publish only on tags"
        required: false
        default: "v0.0.0-dev"

permissions:
  contents: write

jobs:
  build-and-release:
    name: Build all targets
    runs-on: [self-hosted, barrymini]
    timeout-minutes: 180
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Use preinstalled Zig
        shell: bash
        run: |
          set -euo pipefail
          for c in /opt/toolchains/zig/zig "$HOME/.local/zig/zig" "$(command -v zig || true)"; do
            if [[ -n "$c" && -x "$c" ]]; then
              echo "Using zig: $c ($("$c" version))"
              echo "$(dirname "$c")" >> "$GITHUB_PATH"
              exit 0
            fi
          done
          echo "Zig 0.17.0 not found. Install to /opt/toolchains/zig." >&2
          exit 1

      - name: Parse version and channel
        id: version
        shell: bash
        run: |
          if [[ "${GITHUB_REF}" == refs/tags/zig/* ]]; then
            version="${GITHUB_REF#refs/tags/zig/}"
          else
            version="${{ github.event.inputs.version }}"
          fi
          echo "version=${version}" >> "$GITHUB_OUTPUT"
          if [[ "$version" =~ -alpha ]]; then
            echo "channel=dev" >> "$GITHUB_OUTPUT"
          elif [[ "$version" =~ -beta ]]; then
            echo "channel=beta" >> "$GITHUB_OUTPUT"
          else
            echo "channel=prod" >> "$GITHUB_OUTPUT"
          fi

      - name: Build Linux targets
        shell: bash
        run: |
          set -euo pipefail
          channel="${{ steps.version.outputs.channel }}"
          version="${{ steps.version.outputs.version }}"
          if [[ "$channel" == "prod" ]]; then optimize="ReleaseSmall"; else optimize="ReleaseSafe"; fi
          mkdir -p release-artifacts
          targets=(
            "x86_64-linux-musl:linux_amd64"
            "aarch64-linux-musl:linux_arm64"
            "arm-linux-musleabihf:linux_armv7"
          )
          for entry in "${targets[@]}"; do
            target="${entry%%:*}"
            label="${entry##*:}"
            echo "::group::Build ${label} (${target})"
            rm -rf zig-out .zig-cache busybox busybox_unstripped* .zig-patches-applied
            zig build -Doptimize="${optimize}" -Dtarget="${target}"
            archive="busybox_${version}_${label}.tar.gz"
            tar -czf "release-artifacts/${archive}" -C zig-out/bin busybox
            echo "::endgroup::"
          done
          ls -la release-artifacts
          (cd release-artifacts && sha256sum *.tar.gz > checksums.txt && cat checksums.txt)

      - name: Publish GitHub Release
        if: >-
          startsWith(github.ref, 'refs/tags/zig/') ||
          (github.event_name == 'workflow_dispatch' && inputs.version != 'v0.0.0-dev')
        env:
          GH_TOKEN: ${{ secrets.RELEASER_TOKEN || secrets.GITHUB_TOKEN }}
        shell: bash
        run: |
          set -euo pipefail
          version="${{ steps.version.outputs.version }}"
          if [[ "${GITHUB_REF}" == refs/tags/zig/* ]]; then
            tag="${{ github.ref_name }}"
          else
            tag="zig/${version}"
          fi
          prerelease=()
          if [[ "${{ steps.version.outputs.channel }}" != "prod" ]]; then
            prerelease=(--prerelease)
          fi
          if gh release view "$tag" --repo "${{ github.repository }}" >/dev/null 2>&1; then
            gh release upload "$tag" release-artifacts/* \
              --repo "${{ github.repository }}" --clobber
          else
            gh release create "$tag" \
              --repo "${{ github.repository }}" \
              --title "busybox ${version}" \
              --generate-notes \
              --target "${{ github.sha }}" \
              "${prerelease[@]}" \
              release-artifacts/*
          fi
```

- [ ] **Step 2: Write `README.lavaxx.md`**

```markdown
# lavaxx BusyBox (Zig builds)

## Build

Requires Zig 0.17+ and GNU Make.

```sh
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl
# binary: zig-out/bin/busybox
```

Other release triples: `aarch64-linux-musl`, `arm-linux-musleabihf`.

Defconfig: `configs/lavaxx_defconfig` (override with `-Ddefconfig=`).

## Release

Push a tag `zig/v1.39.0` (use `-alpha` / `-beta` for pre-releases) or run the
**Release (zig build)** workflow. Artifacts: `busybox_<ver>_linux_{amd64,arm64,armv7}.tar.gz`.
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release-zig.yml README.lavaxx.md
git commit -m "$(cat <<'EOF'
ci: add zig musl release workflow for BusyBox

Publish linux amd64/arm64/armv7 static archives on zig/v* tags.
EOF
)"
```

---

### Task 7: Branch push readiness (no force)

**Files:** none (git remotes only)

**Interfaces:**
- Consumes: green local builds from Task 5; commits from Tasks 1–6
- Produces: remote branch ready for PR / tag

- [ ] **Step 1: Show status**

```bash
git status -sb
git log --oneline origin/master..HEAD
```

Expected: clean tree; commits only for zig/release work.

- [ ] **Step 2: Push feature branch (when user asks)**

```bash
git push -u origin HEAD
```

Do **not** create `zig/v*` tags or GitHub releases unless the user explicitly requests them after the PR/merge preference is clear.

---

## Plan self-review

1. **Spec coverage:** lean defconfig, `build.zig`+Make+`zig cc`, three musl triples, `release-zig.yml`, archive naming, optimize channels, no Windows — all have tasks. Optional UPX excluded.
2. **Placeholders:** none intentional; patch contents are failure-driven by design (Task 4 may no-op).
3. **Consistency:** artifact labels and triples match across Task 5 and Task 6; install path always `zig-out/bin/busybox`.
