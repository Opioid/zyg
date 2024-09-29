const Shape = @import("shape.zig").Shape;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const ro = @import("../ray_offset.zig");
const Scene = @import("../scene.zig").Scene;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const mat = @import("../material/material.zig");

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Volume = struct {
    pub const Event = enum(u8) { Absorb, Scatter, ExitSSS, Pass };

    li: Vec4f,
    tr: Vec4f,
    uvw: Vec4f = @splat(0.0),
    t: f32,
    event: Event,

    pub fn initPass(w: Vec4f) Volume {
        return .{
            .li = @splat(0.0),
            .tr = w,
            .t = 0.0,
            .event = .Pass,
        };
    }
};

pub const Intersection = struct {
    pub const Null: u32 = 0xFFFFFFFF;

    t: f32 = undefined,
    u: f32 = undefined,
    v: f32 = undefined,
    primitive: u32 = Null,
};

pub const Fragment = struct {
    isec: Intersection,
    prop: u32,
    part: u32,
    event: Volume.Event,

    trafo: Trafo,
    p: Vec4f,
    geo_n: Vec4f,
    t: Vec4f,
    b: Vec4f,
    n: Vec4f,
    vol_li: Vec4f,
    uvw: Vec4f,

    const Self = @This();

    pub fn setVolume(self: *Self, vol: Volume) void {
        self.event = vol.event;
        self.vol_li = vol.li;
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
        return .Scatter == self.event;
    }

    pub fn sameHemisphere(self: Self, v: Vec4f) bool {
        return math.dot3(self.geo_n, v) > 0.0;
    }

    pub fn offsetP(self: Self, v: Vec4f) Vec4f {
        const p = self.p;
        const n = if (self.sameHemisphere(v)) self.geo_n else -self.geo_n;
        return ro.offsetRay(p + @as(Vec4f, @splat(self.offset())) * n, n);
    }

    pub fn evaluateRadiance(self: Self, shading_p: Vec4f, wo: Vec4f, sampler: *Sampler, scene: *const Scene) ?Vec4f {
        const volume = self.event;
        if (.Absorb == volume) {
            return self.vol_li;
        }

        const m = self.material(scene);
        if (!m.emissive() or (!m.twoSided() and !self.sameHemisphere(wo)) or .Pass != volume) {
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
};

pub const Interpolation = enum {
    PositionAndNormal,
    All,
};
