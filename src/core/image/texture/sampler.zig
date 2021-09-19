const Scene = @import("../../scene/scene.zig").Scene;
const Texture = @import("texture.zig").Texture;
pub const AddressMode = @import("address_mode.zig").Mode;
const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");

const Address = struct {
    u: AddressMode,
    v: AddressMode,
};

pub const Filter = enum {
    Nearest,
    Linear,
};

pub const Key = struct {
    filter: Filter = .Linear,
    address: Address = .{ .u = .Repeat, .v = .Repeat },
};

pub fn resolveKey(key: Key, filter: ?Filter) Key {
    return .{
        .filter = filter orelse key.filter,
        .address = key.address,
    };
}

pub fn sample2D_1(key: Key, texture: Texture, uv: Vec2f, scene: *const Scene) f32 {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_1(texture, uv, key.address, scene),
        .Linear => Linear2D.sample_1(texture, uv, key.address, scene),
    };
}

pub fn sample2D_2(key: Key, texture: Texture, uv: Vec2f, scene: *const Scene) Vec2f {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_2(texture, uv, key.address, scene),
        .Linear => Linear2D.sample_2(texture, uv, key.address, scene),
    };
}

pub fn sample2D_3(key: Key, texture: Texture, uv: Vec2f, scene: *const Scene) Vec4f {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_3(texture, uv, key.address, scene),
        .Linear => Linear2D.sample_3(texture, uv, key.address, scene),
    };
}

const Nearest2D = struct {
    pub fn sample_1(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) f32 {
        const xy = map(texture.description(scene).dimensions.xy(), uv, adr);
        return texture.get2D_1(xy.v[0], xy.v[1], scene);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) Vec2f {
        const xy = map(texture.description(scene).dimensions.xy(), uv, adr);
        return texture.get2D_2(xy.v[0], xy.v[1], scene);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) Vec4f {
        const xy = map(texture.description(scene).dimensions.xy(), uv, adr);
        return texture.get2D_3(xy.v[0], xy.v[1], scene);
    }

    fn map(d: Vec2i, uv: Vec2f, adr: Address) Vec2i {
        const df = d.toVec2f();

        const u = adr.u.f(uv[0]);
        const v = adr.v.f(uv[1]);

        const b = d.subScalar(1);

        return Vec2i.init2(
            std.math.min(@floatToInt(i32, u * df[0]), b.v[0]),
            std.math.min(@floatToInt(i32, v * df[1]), b.v[1]),
        );
    }
};

const Linear2D = struct {
    pub const Map = struct {
        w: Vec2f,
        xy_xy1: Vec4i,
    };

    pub fn sample_1(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) f32 {
        const m = map(texture.description(scene).dimensions.xy(), uv, adr);
        const c = texture.gather2D_1(m.xy_xy1, scene);
        return bilinear1(c, m.w[0], m.w[1]);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) Vec2f {
        const m = map(texture.description(scene).dimensions.xy(), uv, adr);
        const c = texture.gather2D_2(m.xy_xy1, scene);
        return bilinear2(c, m.w[0], m.w[1]);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) Vec4f {
        const m = map(texture.description(scene).dimensions.xy(), uv, adr);
        const c = texture.gather2D_3(m.xy_xy1, scene);
        return bilinear3(c, m.w[0], m.w[1]);
    }

    fn map(d: Vec2i, uv: Vec2f, adr: Address) Map {
        const df = d.toVec2f();

        const u = adr.u.f(uv[0]) * df[0] - 0.5;
        const v = adr.v.f(uv[1]) * df[1] - 0.5;

        const fu = std.math.floor(u);
        const fv = std.math.floor(v);

        const x = @floatToInt(i32, fu);
        const y = @floatToInt(i32, fv);

        const b = d.subScalar(1);

        return .{
            .w = .{ u - fu, v - fv },
            .xy_xy1 = Vec4i.init4(
                adr.u.lowerBound(x, b.v[0]),
                adr.v.lowerBound(y, b.v[1]),
                adr.u.increment(x, b.v[0]),
                adr.v.increment(y, b.v[1]),
            ),
        };
    }

    fn bilinear1(c: [4]f32, s: f32, t: f32) f32 {
        const _s = 1.0 - s;
        const _t = 1.0 - t;

        return _t * (_s * c[0] + s * c[1]) + t * (_s * c[2] + s * c[3]);
    }

    fn bilinear2(c: [4]Vec2f, s: f32, t: f32) Vec2f {
        const vs = @splat(2, s);
        const vt = @splat(2, t);

        const _s = @splat(2, @as(f32, 1.0)) - vs;
        const _t = @splat(2, @as(f32, 1.0)) - vt;

        return _t * (_s * c[0] + vs * c[1]) + vt * (_s * c[2] + vs * c[3]);
    }

    fn bilinear3(c: [4]Vec4f, s: f32, t: f32) Vec4f {
        const vs = @splat(4, s);
        const vt = @splat(4, t);

        const _s = @splat(4, @as(f32, 1.0)) - vs;
        const _t = @splat(4, @as(f32, 1.0)) - vt;

        return _t * (_s * c[0] + vs * c[1]) + vt * (_s * c[2] + vs * c[3]);
    }
};
