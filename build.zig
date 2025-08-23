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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const capi = b.addLibrary(.{
        .name = "zyg",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/capi/capi.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const it = b.addExecutable(.{
        .name = "it",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/it/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const sow = b.addExecutable(.{
        .name = "sow",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sow/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
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
        sow.addCSourceFile(.{ .file = b.path(source), .flags = &cflags });
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

    const util = b.createModule(.{
        .root_source_file = b.path("src/util/util.zig"),
        .imports = &.{
            .{ .name = "base", .module = base },
            .{ .name = "core", .module = core },
        },
    });

    // CLI/zyg
    cli.root_module.addImport("base", base);
    cli.root_module.addImport("core", core);
    cli.root_module.addImport("util", util);

    cli.linkLibC();
    cli.root_module.strip = true;
    b.installArtifact(cli);

    // C-API
    capi.root_module.addImport("base", base);
    capi.root_module.addImport("core", core);

    capi.linkLibC();
    capi.root_module.strip = true;
    b.installArtifact(capi);

    // it
    it.root_module.addImport("base", base);
    it.root_module.addImport("core", core);

    it.linkLibC();
    it.root_module.strip = true;
    b.installArtifact(it);

    // sow
    sow.root_module.addImport("base", base);
    sow.root_module.addImport("core", core);
    sow.root_module.addImport("util", util);

    sow.root_module.strip = true;
    b.installArtifact(sow);

    // run zyg
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
            //"takes/cornell_nd.take",
            //"takes/curve_test.take",
            //"takes/imrod.take",
            //"takes/instancer.take",
            //"takes/model_test.take",
            //"takes/nme.take",
            //"takes/furnace_test.take",
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
            //"takes/nested_dielectrics.take",
            //"takes/intel_sponza.take",
            //"takes/intel_sponza_night.take",
            //"takes/sss.take",
            //"scenes/island/shot_cam.take",
            //"takes/shadow_catcher.take",
            //"scenes/bamboo/bamboo.take",
            //"models/plants/bamboo/bamboo_leaves.take",
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

    // run it
    // const run_exe = b.addRunArtifact(it);
    // run_exe.step.dependOn(b.getInstallStep());
    // run_exe.setCwd(b.path("system"));

    // const run_step = b.step("run", "Run the application");
    // run_step.dependOn(&run_exe.step);

    // if (b.args) |args| {
    //     run_exe.addArgs(args);
    // } else {
    //     run_exe.addArgs(&[_][]const u8{
    //         "-i",
    //         "image_00_000000_indirect.exr",
    //         "image_00_000000_n.exr",
    //         "image_00_000000_albedo.exr",
    //         "image_00_000000_depth.exr",
    //         "--denoise",
    //         "2.0",
    //         // "leaves_1024.png",
    //         // "--down-sample",
    //         "-t",
    //         "-1",
    //     });
    // }

    // run sow
    // const run_exe = b.addRunArtifact(sow);
    // run_exe.step.dependOn(b.getInstallStep());
    // run_exe.setCwd(b.path("system"));

    // const run_step = b.step("run", "Run the application");
    // run_step.dependOn(&run_exe.step);

    // if (b.args) |args| {
    //     run_exe.addArgs(args);
    // } else {
    //     run_exe.addArgs(&[_][]const u8{
    //         "-i",
    //         // "sow/bamboo_forest.json",
    //         // "sow/bamboo_leaves.json",
    //         //"sow/test.json",
    //         "sow/particle_test.json",
    //         "-o",
    //         //  "../data/models/plants/bamboo/bamboo.instancer",
    //         // "../data/models/plants/bamboo/bamboo_leaves.instancer",
    //         //"../data/models/test.instancer",
    //         //"../data/models/points/sparks.json",
    //         "../data/models/points/cornell_rain.json",
    //         "-t",
    //         "-1",
    //     });
    // }
}
