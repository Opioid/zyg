pub const AOV = @import("aov.zig").AOV;
pub const Pathtracer = @import("pathtracer.zig").Pathtracer;
pub const PathtracerDL = @import("pathtracer_dl.zig").PathtracerDL;
pub const PathtracerMIS = @import("pathtracer_mis.zig").PathtracerMIS;

const IValue = @import("../helper.zig").IValue;
const Vertex = @import("../../../scene/vertex.zig").Vertex;
const Worker = @import("../../worker.zig").Worker;

pub const Integrator = union(enum) {
    AOV: AOV,
    PT: Pathtracer,
    PTDL: PathtracerDL,
    PTMIS: PathtracerMIS,

    pub fn li(self: Integrator, vertex: Vertex, worker: *Worker) IValue {
        return switch (self) {
            inline else => |i| i.li(vertex, worker),
        };
    }
};
