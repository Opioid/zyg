const shape = @import("../shape/intersection.zig");
const Ray = @import("../ray.zig").Ray;
const Renderstate = @import("../renderstate.zig").Renderstate;
const Worker = @import("../worker.zig").Worker;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const mat = @import("../material/material.zig");
const math = @import("base").math;
const Vec4f = math.Vec4f;
const ro = @import("../ray_offset.zig");

pub const Intersection = struct {
    geo: shape.Intersection = undefined,

    prop: u32 = undefined,

    const Self = @This();

    pub fn material(self: Self, worker: Worker) mat.Material {
        return worker.scene.propMaterial(self.prop, self.geo.part);
    }

    pub fn opacity(self: Self, filter: ?Filter, worker: Worker) f32 {
        return self.material(worker).opacity(self.geo.uv, filter, worker);
    }

    pub fn sample(self: Self, wo: Vec4f, ray: Ray, filter: ?Filter, worker: *Worker) mat.Sample {
        _ = ray;

        const m = self.material(worker.*);

        var rs = Renderstate{};
        rs.p = self.geo.p;
        rs.t = self.geo.t;
        rs.b = self.geo.b;

        if (m.isTwoSided() and !self.sameHemisphere(wo)) {
            rs.geo_n = -self.geo.geo_n;
            rs.n = -self.geo.n;
        } else {
            rs.geo_n = self.geo.geo_n;
            rs.n = self.geo.n;
        }

        rs.uv = self.geo.uv;
        rs.prop = self.prop;
        rs.part = self.geo.part;
        rs.primitive = self.geo.primitive;
        rs.filter = filter;

        return m.sample(wo, rs, worker);
    }

    pub fn sameHemisphere(self: Self, v: Vec4f) bool {
        return math.dot3(self.geo.geo_n, v) > 0.0;
    }

    pub fn offsetP(self: Self, v: Vec4f) Vec4f {
        const p = self.geo.p;

        return ro.offsetRay(p, if (self.sameHemisphere(v)) self.geo.geo_n else -self.geo.geo_n);
    }

    pub fn offsetPN(self: Self, geo_n: Vec4f, translucent: bool) Vec4f {
        const p = self.geo.p;

        if (translucent) {
            const t = math.maxComponent3(math.abs(p * geo_n));
            const d = ro.offsetF(t) - t;

            return .{ p[0], p[1], p[2], d };
        }

        return ro.offsetRay(p, geo_n);
    }
};
