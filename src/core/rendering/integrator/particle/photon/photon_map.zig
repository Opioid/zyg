const Photon = @import("photon.zig").Photon;
const Grid = @import("photon_grid.zig").Grid;
const Worker = @import("../../../worker.zig").Worker;
const Intersection = @import("../../../../scene/prop/intersection.zig").Intersection;
const MaterialSample = @import("../../../../scene/material/sample.zig").Sample;

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

        const total_num_photons = @intCast(u32, self.photons.len);

        const reduced_num = if (num_photons == total_num_photons)
            self.grid.reduce(self.photons, threads)
        else
            num_photons;

        const percentage_left = @intToFloat(f32, reduced_num) / @intToFloat(f32, total_num_photons);

        std.debug.print(
            "{} left of {} ({}%)\n",
            .{ reduced_num, total_num_photons, @floatToInt(u32, 100.0 * percentage_left) },
        );

        self.reduced_num = reduced_num;

        return reduced_num;
    }

    pub fn compileFinalize(self: *Self) void {
        //   self.grid.initCells(self.photons[0..self.reduced_num]);
        self.grid.setNumPaths(self.num_paths);
    }

    pub fn li(self: Self, isec: Intersection, sample: MaterialSample, worker: Worker) Vec4f {
        if (0 == self.num_paths) {
            return @splat(4, @as(f32, 0.0));
        }

        return self.grid.li2(isec, sample, worker);
    }

    fn calculateAabb(self: *Self, num_photons: u32, threads: *Threads) AABB {
        const num = threads.runRange(self, calculateAabbRange, 0, num_photons, 0);

        var aabb = math.aabb.empty;
        for (self.aabbs[0..num]) |b| {
            aabb.mergeAssign(b);
        }

        aabb.add(0.0001);

        return aabb;
    }

    fn calculateAabbRange(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        const self = @intToPtr(*Self, context);

        var aabb = math.aabb.empty;
        for (self.photons[begin..end]) |p| {
            aabb.insert(p.p);
        }

        self.aabbs[id] = aabb;
    }
};
