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

const IValue = @import("../helper.zig").IValue;

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

    pub fn li(self: *const Integrator, vertex: *const Vertex, worker: *Worker) IValue {
        return switch (self.*) {
            inline else => |*i| i.li(vertex, worker),
        };
    }
};
