const Photon = @import("photon.zig").Photon;
const Grid = @import("photon_grid.zig").Grid;
const Scene = @import("../../../../scene/scene.zig").Scene;
const Intersection = @import("../../../../scene/shape/intersection.zig").Intersection;
const MaterialSample = @import("../../../../scene/material/sample.zig").Sample;
const Sampler = @import("../../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Map = struct {
    photons: []Photon = &.{},

    grid: Grid = .{},

    aabbs: []AABB = &.{},

    num_paths: u64 = 0,

    reduced_num: u32 = undefined,

    const Self = @This();

    pub fn configure(self: *Self, alloc: Allocator, num_workers: u32, num_photons: u32, search_radius: f32) !void {
        self.photons = try alloc.realloc(self.photons, num_photons);
        self.aabbs = try alloc.realloc(self.aabbs, num_workers);
        self.grid.configure(search_radius, 1.5);
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.grid.deinit(alloc);
        alloc.free(self.aabbs);
        alloc.free(self.photons);
    }

    pub fn start(self: *Self) void {
        self.reduced_num = 0;
    }

    pub fn insert(self: *Self, photon: Photon, index: usize) void {
        self.photons[index] = photon;
    }

    pub fn compileIteration(self: *Self, alloc: Allocator, num_photons: u32, num_paths: u64, threads: *Threads) !u32 {
        const aabb = self.calculateAabb(num_photons, threads);

        try self.grid.resize(alloc, aabb);

        self.num_paths = num_paths;

        self.grid.initCells(self.photons[0..num_photons]);

        const total_num_photons = @as(u32, @intCast(self.photons.len));

        const reduced_num = if (num_photons == total_num_photons)
            self.grid.reduce(self.photons, threads)
        else
            num_photons;

        const percentage_left = @as(f32, @floatFromInt(reduced_num)) / @as(f32, @floatFromInt(total_num_photons));

        std.debug.print(
            "{} left of {} ({}%)\n",
            .{ reduced_num, total_num_photons, @as(u32, @intFromFloat(100.0 * percentage_left)) },
        );

        self.reduced_num = reduced_num;

        return reduced_num;
    }

    pub fn compileFinalize(self: *Self) void {
        //   self.grid.initCells(self.photons[0..self.reduced_num]);
        self.grid.setNumPaths(self.num_paths);
    }

    pub fn li(
        self: *const Self,
        isec: *const Intersection,
        sample: *const MaterialSample,
        sampler: *Sampler,
        scene: *const Scene,
    ) Vec4f {
        if (0 == self.num_paths) {
            return @splat(0.0);
        }

        return self.grid.li2(isec, sample, sampler, scene);
    }

    fn calculateAabb(self: *Self, num_photons: u32, threads: *Threads) AABB {
        const num = threads.runRange(self, calculateAabbRange, 0, num_photons, 0);

        var aabb = math.aabb.Empty;
        for (self.aabbs[0..num]) |b| {
            aabb.mergeAssign(b);
        }

        aabb.expand(0.0001);

        return aabb;
    }

    fn calculateAabbRange(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        const self = @as(*Self, @ptrCast(@alignCast(context)));

        var aabb = math.aabb.Empty;
        for (self.photons[begin..end]) |p| {
            aabb.insert(p.p);
        }

        self.aabbs[id] = aabb;
    }
};
