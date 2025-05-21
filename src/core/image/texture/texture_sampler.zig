const Texture = @import("texture.zig").Texture;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Context = @import("../../scene/context.zig").Context;
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;
const Scene = @import("../../scene/scene.zig").Scene;

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn sampleImage2D_1(texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) f32 {
    return switch (texture.mode.filter) {
        .Nearest => Nearest2D.sample_1(texture, uv, scene),
        .LinearStochastic => LinearStochastic2D.sample_1(texture, uv, sampler, scene),
    };
}

pub fn sample2D_1(texture: Texture, rs: Renderstate, sampler: *Sampler, context: Context) f32 {
    switch (texture.type) {
        .Uniform => return texture.uniform1(),
        .Procedural => return context.sampleProcedural2D_1(texture, rs, sampler),
        else => {
            const uv = if (.Triplanar == texture.mode.uv_set) rs.triplanarUv() else rs.uv();

            return switch (texture.mode.filter) {
                .Nearest => Nearest2D.sample_1(texture, uv, context.scene),
                .LinearStochastic => LinearStochastic2D.sample_1(texture, uv, sampler, context.scene),
            };
        },
    }
}

pub fn sample2D_2(texture: Texture, rs: Renderstate, sampler: *Sampler, context: Context) Vec2f {
    switch (texture.type) {
        .Uniform => return texture.uniform2(),
        .Procedural => return context.sampleProcedural2D_2(texture, rs, sampler),
        else => {
            const uv = if (.Triplanar == texture.mode.uv_set) rs.triplanarUv() else rs.uv();

            return switch (texture.mode.filter) {
                .Nearest => Nearest2D.sample_2(texture, uv, context.scene),
                .LinearStochastic => LinearStochastic2D.sample_2(texture, uv, sampler, context.scene),
            };
        },
    }
}

pub fn sampleImage2D_3(texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) Vec4f {
    return switch (texture.mode.filter) {
        .Nearest => Nearest2D.sample_3(texture, uv, scene),
        .LinearStochastic => LinearStochastic2D.sample_3(texture, uv, sampler, scene),
    };
}

pub fn sample2D_3(texture: Texture, rs: Renderstate, sampler: *Sampler, context: Context) Vec4f {
    switch (texture.type) {
        .Uniform => return texture.uniform3(),
        .Procedural => return context.sampleProcedural2D_3(texture, rs, sampler),
        else => {
            const uv = if (.Triplanar == texture.mode.uv_set) rs.triplanarUv() else rs.uv();

            return switch (texture.mode.filter) {
                .Nearest => Nearest2D.sample_3(texture, uv, context.scene),
                .LinearStochastic => LinearStochastic2D.sample_3(texture, uv, sampler, context.scene),
            };
        },
    }
}

pub fn sample3D_1(texture: Texture, uvw: Vec4f, sampler: *Sampler, context: Context) f32 {
    return switch (texture.mode.filter) {
        .Nearest => Nearest3D.sample_1(texture, uvw, context.scene),
        .LinearStochastic => LinearStochastic3D.sample_1(texture, uvw, sampler, context.scene),
    };
}

pub fn sample3D_2(texture: Texture, uvw: Vec4f, sampler: *Sampler, context: Context) Vec2f {
    return switch (texture.mode.filter) {
        .Nearest => Nearest3D.sample_2(texture, uvw, context.scene),
        .LinearStochastic => LinearStochastic3D.sample_2(texture, uvw, sampler, context.scene),
    };
}

const Nearest2D = struct {
    pub fn sample_1(texture: Texture, uv: Vec2f, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, texture.mode);
        return texture.image2D_1(m[0], m[1], scene);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, texture.mode);
        return texture.image2D_2(m[0], m[1], scene);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, scene: *const Scene) Vec4f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, texture.mode);
        return texture.image2D_3(m[0], m[1], scene);
    }

    fn map(d: Vec2i, uv: Vec2f, mode: Texture.Mode) Vec2i {
        const df: Vec2f = @floatFromInt(d);

        const u = mode.u.f(uv[0]);
        const v = mode.v.f(uv[1]);

        const b = d - @as(Vec2i, @splat(1));

        return .{
            @min(@as(i32, @intFromFloat(u * df[0])), b[0]),
            @min(@as(i32, @intFromFloat(v * df[1])), b[1]),
        };
    }
};

const LinearStochastic2D = struct {
    pub fn sample_1(texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, texture.mode, sampler);
        return texture.image2D_1(m[0], m[1], scene);
    }

    pub fn sample_2(texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, texture.mode, sampler);
        return texture.image2D_2(m[0], m[1], scene);
    }

    pub fn sample_3(texture: Texture, uv: Vec2f, sampler: *Sampler, scene: *const Scene) Vec4f {
        const d = texture.description(scene).dimensions;
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * uv, texture.mode, sampler);
        return texture.image2D_3(m[0], m[1], scene);
    }

    fn map(d: Vec2i, uv: Vec2f, mode: Texture.Mode, sampler: *Sampler) Vec2i {
        const df: Vec2f = @floatFromInt(d);
        const muv = mode.address2(uv) * df - @as(Vec2f, @splat(0.5));
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

        return mode.coord2(xy, d);
    }
};

const Nearest3D = struct {
    pub fn sample_1(texture: Texture, uvw: Vec4f, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, texture.mode);
        return texture.image3D_1(m[0], m[1], m[2], scene);
    }

    pub fn sample_2(texture: Texture, uvw: Vec4f, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, texture.mode);
        return texture.image3D_2(m[0], m[1], m[2], scene);
    }

    fn map(d: Vec4i, uvw: Vec4f, mode: Texture.Mode) Vec4i {
        const df: Vec4f = @floatFromInt(d);
        const muvw = mode.u.f3(uvw);
        return @min(@as(Vec4i, @intFromFloat(muvw * df)), d - Vec4i{ 1, 1, 1, 0 });
    }
};

const LinearStochastic3D = struct {
    pub fn sample_1(texture: Texture, uvw: Vec4f, sampler: *Sampler, scene: *const Scene) f32 {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, texture.mode, sampler);
        return texture.image3D_1(m[0], m[1], m[2], scene);
    }

    pub fn sample_2(texture: Texture, uvw: Vec4f, sampler: *Sampler, scene: *const Scene) Vec2f {
        const d = texture.description(scene).dimensions;
        const m = map(d, uvw, texture.mode, sampler);
        return texture.image3D_2(m[0], m[1], m[2], scene);
    }

    fn map(d: Vec4i, uvw: Vec4f, mode: Texture.Mode, sampler: *Sampler) Vec4i {
        const df: Vec4f = @floatFromInt(d);
        const muvw = mode.u.f3(uvw) * df - Vec4f{ 0.5, 0.5, 0.5, 0.0 };
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

        return mode.u.coord3(xyz, d);
    }
};
