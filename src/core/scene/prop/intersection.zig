const shp = @import("../shape/intersection.zig");
const Shape = @import("../shape/shape.zig").Shape;
const Ray = @import("../ray.zig").Ray;
const ro = @import("../ray_offset.zig");
const Renderstate = @import("../renderstate.zig").Renderstate;
const Scene = @import("../scene.zig").Scene;
const Worker = @import("../../rendering/worker.zig").Worker;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const mat = @import("../material/material.zig");

const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Intersection = struct {
    geo: shp.Intersection = undefined,
    prop: u32 = undefined,
    volume: shp.Volume = undefined,

    const Self = @This();

    pub fn material(self: Self, scene: *const Scene) *const mat.Material {
        return scene.propMaterial(self.prop, self.geo.part);
    }

    pub fn shape(self: Self, scene: *const Scene) *Shape {
        return scene.propShape(self.prop);
    }

    pub fn lightId(self: Self, scene: *const Scene) u32 {
        return scene.propLightId(self.prop, self.geo.part);
    }

    pub fn visibleInCamera(self: Self, scene: *const Scene) bool {
        return scene.prop(self.prop).visibleInCamera();
    }

    pub fn opacity(self: Self, sampler: *Sampler, scene: *const Scene) f32 {
        return self.material(scene).opacity(self.geo.uv, sampler, scene);
    }

    pub inline fn subsurface(self: Self) bool {
        return .Pass != self.volume.event;
    }

    pub fn sample(
        self: Self,
        wo: Vec4f,
        ray: Ray,
        sampler: *Sampler,
        avoid_caustics: bool,
        worker: *const Worker,
    ) mat.Sample {
        const m = self.material(worker.scene);
        const p = self.geo.p;
        const b = self.geo.b;

        var rs: Renderstate = undefined;
        rs.trafo = self.geo.trafo;
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
        rs.subsurface = self.subsurface();
        rs.avoid_caustics = avoid_caustics;

        return m.sample(wo, rs, sampler, worker);
    }

    pub fn evaluateRadiance(
        self: Self,
        shading_p: Vec4f,
        wo: Vec4f,
        sampler: *Sampler,
        scene: *const Scene,
        pure_emissive: *bool,
    ) ?Vec4f {
        const m = self.material(scene);

        const volume = self.volume.event;

        pure_emissive.* = m.pureEmissive() or .Absorb == volume;

        if (.Absorb == volume) {
            return self.volume.li;
        }

        if (!m.emissive() or (!m.twoSided() and !self.sameHemisphere(wo)) or .Scatter == volume) {
            return null;
        }

        const uv = self.geo.uv;
        return m.evaluateRadiance(
            shading_p,
            wo,
            self.geo.geo_n,
            .{ uv[0], uv[1], 0.0, 0.0 },
            self.geo.trafo,
            self.prop,
            self.geo.part,
            sampler,
            scene,
        );
    }

    pub fn sameHemisphere(self: Self, v: Vec4f) bool {
        return math.dot3(self.geo.geo_n, v) > 0.0;
    }

    pub fn offsetP(self: Self, v: Vec4f) Vec4f {
        const p = self.geo.p;
        const n = self.geo.geo_n;
        return ro.offsetRay(p, if (self.sameHemisphere(v)) n else -n);
    }

    pub fn offsetPN(self: Self, geo_n: Vec4f, translucent: bool) Vec4f {
        const p = self.geo.p;

        if (translucent) {
            const t = math.hmax3(@fabs(p * geo_n));
            const d = ro.offsetF(t) - t;

            return .{ p[0], p[1], p[2], d };
        }

        return ro.offsetRay(p, geo_n);
    }

    pub fn offsetT(self: Self, min_t: f32) f32 {
        const p = self.geo.p;
        const n = self.geo.geo_n;

        const t = math.hmax3(@fabs(p * n));
        return ro.offsetF(t + min_t) - t;
    }
};
