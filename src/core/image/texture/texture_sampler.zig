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
    Linear_stochastic,
};

pub const Default_filter = Filter.Linear_stochastic;

pub const Key = struct {
    filter: Filter = Default_filter,
    address: Address = .{ .u = .Repeat, .v = .Repeat },
};

pub fn sample2D_1(key: Key, texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) f32 {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_1(texture, uv, key.address, scene),
        .Linear_stochastic => LinearStochastic2D.sample_1(texture, uv, key.address, sampler, scene),
    };
}

pub fn sample2D_2(key: Key, texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) Vec2f {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_2(texture, uv, key.address, scene),
        .Linear_stochastic => LinearStochastic2D.sample_2(texture, uv, key.address, sampler, scene),
    };
}

pub fn sample2D_3(key: Key, texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) Vec4f {
    return switch (key.filter) {
        .Nearest => Nearest2D.sample_3(texture, uv, key.address, scene),
        .Linear_stochastic => LinearStochastic2D.sample_3(texture, uv, key.address, sampler, scene),
    };
}

pub fn sample3D_1(key: Key, texture: Texture, uvw: Vec4f, sampler: *Sampler, scene: *const Scene) f32 {
    return switch (key.filter) {
        .Nearest => Nearest3D.sample_1(texture, uvw, key.address, scene),
        .Linear_stochastic => LinearStochastic3D.sample_1(texture, uvw, key.address, sampler, scene),
    };
}

pub fn sample3D_2(key: Key, texture: Texture, uvw: Vec4f, sampler: *Sampler, scene: *const Scene) Vec2f {
    return switch (key.filter) {
        .Nearest => Nearest3D.sample_2(texture, uvw, key.address, scene),
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
            @min(@intFromFloat(i32, u * df[0]), b[0]),
            @min(@intFromFloat(i32, v * df[1]), b[1]),
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
        const muv = Vec2f{ adr.u.f(uv[0]), adr.v.f(uv[1]) } * df - @splat(2, @as(f32, 0.5));
        const fuv = @floor(muv);
        var xy = math.vec2fTo2i(fuv);

        // const b = d - @splat(2, @as(i32, 1));
        const w = muv - fuv;
        // const r = sampler.sample2D();
        // const c = r <= w;

        // return .{
        //     if (c[0]) adr.u.increment(xy[0], b[0]) else adr.u.lowerBound(xy[0], b[0]),
        //     if (c[1]) adr.v.increment(xy[1], b[1]) else adr.v.lowerBound(xy[1], b[1]),
        // };

        // return .{
        //     adr.u.offset(xy[0], @boolToInt(c[0]), b[0]),
        //     adr.v.offset(xy[1], @boolToInt(c[1]), b[1]),
        // };

        // return adr.u.offset2(xy, @select(i32, c, @splat(2, @as(i32, 1)), @splat(2, @as(i32, 0))), d);

        var r = sampler.sample1D();

        if (r < w[0]) {
            xy[0] += 1;
            r /= w[0];
        } else {
            r = (r - w[0]) / (1.0 - w[0]);
        }

        if (r < w[1]) {
            xy[1] += 1;
            // u /= w[1];
        } // else {
        //     u = (u - w[1]) / (1.0 - w[1]);
        // }

        return .{ adr.u.coord(xy[0], d[0]), adr.v.coord(xy[1], d[1]) };
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
        return @min(math.vec4fTo4i(muvw * df), d - Vec4i{ 1, 1, 1, 0 });
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
        var xyz = math.vec4fTo4i(fuvw);

        const w = muvw - fuvw;
        const r = sampler.sample3D();
        const c = r < w;

        // return .{
        //     if (c[0]) adr.u.increment(xyz[0], b[0]) else adr.u.lowerBound(xyz[0], b[0]),
        //     if (c[1]) adr.u.increment(xyz[1], b[1]) else adr.u.lowerBound(xyz[1], b[1]),
        //     if (c[2]) adr.u.increment(xyz[2], b[2]) else adr.u.lowerBound(xyz[2], b[2]),
        //     0,
        // };

        // return .{
        //     adr.u.offset(xyz[0], @boolToInt(c[0]), b[0]),
        //     adr.u.offset(xyz[1], @boolToInt(c[1]), b[1]),
        //     adr.u.offset(xyz[2], @boolToInt(c[2]), b[2]),
        //     0,
        // };

        return adr.u.coord3(xyz + @select(i32, c, @splat(4, @as(i32, 1)), @splat(4, @as(i32, 0))), d);

        // var r = sampler.sample1D();

        // if (r < w[0]) {
        //     xyz[0] += 1;
        //     r /= w[0];
        // } else {
        //     r = (r - w[0]) / (1.0 - w[0]);
        // }

        // if (r < w[1]) {
        //     xyz[1] += 1;
        //     r /= w[1];
        // } else {
        //     r = (r - w[1]) / (1.0 - w[1]);
        // }

        // if (r < w[2]) {
        //     xyz[2] += 1;
        // }

        // return adr.u.coord3(xyz, d);
    }
};
