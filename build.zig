const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const cli = b.addExecutable(.{
        .name = "zyg",
        .root_source_file = .{ .path = "src/cli/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const capi = b.addSharedLibrary(.{
        .name = "zyg",
        .root_source_file = .{ .path = "src/capi/capi.zig" },
        .target = target,
        .optimize = optimize,
    });

    const it = b.addExecutable(.{
        .name = "it",
        .root_source_file = .{ .path = "src/it/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    cli.addIncludePath("thirdparty/include");
    cli.addIncludePath("src/cli");
    capi.addIncludePath("thirdparty/include");
    it.addIncludePath("thirdparty/include");

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

    cli.addCSourceFile("src/cli/any_key.c", &cflags);

    it.addCSourceFile(csources[0], &cflags);

    const base = b.createModule(.{
        .source_file = .{ .path = "src/base/base.zig" },
    });

    const core = b.createModule(.{
        .source_file = .{ .path = "src/core/core.zig" },
        .dependencies = &.{.{ .name = "base", .module = base }},
    });

    cli.addModule("base", base);
    cli.addModule("core", core);

    cli.linkLibC();
    // cli.sanitize_thread = true;
    cli.strip = true;
    cli.install();

    capi.addModule("base", base);
    capi.addModule("core", core);

    capi.linkLibC();
    capi.strip = true;
    capi.install();

    it.addModule("base", base);
    it.addModule("core", core);

    it.linkLibC();
    // it.sanitize_thread = true;
    it.strip = true;
    it.install();

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
            "takes/cornell.take",
            //"takes/imrod.take",
            //"takes/model_test.take",
            //"takes/animation_test.take",
            //"takes/material_test.take",
            //"takes/whirligig.take",
            //"takes/candle.take",
            //"takes/disney_cloud.take",
            //"takes/rene.take",
            //"takes/head.take",
            //"takes/flakes.take",
            //"takes/embergen.take",
            //"takes/volume.take",
            //"takes/intel_sponza.take",
            //"scenes/island/shot_cam.take",
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

    // const run_cmd = it.run();
    // run_cmd.step.dependOn(b.getInstallStep());
    // run_cmd.cwd = "/home/beni/workspace/sprout/system";
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // } else {
    //     run_cmd.addArgs(&[_][]const u8{
    //         //"-d",
    //         "-i",
    //         //"image_00000000.exr",
    //         //"image_00000001.exr",
    //         //"image_00000003.exr",
    //         //"san_miguel.exr",
    //         //"Round.IES",
    //         "ScatterLight.IES",
    //         "-t",
    //         "-4",
    //         //"--tone",
    //         "-e",
    //         "0.0",
    //         "-f",
    //         "png",
    //     });
    // }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
