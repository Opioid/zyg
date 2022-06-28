const Scene = @import("../../scene/scene.zig").Scene;
const Texture = @import("texture.zig").Texture;
pub const AddressMode = @import("address_mode.zig").Mode;

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec3i = math.Vec3i;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");

const Address = struct {
    u: AddressMode,
    v: AddressMode,

    pub fn address2(self: Address, uv: Vec2f) Vec2f {
        return .{ self.u.f(uv[0]), self.v.f(uv[1]) };
    }

    pub fn address3(self: Address, uvw: Vec4f) Vec4f {
        return .{ self.u.f(uvw[0]), self.u.f(uvw[1]), self.u.f(uvw[2]), 0.0 };
    }
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

pub fn sample2D_1(key: Key, texture: Texture, uv: Vec2f, scene: Scene) f32 {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_1(texture, uv, key.address, scene),
        .Linear => Linear2D.sample_1(texture, uv, key.address, scene),
    };
}

pub fn sample2D_2(key: Key, texture: Texture, uv: Vec2f, scene: Scene) Vec2f {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_2(texture, uv, key.address, scene),
        .Linear => Linear2D.sample_2(texture, uv, key.address, scene),
    };
}

pub fn sample2D_3(key: Key, texture: Texture, uv: Vec2f, scene: Scene) Vec4f {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_3(texture, uv, key.address, scene),
        .Linear => Linear2D.sample_3(texture, uv, key.address, scene),
    };
}

pub fn sample3D_1(key: Key, texture: Texture, uvw: Vec4f, scene: Scene) f32 {
    return switch (key.filter) {
        .Nearest => Nearest3D.sample_1(texture, uvw, key.address, scene),
        .Linear => Linear3D.sample_1(texture, uvw, key.address, scene),
    };
}

pub fn sample3D_2(key: Key, texture: Texture, uvw: Vec4f, scene: Scene) Vec2f {
    return switch (key.filter) {
        .Nearest => Nearest3D.sample_2(texture, uvw, key.address, scene),
        .Linear => Linear3D.sample_2(texture, uvw, key.address, scene),
    };
}

const Nearest2D = struct {
    pub fn sample_1(texture: Texture, uv: Vec2f, adr: Address, scene: Scene) f32 {
        const d = texture.description(scene).dimensions;
        const xy = map(.{ d.v[0], d.v[1] }, texture.scale * uv, adr);
        return texture.get2D_1(xy[0], xy[1], scene);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, adr: Address, scene: Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const xy = map(.{ d.v[0], d.v[1] }, texture.scale * uv, adr);
        return texture.get2D_2(xy[0], xy[1], scene);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, adr: Address, scene: Scene) Vec4f {
        const d = texture.description(scene).dimensions;
        const xy = map(.{ d.v[0], d.v[1] }, texture.scale * uv, adr);
        return texture.get2D_3(xy[0], xy[1], scene);
    }

    fn map(d: Vec2i, uv: Vec2f, adr: Address) Vec2i {
        const df = math.vec2iTo2f(d);

        const u = adr.u.f(uv[0]);
        const v = adr.v.f(uv[1]);

        const b = d - @splat(2, @as(i32, 1));

        return .{
            std.math.min(@floatToInt(i32, u * df[0]), b[0]),
            std.math.min(@floatToInt(i32, v * df[1]), b[1]),
        };
    }
};

const Linear2D = struct {
    pub const Map = struct {
        w: Vec2f,
        xy_xy1: Vec4i,
    };

    pub fn sample_1(texture: Texture, uv: Vec2f, adr: Address, scene: Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d.v[0], d.v[1] }, texture.scale * uv, adr);
        const c = texture.gather2D_1(m.xy_xy1, scene);
        return math.bilinear1(c, m.w[0], m.w[1]);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, adr: Address, scene: Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d.v[0], d.v[1] }, texture.scale * uv, adr);
        const c = texture.gather2D_2(m.xy_xy1, scene);
        return bilinear2(c, m.w[0], m.w[1]);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, adr: Address, scene: Scene) Vec4f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d.v[0], d.v[1] }, texture.scale * uv, adr);
        const c = texture.gather2D_3(m.xy_xy1, scene);
        return math.bilinear3(c, m.w[0], m.w[1]);
    }

    fn map(d: Vec2i, uv: Vec2f, adr: Address) Map {
        const df = math.vec2iTo2f(d);

        const u = adr.u.f(uv[0]) * df[0] - 0.5;
        const v = adr.v.f(uv[1]) * df[1] - 0.5;

        const fu = @floor(u);
        const fv = @floor(v);

        const x = @floatToInt(i32, fu);
        const y = @floatToInt(i32, fv);

        const b = d - @splat(2, @as(i32, 1));

        return .{
            .w = .{ u - fu, v - fv },
            .xy_xy1 = Vec4i{
                adr.u.lowerBound(x, b[0]),
                adr.v.lowerBound(y, b[1]),
                adr.u.increment(x, b[0]),
                adr.v.increment(y, b[1]),
            },
        };
    }
};

