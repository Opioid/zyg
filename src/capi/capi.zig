const core = @import("core");
const log = core.log;
const rendering = core.rendering;
const resource = core.resource;
const scn = core.scn;
const tk = core.tk;

const base = @import("base");
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

    engine.?.driver = rendering.Driver.init(alloc, &engine.?.threads) catch {
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
