const Scene = @import("../../scene/scene.zig").Scene;
const Texture = @import("texture.zig").Texture;
const am = @import("address_mode.zig");
const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn sample2D_1(texture: Texture, uv: Vec2f, scene: *const Scene) f32 {
    return Nearest2D.sample_1(texture, uv, scene);
}

pub fn sample2D_2(texture: Texture, uv: Vec2f, scene: *const Scene) Vec2f {
    return Nearest2D.sample_2(texture, uv, scene);
}

pub fn sample2D_3(texture: Texture, uv: Vec2f, scene: *const Scene) Vec4f {
    return Nearest2D.sample_3(texture, uv, scene);
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
        const v = am.Repeat.f(uv.v[1]);

        const b = d.subScalar(1);

        return Vec2i.init2(
            std.math.min(@floatToInt(i32, u * df.v[0]), b.v[0]),
            std.math.min(@floatToInt(i32, v * df.v[1]), b.v[1]),
        );
    }
};
