const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // const base = b.addStaticLibrary("base", "src/base/index.zig");
    // base.setTarget(target);
    // base.setBuildMode(mode);

    const cli = b.addExecutable("zyg", "src/cli/main.zig");
    const capi = b.addSharedLibrary("zyg", "src/capi/capi.zig", .{ .unversioned = {} });

    cli.addIncludeDir("thirdparty/include");
    capi.addIncludeDir("thirdparty/include");

    const cflags = [_][]const u8{
        "-std=c99",
        "-Wall",
        "-fno-sanitize=undefined",
    };

    const csources = [_][]const u8{
        "thirdparty/include/miniz/miniz.c",
        "thirdparty/include/arpraguesky/ArPragueSkyModelGround.c",
    };

    for (csources) |source| {
        cli.addCSourceFile(source, &cflags);
        capi.addCSourceFile(source, &cflags);
    }

    const base = std.build.Pkg{
        .name = "base",
        .path = .{ .path = "src/base/base.zig" },
    };

    const core = std.build.Pkg{
        .name = "core",
        .path = .{ .path = "src/core/core.zig" },
        .dependencies = &[_]std.build.Pkg{
            base,
        },
    };

    cli.addPackage(base);
    cli.addPackage(core);

    cli.setTarget(target);
    cli.setBuildMode(mode);
    cli.linkLibC();

    // cli.sanitize_thread = true;
    cli.strip = true;

    cli.install();

    capi.addPackage(base);
    capi.addPackage(core);

    capi.setTarget(target);
    capi.setBuildMode(mode);
    capi.linkLibC();

    capi.strip = true;

    capi.install();

    const run_cmd = cli.run();
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.cwd = "/home/beni/workspace/sprout/system";
    if (b.args) |args| {
        run_cmd.addArgs(args);
    } else {
        run_cmd.addArgs(&[_][]const u8{
            "-i",
            //"takes/bistro_day.take",
            //"takes/bistro_night.take",
            //"takes/san_miguel.take",
            //"takes/cornell.take",
            //"takes/imrod.take",
            //"takes/model_test.take",
            //"takes/material_test.take",
            //"takes/whirligig.take",
            //"takes/candle.take",
            //"takes/disney_cloud.take",
            //"takes/sky.take",
            "takes/rene.take",
            //"takes/embergen.take",
            "-t",
            "-4",
            //"--no-tex",
            //"--no-tex-dwim",
            //"--debug-mat",
            "-f",
            "0",
            "-n",
            "1",
        });
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
