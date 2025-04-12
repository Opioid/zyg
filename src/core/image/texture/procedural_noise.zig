const ts = @import("texture_sampler.zig");
const TexCoordMode = @import("texture.zig").Texture.TexCoordMode;
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;
const hlp = @import("../../scene/material/material_helper.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec2i = math.Vec2i;
const Vec2u = math.Vec2u;
const Vec4f = math.Vec4f;
const Vec4i = math.Vec4i;
const Vec4u = math.Vec4u;

const std = @import("std");

pub const Noise = struct {
    pub const Class = enum {
        Perlin,
        Cell,
    };

    pub const Flags = packed struct {
        absolute: bool,
        invert: bool,
    };

    class: Class,

    flags: Flags,

    levels: u32,

    attenuation: f32,
    ratio: f32,
    transition: f32,

    scale: Vec4f,

    pub fn evaluate1(self: Noise, rs: Renderstate, uv_set: TexCoordMode) f32 {
        const att = self.attenuation;

        var weight: f32 = 0.0;
        var amplitude: f32 = 1.0;

        var value: f32 = 0.0;

        if (.ObjectPos == uv_set) {
            var scale = self.scale;

            const uvw = rs.trafo.worldToObjectPoint(rs.p);

            for (0..self.levels) |_| {
                const local_weight = std.math.pow(f32, amplitude, att);
                value += perlin3D_1(uvw * scale) * local_weight;

                weight += local_weight;
                amplitude *= 0.5;
                scale *= @splat(2.0);
            }
        } else {
            var scale: Vec2f = .{ self.scale[0], self.scale[1] };

            const uv = if (.Triplanar == uv_set) rs.triplanarUv() else rs.uv();

            for (0..self.levels) |_| {
                const local_weight = std.math.pow(f32, amplitude, att);
                value += perlin2D_1(uv * scale) * local_weight;

                weight += local_weight;
                amplitude *= 0.5;
                scale *= @splat(2.0);
            }
        }

        value /= weight;

        const unsigned = if (self.flags.absolute) @abs(value) else (value + 1.0) * 0.5;

        const a = self.ratio - self.transition;
        const b = self.ratio + self.transition;

        const result = math.saturate((unsigned - a) / (b - a));
        //  const result = math.smoothstep(remapped_noise);

        return if (self.flags.invert) (1.0 - result) else result;
    }

    pub fn evaluate3(self: Noise, rs: Renderstate, uv_set: TexCoordMode) Vec4f {
        const noise = self.evaluate1(rs, uv_set);

        return @splat(noise);
    }

    fn scalarPerlin2D_1(p: Vec2f) f32 {
        const fx, const X = floorfrac(p[0]);
        const fy, const Y = floorfrac(p[1]);

        const u = fade(f32, fx);
        const v = fade(f32, fy);

        const c = [_]f32{
            gradient2(hash2(X, Y), fx, fy),
            gradient2(hash2(X + 1, Y), fx - 1.0, fy),
            gradient2(hash2(X, Y + 1), fx, fy - 1.0),
            gradient2(hash2(X + 1, Y + 1), fx - 1.0, fy - 1.0),
        };

        return gradient_scale2D(math.bilinear(f32, c, u, v));
    }

    fn perlin2D_1(p: Vec2f) f32 {
        const fp, const P = floorfrac2(p);

        const uv = fade(Vec2f, fp);

        const P0: Vec4u = .{ P[0], P[0] +% 1, P[0], P[0] +% 1 };
        const P1: Vec4u = .{ P[1], P[1], P[1] +% 1, P[1] +% 1 };

        const fp0: Vec4f = .{ fp[0], fp[0] - 1.0, fp[0], fp[0] - 1.0 };
        const fp1: Vec4f = .{ fp[1], fp[1], fp[1] - 1.0, fp[1] - 1.0 };

        const hash = hash2v(P0, P1);

        const c = gradient2v(hash, fp0, fp1);

        return gradient_scale2D(math.bilinear(f32, c, uv[0], uv[1]));
    }

    fn scalarPerlin3D_1(p: Vec4f) f32 {
        const fx, const X = floorfrac(p[0]);
        const fy, const Y = floorfrac(p[1]);
        const fz, const Z = floorfrac(p[2]);

        const u = fade(fx);
        const v = fade(fy);
        const w = fade(fz);

        const c0 = [_]f32{
            gradient3(hash3(X, Y, Z), fx, fy, fz),
            gradient3(hash3(X + 1, Y, Z), fx - 1.0, fy, fz),
            gradient3(hash3(X, Y + 1, Z), fx, fy - 1.0, fz),
            gradient3(hash3(X + 1, Y + 1, Z), fx - 1.0, fy - 1.0, fz),
        };

        const result0 = math.bilinear(f32, c0, u, v);

        const c1 = [_]f32{
            gradient3(hash3(X, Y, Z + 1), fx, fy, fz - 1.0),
            gradient3(hash3(X + 1, Y, Z + 1), fx - 1.0, fy, fz - 1.0),
            gradient3(hash3(X, Y + 1, Z + 1), fx, fy - 1.0, fz - 1.0),
            gradient3(hash3(X + 1, Y + 1, Z + 1), fx - 1.0, fy - 1.0, fz - 1.0),
        };

        const result1 = math.bilinear(f32, c1, u, v);

        return gradient_scale3D(math.lerp(result0, result1, w));
    }

    fn perlin3D_1(p: Vec4f) f32 {
        const fp, const P = floorfrac3(p);

        const uvw = fade(Vec4f, fp);

        const P0: Vec4u = .{ P[0], P[0] + 1, P[0], P[0] + 1 };
        const P1: Vec4u = .{ P[1], P[1], P[1] + 1, P[1] + 1 };

        const fp0: Vec4f = .{ fp[0], fp[0] - 1.0, fp[0], fp[0] - 1.0 };
        const fp1: Vec4f = .{ fp[1], fp[1], fp[1] - 1.0, fp[1] - 1.0 };

        const hash = hash3v(P0, P1, @splat(P[2]));

        const c0 = gradient3v(hash[0], fp0, fp1, @splat(fp[2]));
        const c1 = gradient3v(hash[1], fp0, fp1, @splat(fp[2] - 1.0));

        const cc = [_]Vec2f{ .{ c0[0], c1[0] }, .{ c0[1], c1[1] }, .{ c0[2], c1[2] }, .{ c0[3], c1[3] } };

        const result = math.bilinear(Vec2f, cc, uvw[0], uvw[1]);

        return gradient_scale3D(math.lerp(result[0], result[1], uvw[2]));
    }

    fn floorfrac(x: f32) struct { f32, u32 } {
        const flx = @floor(x);
        return .{ x - flx, @bitCast(@as(i32, @intFromFloat(flx))) };
    }

    fn floorfrac2(v: Vec2f) struct { Vec2f, Vec2u } {
        const flv = @floor(v);
        return .{ v - flv, @bitCast(@as(Vec2i, @intFromFloat(flv))) };
    }

    fn floorfrac3(v: Vec4f) struct { Vec4f, Vec4u } {
        const flv = @floor(v);
        return .{ v - flv, @bitCast(@as(Vec4i, @intFromFloat(flv))) };
    }

    // Perlin 'fade' function.
    fn fade(comptime T: type, t: T) T {
        return switch (@typeInfo(T)) {
            .float => t * t * t * (t * (t * 6.0 - 15.0) + 10.0),
            .vector => t * t * t * (t * (t * @as(T, @splat(6.0)) - @as(T, @splat(15.0))) + @as(T, @splat(10.0))),
            else => comptime unreachable,
        };
    }

    // 2 and 3 dimensional gradient functions - perform a dot product against a
    // randomly chosen vector. Note that the gradient vector is not normalized, but
    // this only affects the overall "scale" of the result, so we simply account for
    // the scale by multiplying in the corresponding "perlin" function.
    fn gradient2(hash: u32, x: f32, y: f32) f32 {
        // 8 possible directions (+-1,+-2) and (+-2,+-1)
        const h = hash & 7;
        const u = if (h < 4) x else y;
        const v = 2.0 * if (h < 4) y else x;
        // compute the dot product with (x,y).
        return negate_if(u, 0 != (h & 1)) + negate_if(v, 0 != (h & 2));
    }

    fn gradient2v(hash: Vec4u, x: Vec4f, y: Vec4f) Vec4f {
        // 8 possible directions (+-1,+-2) and (+-2,+-1)
        const h = hash & @as(Vec4u, @splat(7));
        const u = @select(f32, h < @as(Vec4u, @splat(4)), x, y);
        const v = @as(Vec4f, @splat(2.0)) * @select(f32, h < @as(Vec4u, @splat(4)), y, x);
        // compute the dot product with (x,y).
        return @select(f32, @as(Vec4u, @splat(0)) != (h & @as(Vec4u, @splat(1))), -u, u) + @select(f32, @as(Vec4u, @splat(0)) != (h & @as(Vec4u, @splat(2))), -v, v);
    }

    fn gradient3(hash: u32, x: f32, y: f32, z: f32) f32 {
        // use vectors pointing to the edges of the cube
        const h = hash & 15;
        const u = if (h < 8) x else y;
        const v = if (h < 4) y else (if (h == 12 or h == 14) x else z);

        return negate_if(u, 0 != (h & 1)) + negate_if(v, 0 != (h & 2));
    }

    fn gradient3v(hash: Vec4u, x: Vec4f, y: Vec4f, z: Vec4f) Vec4f {
        // use vectors pointing to the edges of the cube
        const h = hash & @as(Vec4u, @splat(15));
        const u = @select(f32, h < @as(Vec4u, @splat(8)), x, y);

        const a: Vec4u = @intFromBool(h == @as(Vec4u, @splat(12)));
        const b: Vec4u = @intFromBool(h == @as(Vec4u, @splat(14)));

        const t = @select(f32, @as(Vec4u, @splat(0)) != (a | b), x, z);
        const v = @select(f32, h < @as(Vec4u, @splat(4)), y, t);

        return @select(f32, @as(Vec4u, @splat(0)) != (h & @as(Vec4u, @splat(1))), -u, u) + @select(f32, @as(Vec4u, @splat(0)) != (h & @as(Vec4u, @splat(2))), -v, v);
    }

    fn negate_if(val: f32, b: bool) f32 {
        return if (b) -val else val;
    }

    fn hash2(x: u32, y: u32) u32 {
        const start_val: u32 = 0xdeadbeef + (2 << 2) + 13;
        const a = start_val + x;
        const b = start_val + y;

        return bjfinal(a, b, start_val);
    }

    fn hash2v(x: Vec4u, y: Vec4u) Vec4u {
        const start_val: Vec4u = @splat(0xdeadbeef + (2 << 2) + 13);
        const a = start_val +% x;
        const b = start_val +% y;

        return bjfinal(a, b, start_val);
    }

    fn hash3(x: u32, y: u32, z: u32) u32 {
        const start_val: u32 = 0xdeadbeef + (3 << 2) + 13;
        const a = start_val + x;
        const b = start_val + y;
        const c = start_val + z;

        return bjfinal(a, b, c);
    }

    fn hash3v(x: Vec4u, y: Vec4u, z: Vec4u) [2]Vec4u {
        const start_val: Vec4u = @splat(0xdeadbeef + (3 << 2) + 13);
        const a = start_val + x;
        const b = start_val + y;
        const c = start_val + z;

        return .{ bjfinal(a, b, c), bjfinal(a, b, c + @as(Vec4u, @splat(1))) };
    }

    // Mix up and combine the bits of a, b, and c (doesn't change them, but
    // returns a hash of those three original values).
    fn bjfinal(a_in: anytype, b_in: anytype, c_in: anytype) @TypeOf(a_in, b_in, c_in) {
        var a = a_in;
        var b = b_in;
        var c = c_in;

        c ^= b;
        c -%= std.math.rotl(@TypeOf(a_in), b, 14);
        a ^= c;
        a -%= std.math.rotl(@TypeOf(a_in), c, 11);
        b ^= a;
        b -%= std.math.rotl(@TypeOf(a_in), a, 25);
        c ^= b;
        c -%= std.math.rotl(@TypeOf(a_in), b, 16);
        a ^= c;
        a -%= std.math.rotl(@TypeOf(a_in), c, 4);
        b ^= a;
        b -%= std.math.rotl(@TypeOf(a_in), a, 14);
        c ^= b;
        c -%= std.math.rotl(@TypeOf(a_in), b, 24);
        return c;
    }

    // Scaling factors to normalize the result of gradients above.
    // These factors were experimentally calculated to be:
    //    2D:   0.6616
    //    3D:   0.9820
    fn gradient_scale2D(v: f32) f32 {
        return 0.6616 * v;
    }

    fn gradient_scale3D(v: f32) f32 {
        return 0.9820 * v;
    }
};
