const View = @import("../take/take.zig").View;
const Scene = @import("../scene/scene.zig").Scene;
const Worker = @import("worker.zig").Worker;
const TileQueue = @import("tile_queue.zig").TileQueue;

const img = @import("../image/image.zig");

usingnamespace @import("base").math;

const Allocator = @import("std").mem.Allocator;

pub const Driver = struct {
    view: *View = undefined,
    scene: *Scene = undefined,

    workers: []Worker = &.{},

    tile_queue: TileQueue = undefined,

    target: img.Float4 = .{},

    pub fn init(alloc: *Allocator) !Driver {
        return Driver{
            .workers = try alloc.alloc(Worker, 1),
        };
    }

    pub fn deinit(self: *Driver, alloc: *Allocator) void {
        self.target.deinit(alloc);
        alloc.free(self.workers);
    }

    pub fn configure(self: *Driver, alloc: *Allocator, view: *View, scene: *Scene) !void {
        self.view = view;
        self.scene = scene;

        const camera = &self.view.camera;

        const dim = camera.sensorDimensions();

        try camera.sensor.resize(alloc, dim);

        for (self.workers) |*w| {
            w.configure(view, scene);
        }

        self.tile_queue.configure(camera.crop, 32, 0);

        try self.target.resize(alloc, img.Description.init2D(dim));
    }

    pub fn render(self: *Driver) void {
        var camera = &self.view.camera;

        const camera_pos = self.scene.propWorldPosition(camera.entity);

        self.scene.compile(camera_pos);

        camera.update();

        camera.sensor.clear(0.0);

        self.tile_queue.restart();

        while (self.tile_queue.pop()) |tile| {
            self.workers[0].render(tile);
        }
    }

    pub fn exportFrame(self: *Driver) void {
        self.view.camera.sensor.resolve(&self.target);
    }
};
