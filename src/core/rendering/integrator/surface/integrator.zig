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

const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Worker = @import("../../worker.zig").Worker;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

pub const Integrator = union(enum) {
    AOV: AOV,
    PT: Pathtracer,
    PTDL: PathtracerDL,
    PTMIS: PathtracerMIS,

    pub fn li(self: *const Integrator, vertex: Vertex, gather_photons: bool, worker: *Worker) Vec4f {
        return switch (self.*) {
            .PTMIS => |*i| i.li(vertex, gather_photons, worker),
            inline else => |*i| i.li(vertex, worker),
        };
    }
};

pub const Factory = union(enum) {
    AOV: AOVFactory,
    PT: PathtracerFactory,
    PTDL: PathtracerDLFactory,
    PTMIS: PathtracerMISFactory,

    pub fn create(self: Factory) Integrator {
        return switch (self) {
            .AOV => |i| Integrator{ .AOV = i.create() },
            .PT => |i| Integrator{ .PT = i.create() },
            .PTDL => |i| Integrator{ .PTDL = i.create() },
            .PTMIS => |i| Integrator{ .PTMIS = i.create() },
        };
    }
};