const Nearest3D = struct {
    pub fn sample_1(texture: Texture, uvw: Vec4f, adr: Address, scene: Scene) f32 {
        const d = texture.description(scene).dimensions;
        const xyz = map(d, uvw, adr);
        return texture.get3D_1(xyz.v[0], xyz.v[1], xyz.v[2], scene);
    }

    pub fn sample_2(texture: Texture, uvw: Vec4f, adr: Address, scene: Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const xyz = map(d, uvw, adr);
        return texture.get3D_2(xyz.v[0], xyz.v[1], xyz.v[2], scene);
    }

    fn map(d: Vec3i, uvw: Vec4f, adr: Address) Vec3i {
        const df = math.vec3iTo4f(d);

        const u = adr.u.f(uvw[0]);
        const v = adr.u.f(uvw[1]);
        const w = adr.u.f(uvw[2]);

        const b = d.subScalar(1);

        return Vec3i.init3(
            std.math.min(@floatToInt(i32, u * df[0]), b.v[0]),
            std.math.min(@floatToInt(i32, v * df[1]), b.v[1]),
            std.math.min(@floatToInt(i32, w * df[2]), b.v[2]),
        );
    }
};

const Linear3D = struct {
    pub const Map = struct {
        w: Vec4f,
        xyz: Vec3i,
        xyz1: Vec3i,
    };

    pub fn sample_1(texture: Texture, uvw: Vec4f, adr: Address, scene: Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr);
        const c = texture.gather3D_1(m.xyz, m.xyz1, scene);

        const c0 = math.bilinear1(.{ c[0], c[1], c[2], c[3] }, m.w[0], m.w[1]);
        const c1 = math.bilinear1(.{ c[4], c[5], c[6], c[7] }, m.w[0], m.w[1]);

        return math.lerp(c0, c1, m.w[2]);
    }

    pub fn sample_2(texture: Texture, uvw: Vec4f, adr: Address, scene: Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr);
        const c = texture.gather3D_2(m.xyz, m.xyz1, scene);

        const c0 = bilinear2(.{ c[0], c[1], c[2], c[3] }, m.w[0], m.w[1]);
        const c1 = bilinear2(.{ c[4], c[5], c[6], c[7] }, m.w[0], m.w[1]);

        return math.lerp2(c0, c1, m.w[2]);
    }

    fn map(d: Vec3i, uvw: Vec4f, adr: Address) Map {
        const df = math.vec3iTo4f(d);

        const u = adr.u.f(uvw[0]) * df[0] - 0.5;
        const v = adr.v.f(uvw[1]) * df[1] - 0.5;
        const w = adr.v.f(uvw[2]) * df[2] - 0.5;

        const fu = @floor(u);
        const fv = @floor(v);
        const fw = @floor(w);

        const x = @floatToInt(i32, fu);
        const y = @floatToInt(i32, fv);
        const z = @floatToInt(i32, fw);

        const b = d.subScalar(1);

        return .{
            .w = .{ u - fu, v - fv, w - fw, 0.0 },
            .xyz = Vec3i.init3(
                adr.u.lowerBound(x, b.v[0]),
                adr.u.lowerBound(y, b.v[1]),
                adr.u.lowerBound(z, b.v[2]),
            ),
            .xyz1 = Vec3i.init3(
                adr.u.increment(x, b.v[0]),
                adr.u.increment(y, b.v[1]),
                adr.u.increment(z, b.v[2]),
            ),
        };
    }
};

fn bilinear2(c: [4]Vec2f, s: f32, t: f32) Vec2f {
    const vs = @splat(2, s);
    const vt = @splat(2, t);

    const _s = @splat(2, @as(f32, 1.0)) - vs;
    const _t = @splat(2, @as(f32, 1.0)) - vt;

    return _t * (_s * c[0] + vs * c[1]) + vt * (_s * c[2] + vs * c[3]);
}
