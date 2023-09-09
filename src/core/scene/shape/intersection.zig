const Shape = @import("shape.zig").Shape;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Vertex = @import("../vertex.zig").Vertex;
const ro = @import("../ray_offset.zig");
const rst = @import("../renderstate.zig");
const Renderstate = rst.Renderstate;
const CausticsResolve = rst.CausticsResolve;
const Scene = @import("../scene.zig").Scene;
const Worker = @import("../../rendering/worker.zig").Worker;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const mat = @import("../material/material.zig");

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Volume = struct {
    pub const Event = enum { Absorb, Scatter, Pass };

    li: Vec4f,
    tr: Vec4f,
    uvw: Vec4f = undefined,
    t: f32 = undefined,
    event: Event,

    pub fn initPass(w: Vec4f) Volume {
        return .{
            .li = @splat(0.0),
            .tr = w,
            .uvw = @splat(0.0),
            .event = .Pass,
        };
    }
};

pub const Intersection = struct {
    event: Volume.Event,
    prop: u32,
    part: u32,
    primitive: u32,

    trafo: Trafo,
    p: Vec4f,
    geo_n: Vec4f,
    t: Vec4f,
    b: Vec4f,
    n: Vec4f,
    vol_li: Vec4f,
    vol_tr: Vec4f,
    uvw: Vec4f,

    const Self = @This();

    pub fn setVolume(self: *Self, vol: Volume) void {
        self.event = vol.event;
        self.vol_li = vol.li;
        self.vol_tr = vol.tr;
    }

    pub inline fn uv(self: Self) Vec2f {
        return .{ self.uvw[0], self.uvw[1] };
    }

    pub inline fn offset(self: Self) f32 {
        return self.uvw[3];
    }

    pub fn material(self: Self, scene: *const Scene) *const mat.Material {
        return scene.propMaterial(self.prop, self.part);
    }

    pub fn shape(self: Self, scene: *const Scene) *Shape {
        return scene.propShape(self.prop);
    }

    pub fn lightId(self: Self, scene: *const Scene) u32 {
        return scene.propLightId(self.prop, self.part);
    }

    pub fn visibleInCamera(self: Self, scene: *const Scene) bool {
        return scene.prop(self.prop).visibleInCamera();
    }

    pub fn opacity(self: Self, sampler: *Sampler, scene: *const Scene) f32 {
        return self.material(scene).opacity(self.uv(), sampler, scene);
    }

    pub inline fn subsurface(self: Self) bool {
        return .Pass != self.event;
    }

    pub fn sample(
        self: Self,
        wo: Vec4f,
        vertex: Vertex,
        sampler: *Sampler,
        caustics: CausticsResolve,
        worker: *const Worker,
    ) mat.Sample {
        const m = self.material(worker.scene);
        const p = self.p;
        const b = self.b;

        var rs: Renderstate = undefined;
        rs.trafo = self.trafo;
        rs.p = .{ p[0], p[1], p[2], worker.iorOutside(wo, self) };
        rs.t = self.t;
        rs.b = .{ b[0], b[1], b[2], vertex.wavelength };

        if (m.twoSided() and !self.sameHemisphere(wo)) {
            rs.geo_n = -self.geo_n;
            rs.n = -self.n;
        } else {
            rs.geo_n = self.geo_n;
            rs.n = self.n;
        }

        rs.ray_p = vertex.ray.origin;

        rs.uv = self.uv();
        rs.prop = self.prop;
        rs.part = self.part;
        rs.primitive = self.primitive;
        rs.depth = vertex.depth;
        rs.time = vertex.time;
        rs.subsurface = self.subsurface();
        rs.caustics = caustics;

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

        const volume = self.event;

        pure_emissive.* = m.pureEmissive() or .Absorb == volume;

        if (.Absorb == volume) {
            return self.vol_li;
        }

        if (!m.emissive() or (!m.twoSided() and !self.sameHemisphere(wo)) or .Scatter == volume) {
            return null;
        }

        return m.evaluateRadiance(
            shading_p,
            wo,
            self.geo_n,
            self.uvw,
            self.trafo,
            self.prop,
            self.part,
            sampler,
            scene,
        );
    }

    pub fn sameHemisphere(self: Self, v: Vec4f) bool {
        return math.dot3(self.geo_n, v) > 0.0;
    }

    pub fn offsetP(self: Self, v: Vec4f) Vec4f {
        const p = self.p;
        const n = if (self.sameHemisphere(v)) self.geo_n else -self.geo_n;
        return ro.offsetRay(p + @as(Vec4f, @splat(self.offset())) * n, n);
    }

    pub fn offsetT(self: Self, min_t: f32) f32 {
        const p = self.p;
        const n = self.geo_n;
        const t = math.hmax3(@fabs(p * n));
        return ro.offsetF(t + min_t) - t + self.offset();
    }
};

pub const Interpolation = enum {
    Normal,
    All,
};
