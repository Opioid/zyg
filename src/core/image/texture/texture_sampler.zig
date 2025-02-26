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

    pub fn coord2(self: Address, c: Vec2i, end: Vec2i) Vec2i {
        return .{ self.u.coord(c[0], end[0]), self.v.coord(c[1], end[1]) };
    }
};

pub const Filter = enum {
    Nearest,
    LinearStochastic,
};

pub const DefaultFilter = Filter.LinearStochastic;

pub const Key = struct {
    filter: Filter = DefaultFilter,
    address: Address = .{ .u = .Repeat, .v = .Repeat },
};

pub fn sample2D_1(key: Key, texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) f32 {
    if (!texture.valid()) {
        return texture.uniform1();
    }

    return switch (key.filter) {
        .Nearest => Nearest2D.sample_1(texture, uv, key.address, scene),
        .LinearStochastic => LinearStochastic2D.sample_1(texture, uv, key.address, sampler, scene),
    };
}

pub fn sample2D_2(key: Key, texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) Vec2f {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_2(texture, uv, key.address, scene),
        .LinearStochastic => LinearStochastic2D.sample_2(texture, uv, key.address, sampler, scene),
    };
}

pub fn sample2D_3(key: Key, texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) Vec4f {
    if (!texture.valid()) {
        return texture.uniform3();
    }

    return switch (key.filter) {
        .Nearest => Nearest2D.sample_3(texture, uv, key.address, scene),
        .LinearStochastic => LinearStochastic2D.sample_3(texture, uv, key.address, sampler, scene),
    };
}

pub fn sample3D_1(key: Key, texture: Texture, uvw: Vec4f, sampler: *Sampler, scene: *const Scene) f32 {
    return switch (key.filter) {
        .Nearest => Nearest3D.sample_1(texture, uvw, key.address, scene),
        .LinearStochastic => LinearStochastic3D.sample_1(texture, uvw, key.address, sampler, scene),
    };
}

pub fn sample3D_2(key: Key, texture: Texture, uvw: Vec4f, sampler: *Sampler, scene: *const Scene) Vec2f {
    return switch (key.filter) {
        .Nearest => Nearest3D.sample_2(texture, uvw, key.address, scene),
        .LinearStochastic => LinearStochastic3D.sample_2(texture, uvw, key.address, sampler, scene),
    };
}

const Nearest2D = struct {
    pub fn sample_1(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, adr);
        return texture.image2D_1(m[0], m[1], scene);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, adr);
        return texture.image2D_2(m[0], m[1], scene);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, adr: Address, scene: *const Scene) Vec4f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, adr);
        return texture.image2D_3(m[0], m[1], scene);
    }

    fn map(d: Vec2i, uv: Vec2f, adr: Address) Vec2i {
        const df: Vec2f = @floatFromInt(d);

        const u = adr.u.f(uv[0]);
        const v = adr.v.f(uv[1]);

        const b = d - @as(Vec2i, @splat(1));

        return .{
            @min(@as(i32, @intFromFloat(u * df[0])), b[0]),
            @min(@as(i32, @intFromFloat(v * df[1])), b[1]),
        };
    }
};

const LinearStochastic2D = struct {
    pub fn sample_1(texture: Texture, uv: Vec2f, adr: Address, sampler: *Sampler, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, adr, sampler);
        return texture.image2D_1(m[0], m[1], scene);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, adr: Address, sampler: *Sampler, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, adr, sampler);
        return texture.image2D_2(m[0], m[1], scene);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, adr: Address, sampler: *Sampler, scene: *const Scene) Vec4f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, adr, sampler);
        return texture.image2D_3(m[0], m[1], scene);
    }

    fn map(d: Vec2i, uv: Vec2f, adr: Address, sampler: *Sampler) Vec2i {
        const df: Vec2f = @floatFromInt(d);
        const muv = adr.address2(uv) * df - @as(Vec2f, @splat(0.5));
        const fuv = @floor(muv);
        const w = muv - fuv;
        const omw = @as(Vec2f, @splat(1.0)) - w;

        var xy: Vec2i = @intFromFloat(fuv);

        const r = sampler.sample1D();

        var index: i32 = 0;

        var threshold = omw[0] * omw[1];
        index += @intFromBool(r > threshold);

        threshold += w[0] * omw[1];
        index += @intFromBool(r > threshold);

        threshold += omw[0] * w[1];
        index += @intFromBool(r > threshold);

        xy[0] += index & 1;
        xy[1] += (index & 2) >> 1;

        return adr.coord2(xy, d);
    }
};

const Nearest3D = struct {
    pub fn sample_1(texture: Texture, uvw: Vec4f, adr: Address, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr);
        return texture.image3D_1(m[0], m[1], m[2], scene);
    }

    pub fn sample_2(texture: Texture, uvw: Vec4f, adr: Address, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr);
        return texture.image3D_2(m[0], m[1], m[2], scene);
    }

    fn map(d: Vec4i, uvw: Vec4f, adr: Address) Vec4i {
        const df: Vec4f = @floatFromInt(d);
        const muvw = adr.u.f3(uvw);
        return @min(@as(Vec4i, @intFromFloat(muvw * df)), d - Vec4i{ 1, 1, 1, 0 });
    }
};

const LinearStochastic3D = struct {
    pub fn sample_1(texture: Texture, uvw: Vec4f, adr: Address, sampler: *Sampler, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr, sampler);
        return texture.image3D_1(m[0], m[1], m[2], scene);
    }

    pub fn sample_2(texture: Texture, uvw: Vec4f, adr: Address, sampler: *Sampler, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, adr, sampler);
        return texture.image3D_2(m[0], m[1], m[2], scene);
    }

    fn map(d: Vec4i, uvw: Vec4f, adr: Address, sampler: *Sampler) Vec4i {
        const df: Vec4f = @floatFromInt(d);
        const muvw = adr.u.f3(uvw) * df - Vec4f{ 0.5, 0.5, 0.5, 0.0 };
        const fuvw = @floor(muvw);
        const w = muvw - fuvw;
        const omw = @as(Vec4f, @splat(1.0)) - w;

        var xyz: Vec4i = @intFromFloat(fuvw);

        const r = sampler.sample1D();

        var index: i32 = 0;

        var threshold = omw[0] * omw[1] * omw[2];
        index += @intFromBool(r > threshold);

        threshold += w[0] * omw[1] * omw[2];
        index += @intFromBool(r > threshold);

        threshold += omw[0] * w[1] * omw[2];
        index += @intFromBool(r > threshold);

        threshold += w[0] * w[1] * omw[2];
        index += @intFromBool(r > threshold);

        threshold += omw[0] * omw[1] * w[2];
        index += @intFromBool(r > threshold);

        threshold += w[0] * omw[1] * w[2];
        index += @intFromBool(r > threshold);

        threshold += omw[0] * w[1] * w[2];
        index += @intFromBool(r > threshold);

        xyz[0] += index & 1;
        xyz[1] += (index & 2) >> 1;
        xyz[2] += (index & 4) >> 2;

        return adr.u.coord3(xyz, d);
    }
};
