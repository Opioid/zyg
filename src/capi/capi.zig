const core = @import("core");
const log = core.log;
const rendering = core.rendering;
const resource = core.resource;
const scn = core.scn;
const tk = core.tk;
const Progressor = core.progress.Progressor;

const base = @import("base");
const math = base.math;
const encoding = base.encoding;
const spectrum = base.spectrum;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Engine = struct {
    alloc: Allocator,

    threads: Threads = .{},

    resources: resource.Manager = undefined,
    scene_loader: scn.Loader = undefined,
    scene: scn.Scene = undefined,

    take: tk.Take = undefined,
    driver: rendering.Driver = undefined,

    frame: u32 = 0,
    iteration: u32 = 0,

    progress: Progressor = .{ .Null = {} },
};

var engine: ?Engine = null;

export fn su_init() i32 {
    if (engine) |_| {
        return -1;
    }

    const alloc = std.heap.c_allocator;

    engine = .{ .alloc = alloc };

    const num_workers = Threads.availableCores(0);
    engine.?.threads.configure(alloc, num_workers) catch {
        //_ = err;
        engine = null;
        return -1;
    };

    engine.?.resources = resource.Manager.init(alloc, &engine.?.threads) catch {
        engine = null;
        return -1;
    };

    const resources = &engine.?.resources;

    engine.?.scene_loader = scn.Loader.init(alloc, resources, scn.mat.Provider.createFallbackMaterial());

    engine.?.scene = scn.Scene.init(
        alloc,
        &resources.images.resources,
        &resources.materials.resources,
        &resources.shapes.resources,
        engine.?.scene_loader.null_shape,
    ) catch {
        engine = null;
        return -1;
    };

    engine.?.take = tk.Take.init(alloc) catch {
        engine = null;
        return -1;
    };

    engine.?.driver = rendering.Driver.init(alloc, &engine.?.threads, engine.?.progress) catch {
        engine = null;
        return -1;
    };

    return 0;
}

export fn su_release() i32 {
    if (engine) |*e| {
        e.driver.deinit(e.alloc);
        e.take.deinit(e.alloc);
        e.scene.deinit(e.alloc);
        e.scene_loader.deinit(e.alloc);
        e.resources.deinit(e.alloc);
        e.threads.deinit(e.alloc);
        return 0;
    }

    return -1;
}

export fn su_mount(folder: [*:0]const u8) i32 {
    if (engine) |*e| {
        e.resources.fs.pushMount(e.alloc, folder[0..std.mem.len(folder)]) catch {
            return -1;
        };

        return 0;
    }

    return -1;
}

export fn su_load_take(string: [*:0]const u8) i32 {
    if (engine) |*e| {
        var stream = e.resources.fs.readStream(e.alloc, string[0..std.mem.len(string)]) catch {
            //  log.err("Open stream \"{s}\": {}", .{ string, err });
            return -1;
        };

        var take = tk.load(e.alloc, stream, &e.scene, &e.resources) catch {
            //    log.err("Loading take: {}", .{err});
            return -1;
        };

        e.scene_loader.load(e.alloc, take.scene_filename, take, &e.scene) catch {
            // log.err("Loading scene: {}", .{err});
            return -1;
        };

        e.take = take;

        return 0;
    }

    return -1;
}

export fn su_camera_sensor_dimensions(dimensions: [*]i32) i32 {
    if (engine) |*e| {
        const d = e.take.view.camera.sensorDimensions();
        dimensions[0] = d[0];
        dimensions[1] = d[1];
        return 0;
    }

    return -1;
}

export fn su_render_frame(frame: u32) i32 {
    if (engine) |*e| {
        e.threads.waitAsync();

        e.driver.configure(e.alloc, &e.take.view, &e.scene) catch {
            return -1;
        };

        e.frame = frame;

        e.driver.render(e.alloc, frame) catch {
            return -1;
        };

        return 0;
    }

    return -1;
}

export fn su_export_frame() i32 {
    if (engine) |*e| {
        e.driver.exportFrame(e.alloc, e.frame, e.take.exporters.items) catch {
            return -1;
        };

        return 0;
    }

    return -1;
}

export fn su_start_frame(frame: u32) i32 {
    if (engine) |*e| {
        e.threads.waitAsync();

        e.driver.configure(e.alloc, &e.take.view, &e.scene) catch {
            return -1;
        };

        e.frame = frame;
        e.iteration = 0;
        e.driver.startFrame(e.alloc, frame) catch {
            return -1;
        };

        return 0;
    }

    return -1;
}

export fn su_render_iteration() i32 {
    if (engine) |*e| {
        e.driver.renderIteration(e.iteration);
        e.iteration += 1;

        return 0;
    }

    return -1;
}

export fn su_resolve_frame() i32 {
    if (engine) |*e| {
        e.driver.resolve();
        return 0;
    }

    return -1;
}

export fn su_copy_framebuffer(
    format: u32,
    width: u32,
    height: u32,
    num_channels: u32,
    destination: [*]u8,
) i32 {
    if (engine) |*e| {
        _ = format;
        _ = num_channels;

        const buffer = e.driver.target;

        const d = buffer.description.dimensions;

        const used_width = @minimum(width, @intCast(u32, d.v[0]));
        const used_height = @minimum(height, @intCast(u32, d.v[1]));

        // var target = std.mem.asSlice()

        var y: u32 = 0;
        while (y < used_height) : (y += 1) {
            var o: u32 = y * width * 3;
            var x: u32 = 0;
            while (x < used_width) : (x += 1) {
                const color = buffer.get2D(@intCast(i32, x), @intCast(i32, y));

                destination[o + 0] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(color.v[0]));
                destination[o + 1] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(color.v[1]));
                destination[o + 2] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(color.v[2]));

                o += 3;
            }
        }

        return 0;
    }

    return -1;
}

export fn su_register_log(post: ?*log.CFunc.Func) i32 {
    if (post) |p| {
        log.log = .{ .CFunc = .{ .func = p } };
        return 0;
    }

    return -1;
}

export fn su_register_progress() i32 {
    return -1;
}
