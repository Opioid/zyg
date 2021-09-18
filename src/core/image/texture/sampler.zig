const Scene = @import("../../scene/scene.zig").Scene;
const Texture = @import("texture.zig").Texture;
const am = @import("address_mode.zig");
const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn sample2D_1(texture: Texture, uv: Vec2f, scene: *const Scene) f32 {
    return Nearest2D.sample_1(texture, uv, scene);
}

pub fn sample2D_2(texture: Texture, uv: Vec2f, scene: *const Scene) Vec2f {
    return Nearest2D.sample_2(texture, uv, scene);
}

pub fn sample2D_3(texture: Texture, uv: Vec2f, scene: *const Scene) Vec4f {
    return Linear2D.sample_3(texture, uv, scene);
}

const Nearest2D = struct {
    pub fn sample_1(texture: Texture, uv: Vec2f, scene: *const Scene) f32 {
        const xy = map(texture.description(scene).dimensions.xy(), uv);

        return texture.get2D_1(xy.v[0], xy.v[1], scene);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, scene: *const Scene) Vec2f {
        const xy = map(texture.description(scene).dimensions.xy(), uv);

        return texture.get2D_2(xy.v[0], xy.v[1], scene);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, scene: *const Scene) Vec4f {
        const xy = map(texture.description(scene).dimensions.xy(), uv);

        return texture.get2D_3(xy.v[0], xy.v[1], scene);
    }

    fn map(d: Vec2i, uv: Vec2f) Vec2i {
        const df = d.toVec2f();

        const u = am.Repeat.f(uv.v[0]);
        const v = am.Clamp.f(uv.v[1]);

        const b = d.subScalar(1);

        return Vec2i.init2(
            std.math.min(@floatToInt(i32, u * df.v[0]), b.v[0]),
            std.math.min(@floatToInt(i32, v * df.v[1]), b.v[1]),
        );
    }
};

const Linear2D = struct {
    pub const Map = struct {
        w: Vec2f,
        xy_xy1: Vec4i,
    };

    pub fn sample_3(texture: Texture, uv: Vec2f, scene: *const Scene) Vec4f {
        const m = map(texture.description(scene).dimensions.xy(), uv);

        const c = texture.gather2D_3(m.xy_xy1, scene);
        return bilinear3(c, m.w.v[0], m.w.v[1]);
    }

    fn map(d: Vec2i, uv: Vec2f) Map {
        const df = d.toVec2f();

        const u = am.Repeat.f(uv.v[0]) * df.v[0] - 0.5;
        const v = am.Clamp.f(uv.v[1]) * df.v[1] - 0.5;

        const fu = std.math.floor(u);
        const fv = std.math.floor(v);

        const x = @floatToInt(i32, fu);
        const y = @floatToInt(i32, fv);

        const b = d.subScalar(1);

        return .{
            .w = Vec2f.init2(u - fu, v - fv),
            .xy_xy1 = Vec4i.init4(
                am.Repeat.lowerBound(x, b.v[0]),
                am.Clamp.lowerBound(y, b.v[1]),
                am.Repeat.increment(x, b.v[0]),
                am.Clamp.increment(y, b.v[1]),
            ),
        };
    }

    fn bilinear3(c: [4]Vec4f, s: f32, t: f32) Vec4f {
        const vs = @splat(4, s);
        const vt = @splat(4, t);

        const _s = @splat(4, @as(f32, 1.0)) - vs;
        const _t = @splat(4, @as(f32, 1.0)) - vt;

        return _t * (_s * c[0] + vs * c[1]) + vt * (_s * c[2] + vs * c[3]);
    }
};
