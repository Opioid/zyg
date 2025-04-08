const ts = @import("texture_sampler.zig");
const TexCoordMode = @import("texture.zig").Texture.TexCoordMode;
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;
const hlp = @import("../../scene/material/material_helper.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

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
        var freq: f32 = 1.0;

        var value: f32 = 0.0;

        if (.ObjectPos == uv_set) {
            var scale = self.scale;

            const uvw = rs.trafo.worldToObjectPoint(rs.p);

            for (0..self.levels) |_| {
                const local_weight = std.math.pow(f32, freq, att);
                value += perlin3D_1(uvw * scale) * local_weight;

                weight += local_weight;
                freq *= 0.5;
                scale *= @splat(2.0);
            }
        } else {
            var scale: Vec2f = .{ self.scale[0], self.scale[1] };

            const uv = if (.Triplanar == uv_set) rs.triplanarUv() else rs.uv();

            for (0..self.levels) |_| {
                const local_weight = std.math.pow(f32, freq, att);
                value += perlin2D_1((uv) * scale) * local_weight;

                weight += local_weight;
                freq *= 0.5;
                scale *= @splat(2.0);
            }
        }

        value /= weight;

        const unsigned = (if (self.flags.absolute) @abs(value) else (value + 1.0) * 0.5);

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

    fn perlin2D_1(p: Vec2f) f32 {
        const fx, const X = floorfrac(p[0]);
        const fy, const Y = floorfrac(p[1]);

        const u = fade(fx);
        const v = fade(fy);

        const c = [_]f32{
            gradient2(hash2(X, Y), fx, fy),
            gradient2(hash2(X + 1, Y), fx - 1.0, fy),
            gradient2(hash2(X, Y + 1), fx, fy - 1.0),
            gradient2(hash2(X + 1, Y + 1), fx - 1.0, fy - 1.0),
        };

        return gradient_scale2D(math.bilinear(f32, c, u, v));
    }

    fn perlin3D_1(p: Vec4f) f32 {
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

    fn floorfrac(x: f32) struct { f32, u32 } {
        const flx = @floor(x);
        return .{ x - flx, @bitCast(@as(i32, @intFromFloat(flx))) };
    }

    // Perlin 'fade' function.
    fn fade(t: f32) f32 {
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
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

    fn gradient3(hash: u32, x: f32, y: f32, z: f32) f32 {
        // use vectors pointing to the edges of the cube
        const h = hash & 15;
        const u = if (h < 8) x else y;
        const v = if (h < 4) y else (if (h == 12 or h == 14) x else z);

        return negate_if(u, 0 != (h & 1)) + negate_if(v, 0 != (h & 2));
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

    fn hash3(x: u32, y: u32, z: u32) u32 {
        const start_val: u32 = 0xdeadbeef + (3 << 2) + 13;
        const a = start_val + x;
        const b = start_val + y;
        const c = start_val + z;

        return bjfinal(a, b, c);
    }

    // Mix up and combine the bits of a, b, and c (doesn't change them, but
    // returns a hash of those three original values).
    fn bjfinal(a_in: u32, b_in: u32, c_in: u32) u32 {
        var a = a_in;
        var b = b_in;
        var c = c_in;

        c ^= b;
        c -%= std.math.rotl(u32, b, 14);
        a ^= c;
        a -%= std.math.rotl(u32, c, 11);
        b ^= a;
        b -%= std.math.rotl(u32, a, 25);
        c ^= b;
        c -%= std.math.rotl(u32, b, 16);
        a ^= c;
        a -%= std.math.rotl(u32, c, 4);
        b ^= a;
        b -%= std.math.rotl(u32, a, 14);
        c ^= b;
        c -%= std.math.rotl(u32, b, 24);
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
