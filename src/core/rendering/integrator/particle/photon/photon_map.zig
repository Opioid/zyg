const Photon = @import("photon.zig").Photon;
const Worker = @import("../../../worker.zig").Worker;
const Intersection = @import("../../../../scene/prop/intersection.zig").Intersection;
const MaterialSample = @import("../../../../scene/material/sample.zig").Sample;
const mat = @import("../../../../scene/material/sample_helper.zig");

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Map = struct {
    photons: []Photon = &.{},

    num_paths: u64 = 0,

    search_radius: f32 = 0.01,
    surface_normalization: f32 = undefined,

    const Self = @This();

    pub fn configure(self: *Self, alloc: Allocator, num_photons: u32, search_radius: f32) !void {
        self.photons = try alloc.realloc(self.photons, num_photons);
        self.search_radius = search_radius;
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.photons);
    }

    pub fn start(self: *Self) void {
        _ = self;
    }

    pub fn insert(self: *Self, photon: Photon, index: usize) void {
        self.photons[index] = photon;
    }

    pub fn compileIteration(self: *Self, num_photons: u32, num_paths: u64, threads: *Threads) u32 {
        _ = num_photons;
        self.num_paths = num_paths;
        _ = threads;

        return 0;
    }

    pub fn compileFinalize(self: *Self) void {
        _ = self;

        self.setNumPaths(self.num_paths);
    }

    pub fn setNumPaths(self: *Self, num_paths: u64) void {
        self.num_paths = num_paths;

        const search_radius = self.search_radius;
        const radius2 = search_radius * search_radius;

        // conely
        // self.surface_normalization = 1.0 / (((1.0 / 2.0) * std.math.pi) * @intToFloat(f32, num_paths) * radius2);

        // cone
        self.surface_normalization = 1.0 / (((1.0 / 3.0) * std.math.pi) * @intToFloat(f32, num_paths) * radius2);
    }

    pub fn li(self: Self, isec: Intersection, sample: MaterialSample, worker: Worker) Vec4f {
        _ = worker;

        var result = @splat(4, @as(f32, 0.0));

        const position = isec.geo.p;

        const search_radius = self.search_radius;
        const radius2 = search_radius * search_radius;
        const inv_radius2 = 1.0 / radius2;

        for (self.photons) |p| {
            const distance2 = math.squaredDistance3(p.p, position);
            if (distance2 < radius2) {
                if (math.dot3(sample.super().interpolatedNormal(), p.wi) > 0.0) {
                    const k = coneFilter(distance2, inv_radius2);

                    const n_dot_wi = mat.clampDot(sample.super().shadingNormal(), p.wi);

                    const bxdf = sample.evaluate(p.wi);

                    result += @splat(4, k / n_dot_wi) * Vec4f{ p.alpha[0], p.alpha[1], p.alpha[2] } * bxdf.reflection;
                }
            }
        }

        return result * @splat(4, self.surface_normalization);
    }

    fn coneFilter(squared_distance: f32, inv_squared_radius: f32) f32 {
        const s = 1.0 - squared_distance * inv_squared_radius;
        return s * s;
    }

    fn conelyFilter(squared_distance: f32, inv_squared_radius: f32) f32 {
        return 1.0 - squared_distance * inv_squared_radius;
    }
};
