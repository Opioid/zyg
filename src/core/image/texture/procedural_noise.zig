const ts = @import("texture_sampler.zig");
const UvSet = @import("texture.zig").Texture.UvSet;
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

    class: Class,

    levels: u32,

    attenuation: f32,

    contrast: f32,

    scale: Vec4f,

    pub fn evaluate1(self: Noise, rs: Renderstate, uv_set: UvSet) f32 {
        const uv = if (.Triplanar == uv_set) rs.triplanarUv() else rs.uv();

        const att = self.attenuation;

        var weight: f32 = 0.0;
        var freq: f32 = 1.0;
        var scale: Vec2f = .{ self.scale[0], self.scale[1] };

        var value: f32 = 0.0;

        for (0..self.levels) |_| {
            const local_weight = std.math.pow(f32, freq, att);
            value += perlin2D_1((uv) * scale) * local_weight;

            weight += local_weight;
            freq *= 0.5;
            scale *= @splat(2.0);
        }

        //const unsigned = @abs(value / weight);
        const unsigned = ((value / weight) + 1.0) * 0.5;

        return math.saturate((unsigned - 0.5) * self.contrast + 0.5);
    }

    pub fn evaluate3(self: Noise, rs: Renderstate, uv_set: UvSet) Vec4f {
        const noise = self.evaluate1(rs, uv_set);

        return @splat(noise);
    }

    fn perlin2D_1(p: Vec2f) f32 {
        const fx, const X = floorfrac(p[0]);
        const fy, const Y = floorfrac(p[1]);

        const u = fade(fx);
        const v = fade(fy);

        const c = [_]f32{
            gradient(hash2(X, Y), fx, fy),
            gradient(hash2(X + 1, Y), fx - 1.0, fy),
            gradient(hash2(X, Y + 1), fx, fy - 1.0),
            gradient(hash2(X + 1, Y + 1), fx - 1.0, fy - 1.0),
        };

        return gradient_scale2D(math.bilinear(f32, c, u, v));
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
    fn gradient(hash: u32, x: f32, y: f32) f32 {
        // 8 possible directions (+-1,+-2) and (+-2,+-1)
        const h = hash & 7;
        const u = if (h < 4) x else y;
        const v = 2.0 * if (h < 4) y else x;
        // compute the dot product with (x,y).
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
};
