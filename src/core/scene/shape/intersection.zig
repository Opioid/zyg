const Shape = @import("shape.zig").Shape;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const ro = @import("../ray_offset.zig");
const Scene = @import("../scene.zig").Scene;
const Material = @import("../material/material.zig").Material;

const math = @import("base").math;
const Ray = math.Ray;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Volume = struct {
    pub const Event = enum(u8) {
        Absorb,
        Abort,
        ExitSSS,
        Pass,
        Scatter,
    };

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

    pub fn initAbort() Volume {
        return .{
            .li = @splat(0.0),
            .tr = @splat(0.0),
            .t = 0.0,
            .event = .Abort,
        };
    }
};

pub const Intersection = struct {
    pub const Null: u32 = 0xFFFFFFFF;

    t: f32,
    u: f32,
    v: f32,
    primitive: u32,
    prototype: u32,

    trafo: Trafo,

    pub inline fn resolveEntity(self: Intersection, p: u32) u32 {
        const prototype = self.prototype;
        return if (Intersection.Null == prototype) p else prototype;
    }
};

pub const Fragment = struct {
    isec: Intersection,
    prop: u32,
    part: u32,
    event: Volume.Event,

    p: Vec4f,
    geo_n: Vec4f,
    t: Vec4f,
    b: Vec4f,
    n: Vec4f,
    vol_li: Vec4f,
    uvw: Vec4f,

    const Self = @This();

    pub inline fn uv(self: Self) Vec2f {
        return .{ self.uvw[0], self.uvw[1] };
    }

    pub inline fn offset(self: Self) f32 {
        return self.uvw[3];
    }

    pub inline fn hit(self: Self) bool {
        return Scene.Null != self.prop;
    }

    pub fn material(self: Self, scene: *const Scene) *const Material {
        return scene.propMaterial(self.prop, self.part);
    }

    pub fn shape(self: Self, scene: *const Scene) *Shape {
        return scene.propShape(self.prop);
    }

    pub fn lightId(self: Self, scene: *const Scene) u32 {
        return scene.propLightId(self.prop, self.part);
    }

    pub fn visibleInCamera(self: Self, scene: *const Scene) bool {
        return scene.propIsVisibleInCamera(self.prop);
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
        return ro.offsetRay(@mulAdd(Vec4f, @splat(self.offset()), n, p), n);
    }

    pub fn offsetRay(self: Self, dir: Vec4f) Ray {
        return Ray.init(self.offsetP(dir), dir, 0.0, ro.RayMaxT);
    }
};

pub const DifferentialSurface = struct {
    dpdu: Vec4f,
    dpdv: Vec4f,
};
