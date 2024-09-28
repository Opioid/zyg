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
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const capi = b.addSharedLibrary(.{
        .name = "zyg",
        .root_source_file = b.path("src/capi/capi.zig"),
        .target = target,
        .optimize = optimize,
    });

    const it = b.addExecutable(.{
        .name = "it",
        .root_source_file = b.path("src/it/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    cli.addIncludePath(b.path("thirdparty/include"));
    cli.addIncludePath(b.path("src/cli"));
    capi.addIncludePath(b.path("thirdparty/include"));
    it.addIncludePath(b.path("thirdparty/include"));

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
        cli.addCSourceFile(.{ .file = b.path(source), .flags = &cflags });
        capi.addCSourceFile(.{ .file = b.path(source), .flags = &cflags });
    }

    cli.addCSourceFile(.{ .file = b.path("src/cli/any_key.c"), .flags = &cflags });

    it.addCSourceFile(.{ .file = b.path(csources[0]), .flags = &cflags });

    const base = b.createModule(.{
        .root_source_file = b.path("src/base/base.zig"),
    });

    const core = b.createModule(.{
        .root_source_file = b.path("src/core/core.zig"),
        .imports = &.{.{ .name = "base", .module = base }},
    });

    core.addIncludePath(b.path("thirdparty/include"));

    cli.root_module.addImport("base", base);
    cli.root_module.addImport("core", core);

    cli.linkLibC();
    // cli.sanitize_thread = true;
    cli.root_module.strip = true;
    b.installArtifact(cli);

    capi.root_module.addImport("base", base);
    capi.root_module.addImport("core", core);

    capi.linkLibC();
    capi.root_module.strip = true;
    b.installArtifact(capi);

    it.root_module.addImport("base", base);
    it.root_module.addImport("core", core);

    it.linkLibC();
    // it.sanitize_thread = true;
    it.root_module.strip = true;
    b.installArtifact(it);

    const run_exe = b.addRunArtifact(cli);
    run_exe.step.dependOn(b.getInstallStep());
    run_exe.setCwd(b.path("system"));

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);

    if (b.args) |args| {
        run_exe.addArgs(args);
    } else {
        run_exe.addArgs(&[_][]const u8{
            "-i",
            //"takes/bistro_day.take",
            //"takes/bistro_night.take",
            //"takes/san_miguel.take",
            "takes/cornell.take",
            //"takes/curve_test.take",
            //"takes/imrod.take",
            //"takes/model_test.take",
            //"takes/animation_test.take",
            //"takes/material_test.take",
            //"takes/whirligig.take",
            //"takes/candle.take",
            //"takes/sss.take",
            //"takes/disney_cloud.take",
            //"takes/sky.take",
            //"takes/rene.take",
            //"takes/head.take",
            //"takes/flakes.take",
            //"takes/embergen.take",
            //"takes/volume.take",
            //"takes/intel_sponza.take",
            //"takes/sss.take",
            //"scenes/island/shot_cam.take",
            "-t",
            "-1",
            //"--no-tex",
            //"--no-tex-dwim",
            //"--debug-mat",
            "-f",
            "0",
            "-n",
            "1",
        });
    }

    // // const run_cmd = b.addRunArtifact(it);
    // // run_cmd.step.dependOn(b.getInstallStep());
    // // run_cmd.cwd = "/home/beni/workspace/sprout/system";
    // // if (b.args) |args| {
    // //     run_cmd.addArgs(args);
    // // } else {
    // //     run_cmd.addArgs(&[_][]const u8{
    // //         //"-d",
    // //         "-i",
    // //         //"image_00000000.exr",
    // //         //"image_00000001.exr",
    // //         //"image_00000064.exr",
    // //         //"san_miguel.exr",
    // //         "intel_sponza_day.exr",
    // //         //"Round.IES",
    // //         //"ScatterLight.IES",
    // //         "-t",
    // //         "-4",
    // //         "--tone",
    // //         "agx",
    // //         "-e",
    // //         "-1.0",
    // //         "-f",
    // //         "png",
    // //     });
    // // }

    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);
}
