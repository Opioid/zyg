const Sampler = @import("../../sampler/sampler.zig").Sampler;
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

    pub fn address2(self: Address, uv: Vec2f) Vec2f {
        return .{ self.u.f(uv[0]), self.v.f(uv[1]) };
    }

    pub fn address3(self: Address, uvw: Vec4f) Vec4f {
        return self.u.f3(uvw);
    }
};

pub const Filter = enum {
    Nearest,
    Linear,
    Linear_stochastic,
};

pub const Default_filter = Filter.Linear_stochastic;

pub const Key = struct {
    filter: Filter = Default_filter,
    address: Address = .{ .u = .Repeat, .v = .Repeat },
};

pub fn resolveKey(key: Key, filter: ?Filter) Key {
    return .{
        .filter = filter orelse key.filter,
        .address = key.address,
    };
}

pub fn sample2D_1(key: Key, texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) f32 {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_1(texture, uv, key.address, scene),
        .Linear => Linear2D.sample_1(texture, uv, key.address, scene),
        .Linear_stochastic => LinearStochastic2D.sample_1(texture, uv, key.address, sampler, scene),
    };
}

pub fn sample2D_2(key: Key, texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) Vec2f {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_2(texture, uv, key.address, scene),
        .Linear => Linear2D.sample_2(texture, uv, key.address, scene),
        .Linear_stochastic => LinearStochastic2D.sample_2(texture, uv, key.address, sampler, scene),
    };
}

pub fn sample2D_3(key: Key, texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) Vec4f {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_3(texture, uv, key.address, scene),
        .Linear => Linear2D.sample_3(texture, uv, key.address, scene),
        .Linear_stochastic => LinearStochastic2D.sample_3(texture, uv, key.address, sampler, scene),
    };
}

pub fn sample3D_1(key: Key, texture: Texture, uvw: Vec4f, sampler: *Sampler, scene: *const Scene) f32 {
    return switch (key.filter) {
        .Nearest => Nearest3D.sample_1(texture, uvw, key.address, scene),
        .Linear => Linear3D.sample_1(texture, uvw, key.address, scene),
        .Linear_stochastic => LinearStochastic3D.sample_1(texture, uvw, key.address, sampler, scene),
    };
}

pub fn sample3D_2(key: Key, texture: Texture, uvw: Vec4f, sampler: *Sampler, scene: *const Scene) Vec2f {
    return switch (key.filter) {
        .Nearest => Nearest3D.sample_2(texture, uvw, key.address, scene),
        .Linear => Linear3D.sample_2(texture, uvw, key.address, scene),
        .Linear_stochastic => LinearStochastic3D.sample_2(texture, uvw, key.address, sampler, scene),
    };
}

const Nearest2D = struct {
    pub fn sample_1(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.scale * uv, adr);
        return texture.get2D_1(m[0], m[1], scene);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.scale * uv, adr);
        return texture.get2D_2(m[0], m[1], scene);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) Vec4f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.scale * uv, adr);
        return texture.get2D_3(m[0], m[1], scene);
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

    pub fn sample_1(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.scale * uv, adr);
        const c = texture.gather2D_1(m.xy_xy1, scene);
        return math.bilinear(f32, c, m.w[0], m.w[1]);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.scale * uv, adr);
        const c = texture.gather2D_2(m.xy_xy1, scene);
        return math.bilinear(Vec2f, c, m.w[0], m.w[1]);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) Vec4f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.scale * uv, adr);
        const c = texture.gather2D_3(m.xy_xy1, scene);
        return math.bilinear(Vec4f, c, m.w[0], m.w[1]);
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

const LinearStochastic2D = struct {
    pub fn sample_1(texture: Texture, uv: Vec2f, adr: Address, sampler: *Sampler, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.scale * uv, adr, sampler);
        return texture.get2D_1(m[0], m[1], scene);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, adr: Address, sampler: *Sampler, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.scale * uv, adr, sampler);
        return texture.get2D_2(m[0], m[1], scene);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, adr: Address, sampler: *Sampler, scene: *const Scene) Vec4f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.scale * uv, adr, sampler);
        return texture.get2D_3(m[0], m[1], scene);
    }

    fn map(d: Vec2i, uv: Vec2f, adr: Address, sampler: *Sampler) Vec2i {
        const df = math.vec2iTo2f(d);

        // const u = adr.u.f(uv[0]) * df[0] - 0.5;
        // const v = adr.v.f(uv[1]) * df[1] - 0.5;

        const muv = Vec2f{ adr.u.f(uv[0]), adr.v.f(uv[1]) } * df - @splat(2, @as(f32, 0.5));

        // const fu = @floor(u);
        // const fv = @floor(v);

        const fuv = @floor(muv);

        // const x = @floatToInt(i32, fu);
        // const y = @floatToInt(i32, fv);

        const xy = math.vec2fTo2i(fuv);

        const b = d - @splat(2, @as(i32, 1));
        // const wu = u - fu;
        // const wv = v - fv;

        const wuv = muv - fuv;
        const r = sampler.sample2D();

        // return .{
        //     if (r[0] <= wu) adr.u.increment(x, b[0]) else adr.u.lowerBound(x, b[0]),
        //     if (r[1] <= wv) adr.v.increment(y, b[1]) else adr.v.lowerBound(y, b[1]),
        // };

        const c = r <= wuv;

        return .{
            adr.u.offset(xy[0], @boolToInt(c[0]), b[0]),
            adr.v.offset(xy[1], @boolToInt(c[1]), b[1]),
        };
    }
};

