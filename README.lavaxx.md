# lavaxx BusyBox (Zig builds)

## Build

Requires Zig 0.17+ and GNU Make.

```sh
zig build -Doptimize=small -Dtarget=x86_64-linux-musl
# binary: zig-out/bin/busybox (stripped)
```

Zig 0.17 CLI values: `Debug` / `safe` / `fast` / `small` (same as dropbear).

Other release triples: `aarch64-linux-musl`, `arm-linux-musleabihf`.

Defconfig: `configs/lavaxx_defconfig` — applet set aligned with a typical
camera/appliance BusyBox (ash+hush, networking, modules, …); **no** BusyBox
TLS/`wget` HTTPS. Override with `-Ddefconfig=`.

## Release

All release channels (including `-alpha` / `-beta`) build with
`-Doptimize=small` and strip the ELF. The GitHub workflow builds the three
musl targets **in parallel** (matrix jobs). Object trees (`.build/<label>`)
are warmed on `master` by **Cache BusyBox objects**, then restored on release
tags (GHA tag caches are not shared across tags). Push a tag `zig/v1.39.0`
or run the **Release (zig build)** workflow on `ubuntu-latest` (Zig 0.17 via
`mlugg/setup-zig`). Artifacts:
`busybox_<ver>_linux_{amd64,arm64,armv7}.tar.gz`.
