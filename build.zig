const std = @import("std");

// BusyBox build using `zig build` (Zig 0.17).
//
// Orchestrates upstream GNU Make + Kconfig with `zig cc` as the cross
// compiler (and native HOSTCC). See docs/superpowers/specs/2026-11-10-zig-build-release-design.md.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const defconfig_opt = b.option(
        []const u8,
        "defconfig",
        "Path to BusyBox defconfig",
    );
    const os_tag = target.result.os.tag;
    const defconfig = defconfig_opt orelse if (os_tag == .macos or os_tag == .ios)
        "configs/lavaxx_macos_defconfig"
    else
        "configs/lavaxx_defconfig";

    // Prefer a compact triple for `zig cc -target` (no OS version range).
    const triple = std.fmt.allocPrint(
        b.allocator,
        "{s}-{s}-{s}",
        .{
            @tagName(target.result.cpu.arch),
            @tagName(os_tag),
            @tagName(target.result.abi),
        },
    ) catch @panic("OOM");
    const cflags: []const []const u8 = switch (optimize) {
        .Debug => &.{ "-O0", "-g" },
        .ReleaseSafe => &.{ "-O2", "-g" },
        .ReleaseFast => &.{ "-O2" },
        .ReleaseSmall => &.{ "-Os" },
    };

    const make_step = b.addSystemCommand(&.{
        "bash",
        "scripts/zig-busybox-make.sh",
        triple,
    });
    make_step.setEnvironmentVariable("DEFCONFIG", defconfig);
    make_step.setEnvironmentVariable("FORCE_DEFCONFIG", "1");
    for (cflags) |f| make_step.addArg(f);
    // Rebuild when the helper or defconfig changes.
    make_step.addFileInput(b.path("scripts/zig-busybox-make.sh"));
    make_step.addFileInput(b.path(defconfig));

    const install_busybox = b.addInstallBinFile(b.path("busybox"), "busybox");
    install_busybox.step.dependOn(&make_step.step);
    b.getInstallStep().dependOn(&install_busybox.step);
}
