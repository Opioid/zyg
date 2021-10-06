const aoc = @import("ao.zig");
pub const AO = aoc.AO;
pub const AOFactory = aoc.Factory;

const ptr = @import("pathtracer.zig");
pub const Pathtracer = ptr.Pathtracer;
pub const PathtracerFactory = ptr.Factory;

const ptdl = @import("pathtracer_dl.zig");
pub const PathtracerDL = ptdl.PathtracerDL;
pub const PathtracerDLFactory = ptdl.Factory;

const ptmis = @import("pathtracer_mis.zig");
pub const PathtracerMIS = ptmis.PathtracerMIS;
pub const PathtracerMISFactory = ptmis.Factory;

const Ray = @import("../../../scene/ray.zig").Ray;
const Worker = @import("../../worker.zig").Worker;
const Intersection = @import("../../../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../../../scene/prop/interface.zig").Stack;

const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Integrator = union(enum) {
    AO: AO,
    PT: Pathtracer,
    PTDL: PathtracerDL,
    PTMIS: PathtracerMIS,

    pub fn deinit(self: *Integrator, alloc: *Allocator) void {
        switch (self.*) {
            .AO => |*ao| ao.deinit(alloc),
            .PT => |*pt| pt.deinit(alloc),
            .PTDL => |*pt| pt.deinit(alloc),
            .PTMIS => |*pt| pt.deinit(alloc),
        }
    }

    pub fn startPixel(self: *Integrator) void {
        switch (self.*) {
            .AO => |*ao| ao.startPixel(),
            .PT => |*pt| pt.startPixel(),
            .PTDL => |*pt| pt.startPixel(),
            .PTMIS => |*pt| pt.startPixel(),
        }
    }

    pub fn li(
        self: *Integrator,
        ray: *Ray,
        isec: *Intersection,
        worker: *Worker,
        initial_stack: InterfaceStack,
    ) Vec4f {
        return switch (self.*) {
            .AO => |*ao| ao.li(ray, isec, worker),
            .PT => |*pt| pt.li(ray, isec, worker, initial_stack),
            .PTDL => |*pt| pt.li(ray, isec, worker, initial_stack),
            .PTMIS => |*pt| pt.li(ray, isec, worker, initial_stack),
        };
    }
};

pub const Factory = union(enum) {
    AO: AOFactory,
    PT: PathtracerFactory,
    PTDL: PathtracerDLFactory,
    PTMIS: PathtracerMISFactory,

    pub fn create(self: Factory, alloc: *Allocator, max_samples_per_pixel: u32) !Integrator {
        return switch (self) {
            .AO => |ao| Integrator{ .AO = try ao.create(alloc, max_samples_per_pixel) },
            .PT => |pt| Integrator{ .PT = try pt.create(alloc, max_samples_per_pixel) },
            .PTDL => |pt| Integrator{ .PTDL = try pt.create(alloc, max_samples_per_pixel) },
            .PTMIS => |pt| Integrator{ .PTMIS = try pt.create(alloc, max_samples_per_pixel) },
        };
    }
};
