const aov = @import("aov.zig");
pub const AOV = aov.AOV;
pub const AOVFactory = aov.Factory;

const pt = @import("pathtracer.zig");
pub const Pathtracer = pt.Pathtracer;
pub const PathtracerFactory = pt.Factory;

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
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Integrator = union(enum) {
    AOV: AOV,
    PT: Pathtracer,
    PTDL: PathtracerDL,
    PTMIS: PathtracerMIS,

    pub fn startPixel(self: *Integrator, sample: u32, seed: u32) void {
        switch (self.*) {
            inline else => |*i| i.startPixel(sample, seed),
        }
    }

    pub fn li(
        self: *Integrator,
        ray: *Ray,
        isec: *Intersection,
        gather_photons: bool,
        worker: *Worker,
        initial_stack: InterfaceStack,
    ) Vec4f {
        return switch (self.*) {
            .AOV => |*i| i.li(ray, isec, worker, initial_stack),
            .PT => |*i| i.li(ray, isec, worker, initial_stack),
            .PTDL => |*i| i.li(ray, isec, worker, initial_stack),
            .PTMIS => |*i| i.li(ray, isec, gather_photons, worker, initial_stack),
        };
    }

    pub fn sampler(self: *Integrator) *Sampler {
        return switch (self.*) {
            inline else => |*i| &i.samplers[0],
        };
    }
};

pub const Factory = union(enum) {
    AOV: AOVFactory,
    PT: PathtracerFactory,
    PTDL: PathtracerDLFactory,
    PTMIS: PathtracerMISFactory,

    pub fn create(self: Factory, rng: *RNG) Integrator {
        return switch (self) {
            .AOV => |i| Integrator{ .AOV = i.create(rng) },
            .PT => |i| Integrator{ .PT = i.create(rng) },
            .PTDL => |i| Integrator{ .PTDL = i.create(rng) },
            .PTMIS => |i| Integrator{ .PTMIS = i.create(rng) },
        };
    }
};