const Nearest3D = struct {
    pub fn sample_1(texture: Texture, uvw: Vec4f, adr: Address, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr);
        return texture.get3D_1(m[0], m[1], m[2], scene);
    }

    pub fn sample_2(texture: Texture, uvw: Vec4f, adr: Address, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr);
        return texture.get3D_2(m[0], m[1], m[2], scene);
    }

    fn map(d: Vec4i, uvw: Vec4f, adr: Address) Vec4i {
        const df = math.vec4iTo4f(d);

        const muvw = adr.u.f3(uvw);

        const b = d - @splat(4, @as(i32, 1));

        return @min(math.vec4fTo4i(muvw * df), b);
    }
};

const Linear3D = struct {
    pub const Map = struct {
        w: Vec4f,
        xyz: Vec4i,
        xyz1: Vec4i,
    };

    pub fn sample_1(texture: Texture, uvw: Vec4f, adr: Address, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr);
        const c = texture.gather3D_1(m.xyz, m.xyz1, scene);

        const ci = math.bilinear(Vec2f, .{
            c[0..2].*,
            c[2..4].*,
            c[4..6].*,
            c[6..8].*,
        }, m.w[0], m.w[1]);

        return math.lerp(ci[0], ci[1], m.w[2]);
    }

    pub fn sample_2(texture: Texture, uvw: Vec4f, adr: Address, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr);
        const c = texture.gather3D_2(m.xyz, m.xyz1, scene);

        const cl = math.bilinear(Vec4f, .{
            .{ c[0][0], c[0][1], c[1][0], c[1][1] },
            .{ c[2][0], c[2][1], c[3][0], c[3][1] },
            .{ c[4][0], c[4][1], c[5][0], c[5][1] },
            .{ c[6][0], c[6][1], c[7][0], c[7][1] },
        }, m.w[0], m.w[1]);

        return math.lerp(Vec2f{ cl[0], cl[1] }, Vec2f{ cl[2], cl[3] }, m.w[2]);
    }

    fn map(d: Vec4i, uvw: Vec4f, adr: Address) Map {
        const df = math.vec4iTo4f(d);

        const muvw = adr.u.f3(uvw) * df - Vec4f{ 0.5, 0.5, 0.5, 0.0 };
        const fuvw = @floor(muvw);
        const xyz = math.vec4fTo4i(fuvw);

        const b = d - Vec4i{ 1, 1, 1, 0 };

        return .{
            .w = muvw - fuvw,
            .xyz = adr.u.lowerBound3(xyz, b),
            .xyz1 = adr.u.increment3(xyz, b),
        };
    }
};

const LinearStochastic3D = struct {
    pub fn sample_1(texture: Texture, uvw: Vec4f, adr: Address, sampler: *Sampler, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr, sampler);
        return texture.get3D_1(m[0], m[1], m[2], scene);
    }

    pub fn sample_2(texture: Texture, uvw: Vec4f, adr: Address, sampler: *Sampler, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr, sampler);
        return texture.get3D_2(m[0], m[1], m[2], scene);
    }

    fn map(d: Vec4i, uvw: Vec4f, adr: Address, sampler: *Sampler) Vec4i {
        const df = math.vec4iTo4f(d);

        const muvw = adr.u.f3(uvw) * df - Vec4f{ 0.5, 0.5, 0.5, 0.0 };
        const fuvw = @floor(muvw);
        const xyz = math.vec4fTo4i(fuvw);

        const b = d - Vec4i{ 1, 1, 1, 0 };
        const w = muvw - fuvw;
        const r = sampler.sample3D();
        // _ = sampler;
        // const r = Vec4f{ 0.5, 0.5, 0.5, 0.0 };

        return .{
            if (r[0] <= w[0]) adr.u.increment(xyz[0], b[0]) else adr.u.lowerBound(xyz[0], b[0]),
            if (r[1] <= w[1]) adr.u.increment(xyz[1], b[1]) else adr.u.lowerBound(xyz[1], b[1]),
            if (r[2] <= w[2]) adr.u.increment(xyz[2], b[2]) else adr.u.lowerBound(xyz[2], b[2]),
            0,
        };

        // var p: [3]f32 = undefined;

        // p[0] = r;
        // if (p[0] <= w[0]) {
        //     p[1] = p[0] / w[0];
        // } else {
        //     p[1] = p[0] / (1.0 - w[0]);
        // }

        // if (p[1] <= w[1]) {
        //     p[2] = p[1] / w[0];
        // } else {
        //     p[2] = p[1] / (1.0 - w[0]);
        // }

        // return .{
        //     if (p[0] <= w[0]) adr.u.increment(xyz[0], b[0]) else adr.u.lowerBound(xyz[0], b[0]),
        //     if (p[1] <= w[1]) adr.u.increment(xyz[1], b[1]) else adr.u.lowerBound(xyz[1], b[1]),
        //     if (p[2] <= w[2]) adr.u.increment(xyz[2], b[2]) else adr.u.lowerBound(xyz[2], b[2]),
        //     0,
        // };
    }
};
