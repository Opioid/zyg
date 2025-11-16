const Texture = @import("texture.zig").Texture;
const Sampler = @import("../sampler/sampler.zig").Sampler;
const Context = @import("../scene/context.zig").Context;
const Renderstate = @import("../scene/renderstate.zig").Renderstate;
const Scene = @import("../scene/scene.zig").Scene;

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn sampleImage2D_1(texture: Texture, st: Vec2f, r: f32, scene: *const Scene) f32 {
    return switch (texture.mode.filter) {
        .Nearest => Nearest2D.sample_1(texture, st, scene),
        .LinearStochastic => LinearStochastic2D.sample_1(texture, st, r, scene),
    };
}

pub fn sample2D_1(texture: Texture, rs: Renderstate, sampler: *Sampler, context: Context) f32 {
    switch (texture.type) {
        .Uniform => return texture.uniform1(),
        .Procedural => return context.sampleProcedural2D_1(texture, rs, sampler),
        else => {
            const st = if (.Triplanar == texture.mode.tex_coord) rs.triplanarSt() else rs.uv();

            return switch (texture.mode.filter) {
                .Nearest => Nearest2D.sample_1(texture, st, context.scene),
                .LinearStochastic => LinearStochastic2D.sample_1(texture, st, rs.stochastic_r, context.scene),
            };
        },
    }
}

pub fn sample2D_2(texture: Texture, rs: Renderstate, sampler: *Sampler, context: Context) Vec2f {
    switch (texture.type) {
        .Uniform => return texture.uniform2(),
        .Procedural => return context.sampleProcedural2D_2(texture, rs, sampler),
        else => {
            const st = if (.Triplanar == texture.mode.tex_coord) rs.triplanarSt() else rs.uv();

            return switch (texture.mode.filter) {
                .Nearest => Nearest2D.sample_2(texture, st, context.scene),
                .LinearStochastic => LinearStochastic2D.sample_2(texture, st, rs.stochastic_r, context.scene),
            };
        },
    }
}

pub fn sampleImage2D_3(texture: Texture, st: Vec2f, r: f32, scene: *const Scene) Vec4f {
    return switch (texture.mode.filter) {
        .Nearest => Nearest2D.sample_3(texture, st, scene),
        .LinearStochastic => LinearStochastic2D.sample_3(texture, st, r, scene),
    };
}

pub fn sampleImageNearest2D_3(texture: Texture, st: Vec2f, scene: *const Scene) Vec4f {
    return Nearest2D.sample_3(texture, st, scene);
}

pub fn sample2D_3(texture: Texture, rs: Renderstate, sampler: *Sampler, context: Context) Vec4f {
    switch (texture.type) {
        .Uniform => return texture.uniform3(),
        .Procedural => return context.sampleProcedural2D_3(texture, rs, sampler),
        else => {
            const st = if (.Triplanar == texture.mode.tex_coord) rs.triplanarSt() else rs.uv();

            return switch (texture.mode.filter) {
                .Nearest => Nearest2D.sample_3(texture, st, context.scene),
                .LinearStochastic => LinearStochastic2D.sample_3(texture, st, rs.stochastic_r, context.scene),
            };
        },
    }
}

pub fn sample3D_1(texture: Texture, sto: Vec4f, r: f32, context: Context) f32 {
    return switch (texture.mode.filter) {
        .Nearest => Nearest3D.sample_1(texture, sto, context.scene),
        .LinearStochastic => LinearStochastic3D.sample_1(texture, sto, r, context.scene),
    };
}

pub fn sample3D_2(texture: Texture, sto: Vec4f, r: f32, context: Context) Vec2f {
    return switch (texture.mode.filter) {
        .Nearest => Nearest3D.sample_2(texture, sto, context.scene),
        .LinearStochastic => LinearStochastic3D.sample_2(texture, sto, r, context.scene),
    };
}

