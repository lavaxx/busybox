# lavaxx BusyBox (Zig builds)

## Build

Requires Zig 0.17+ and GNU Make.

```sh
zig build -Doptimize=small -Dtarget=x86_64-linux-musl
# binary: zig-out/bin/busybox (stripped)
```

Zig 0.17 CLI values: `Debug` / `safe` / `fast` / `small` (same as dropbear).

Other release triples: `aarch64-linux-musl`, `arm-linux-musleabihf`.

Defconfig: `configs/lavaxx_defconfig` — NVR/camera `--list` allowlist with
lean `FEATURE_*` (ash only, no hush), stripped musl ELF **≤800KB** on the
three release arches; **`wget`** kept without TLS/HTTPS. Override with
`-Ddefconfig=`.

## Release

All release channels (including `-alpha` / `-beta`) build with
`-Doptimize=small` and strip the ELF. The GitHub workflow builds the three
musl targets **in parallel** (matrix jobs). Master runs **Cache BusyBox
objects** to store `.build/<label>` (incl. stripped `busybox`). Release tags
restore that cache; an exact key hit reuses the binary (Make cannot
incrementally reuse `zig cc` objects after checkout). Push a tag
`zig/v1.39.0` or run the **Release (zig build)** workflow on `ubuntu-latest`
(Zig 0.17 via `mlugg/setup-zig`). Artifacts:
`busybox_<ver>_linux_{amd64,arm64,armv7}.tar.gz`.
