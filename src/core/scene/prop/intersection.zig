const shp = @import("../shape/intersection.zig");
const Shape = @import("../shape/shape.zig").Shape;
const Ray = @import("../ray.zig").Ray;
const Renderstate = @import("../renderstate.zig").Renderstate;
const Scene = @import("../scene.zig").Scene;
const Worker = @import("../worker.zig").Worker;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const mat = @import("../material/material.zig");
const ro = @import("../ray_offset.zig");

const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Intersection = struct {
    geo: shp.Intersection = undefined,
    prop: u32 = undefined,
    subsurface: bool = undefined,

    const Self = @This();

    pub fn material(self: Self, scene: Scene) mat.Material {
        return scene.propMaterial(self.prop, self.geo.part);
    }

    pub fn shape(self: Self, scene: Scene) Shape {
        return scene.propShape(self.prop);
    }

    pub fn lightId(self: Self, scene: Scene) u32 {
        return scene.propLightId(self.prop, self.geo.part);
    }

    pub fn visibleInCamera(self: Self, scene: Scene) bool {
        return scene.prop(self.prop).visibleInCamera();
    }

    pub fn opacity(self: Self, filter: ?Filter, scene: Scene) f32 {
        return self.material(scene).opacity(self.geo.uv, filter, scene);
    }

    pub fn sample(
        self: Self,
        wo: Vec4f,
        ray: Ray,
        filter: ?Filter,
        avoid_caustics: bool,
        worker: Worker,
    ) mat.Sample {
        const m = self.material(worker.scene.*);
        const p = self.geo.p;
        const b = self.geo.b;

        var rs: Renderstate = undefined;
        rs.p = .{ p[0], p[1], p[2], worker.iorOutside(wo, self) };
        rs.t = self.geo.t;
        rs.b = .{ b[0], b[1], b[2], ray.wavelength };

        if (m.twoSided() and !self.sameHemisphere(wo)) {
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
        rs.depth = ray.depth;
        rs.time = ray.time;
        rs.filter = filter;
        rs.subsurface = self.subsurface;
        rs.avoid_caustics = avoid_caustics;

        return m.sample(wo, rs, worker);
    }

    pub fn evaluateRadiance(
        self: Self,
        wo: Vec4f,
        filter: ?Filter,
        scene: Scene,
        pure_emissive: *bool,
    ) ?Vec4f {
        const m = self.material(scene);

        pure_emissive.* = m.pureEmissive();

        if (!m.twoSided() and !self.sameHemisphere(wo)) {
            return null;
        }

        const extent = scene.lightArea(self.prop, self.geo.part);

        const uv = self.geo.uv;
        return m.evaluateRadiance(wo, self.geo.geo_n, .{ uv[0], uv[1], 0.0, 0.0 }, extent, filter, scene);
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
            const t = math.maxComponent3(@fabs(p * geo_n));
            const d = ro.offsetF(t) - t;

            return .{ p[0], p[1], p[2], d };
        }

        return ro.offsetRay(p, geo_n);
    }
};