const Nearest2D = struct {
    pub fn sample_1(texture: Texture, st: Vec2f, scene: *const Scene) f32 {
        const d = texture.dimensions(scene);
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * st, texture.mode);
        return texture.image2D_1(m[0], m[1], scene);
    }

    pub fn sample_2(texture: Texture, st: Vec2f, scene: *const Scene) Vec2f {
        const d = texture.dimensions(scene);
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * st, texture.mode);
        return texture.image2D_2(m[0], m[1], scene);
    }

    pub fn sample_3(texture: Texture, st: Vec2f, scene: *const Scene) Vec4f {
        const d = texture.dimensions(scene);
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * st, texture.mode);
        return texture.image2D_3(m[0], m[1], scene);
    }

    fn map(d: Vec2i, st: Vec2f, mode: Texture.Mode) Vec2i {
        const df: Vec2f = @floatFromInt(d);

        const s = mode.u.f(st[0]);
        const t = mode.v.f(st[1]);

        const b = d - @as(Vec2i, @splat(1));

        return .{
            @min(@as(i32, @intFromFloat(s * df[0])), b[0]),
            @min(@as(i32, @intFromFloat(t * df[1])), b[1]),
        };
    }
};

const LinearStochastic2D = struct {
    pub fn sample_1(texture: Texture, st: Vec2f, r: f32, scene: *const Scene) f32 {
        const d = texture.dimensions(scene);
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * st, texture.mode, r);
        return texture.image2D_1(m[0], m[1], scene);
    }

    pub fn sample_2(texture: Texture, st: Vec2f, r: f32, scene: *const Scene) Vec2f {
        const d = texture.dimensions(scene);
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * st, texture.mode, r);
        return texture.image2D_2(m[0], m[1], scene);
    }

    pub fn sample_3(texture: Texture, st: Vec2f, r: f32, scene: *const Scene) Vec4f {
        const d = texture.dimensions(scene);
        const m = map(.{ d[0], d[1] }, texture.data.image.scale * st, texture.mode, r);
        return texture.image2D_3(m[0], m[1], scene);
    }

    fn map(d: Vec2i, st: Vec2f, mode: Texture.Mode, r: f32) Vec2i {
        const df: Vec2f = @floatFromInt(d);
        const mst = mode.address2(st) * df - @as(Vec2f, @splat(0.5));
        const fst = @floor(mst);
        const w = mst - fst;
        const omw = @as(Vec2f, @splat(1.0)) - w;

        var xy: Vec2i = @intFromFloat(fst);

        var index: i32 = 0;

        var threshold = omw[0] * omw[1];
        index += @intFromBool(r > threshold);

        threshold = @mulAdd(f32, w[0], omw[1], threshold);
        index += @intFromBool(r > threshold);

        threshold = @mulAdd(f32, omw[0], w[1], threshold);
        index += @intFromBool(r > threshold);

        xy[0] += index & 1;
        xy[1] += (index & 2) >> 1;

        return mode.coord2(xy, d);
    }
};

const Nearest3D = struct {
    pub fn sample_1(texture: Texture, sto: Vec4f, scene: *const Scene) f32 {
        const d = texture.dimensions(scene);
        const m = map(d, sto, texture.mode);
        return texture.image3D_1(m[0], m[1], m[2], scene);
    }

    pub fn sample_2(texture: Texture, sto: Vec4f, scene: *const Scene) Vec2f {
        const d = texture.dimensions(scene);
        const m = map(d, sto, texture.mode);
        return texture.image3D_2(m[0], m[1], m[2], scene);
    }

    fn map(d: Vec4i, sto: Vec4f, mode: Texture.Mode) Vec4i {
        const df: Vec4f = @floatFromInt(d);
        const msto = mode.u.f3(sto);
        return @min(@as(Vec4i, @intFromFloat(msto * df)), d - Vec4i{ 1, 1, 1, 0 });
    }
};

const LinearStochastic3D = struct {
    pub fn sample_1(texture: Texture, sto: Vec4f, r: f32, scene: *const Scene) f32 {
        const d = texture.dimensions(scene);
        const m = map(d, sto, texture.mode, r);
        return texture.image3D_1(m[0], m[1], m[2], scene);
    }

    pub fn sample_2(texture: Texture, sto: Vec4f, r: f32, scene: *const Scene) Vec2f {
        const d = texture.dimensions(scene);
        const m = map(d, sto, texture.mode, r);
        return texture.image3D_2(m[0], m[1], m[2], scene);
    }

    fn map(d: Vec4i, sto: Vec4f, mode: Texture.Mode, r: f32) Vec4i {
        const df: Vec4f = @floatFromInt(d);
        const msto = mode.u.f3(sto) * df - Vec4f{ 0.5, 0.5, 0.5, 0.0 };
        const fsto = @floor(msto);
        const w = msto - fsto;
        const omw = @as(Vec4f, @splat(1.0)) - w;

        var xyz: Vec4i = @intFromFloat(fsto);

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
