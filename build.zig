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

    const zyg = b.addExecutable("zyg", "src/cli/main.zig");

    zyg.addIncludeDir("thirdparty/include");

    const cflags = [_][]const u8{
        "-std=c99",
        "-Wall",
        "-fno-sanitize=undefined",
    };
    zyg.addCSourceFile("thirdparty/include/miniz/miniz.c", &cflags);
    zyg.addCSourceFile("thirdparty/include/arpraguesky/ArPragueSkyModelGround.c", &cflags);

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

    zyg.addPackage(base);
    zyg.addPackage(core);

    zyg.setTarget(target);
    zyg.setBuildMode(mode);
    zyg.linkLibC();

    // zyg.sanitize_thread = true;
    // zyg.strip = true;

    zyg.install();

    const run_cmd = zyg.run();
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
            "takes/embergen.take",
            "-t",
            "-4",
            //"--no-tex",
            //"--no-tex-dwim",
            //"--debug-mat",
            "-f",
            "64",
            // "-n",
            // "4",
        });
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
