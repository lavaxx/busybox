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
**Release (zig build)** workflow. Artifacts:
`busybox_<ver>_linux_{amd64,arm64,armv7}.tar.gz`.
