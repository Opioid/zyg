const aoc = @import("ao.zig");
pub const AO = aoc.AO;
pub const AO_factory = aoc.Factory;

const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;

const math = @import("base").math;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;
const std = @import("std");

pub const Integrator = union(enum) {
    AO: AO,

    pub fn deinit(self: *Integrator, alloc: *Allocator) void {
        switch (self.*) {
            .AO => |*ao| ao.deinit(alloc),
        }
    }

    pub fn startPixel(self: *Integrator) void {
        switch (self.*) {
            .AO => |*ao| ao.startPixel(),
        }
    }

    pub fn li(self: *Integrator, ray: *Ray, isec: *Intersection, worker: *Worker) Vec4f {
        return switch (self.*) {
            .AO => |*ao| ao.li(ray, isec, worker),
        };
    }
};

pub const Factory = union(enum) {
    AO: AO_factory,

    pub fn create(self: Factory, alloc: *Allocator, max_samples_per_pixel: u32) !Integrator {
        return switch (self) {
            .AO => |ao| Integrator{ .AO = try ao.create(alloc, max_samples_per_pixel) },
        };
    }
};
