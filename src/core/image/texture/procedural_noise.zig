const ts = @import("texture_sampler.zig");
const TexCoordMode = @import("texture.zig").Texture.TexCoordMode;
const Context = @import("../../scene/context.zig").Context;
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
        Cellular,
        Gradient,
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

    const Self = @This();

    pub fn evaluate1(self: Self, rs: Renderstate, offset: Vec4f, uv_set: TexCoordMode) f32 {
        const is_cellular = .Cellular == self.class;
        const att = self.attenuation;

        var weight: f32 = 0.0;
        var amplitude: f32 = 1.0;

        var value: f32 = 0.0;

        if (.ObjectPos == uv_set) {
            var scale = self.scale;

            const uvw = rs.trafo.worldToObjectPoint(rs.p - offset);

            for (0..self.levels) |_| {
                const local_weight = std.math.pow(f32, amplitude, att);

                const local = if (is_cellular) worley3D_1(uvw * scale, 1.0) else perlin3D_1(uvw * scale);

                value += local * local_weight;

                weight += local_weight;
                amplitude *= 0.5;
                scale *= @splat(2.0);
            }
        } else {
            var scale: Vec2f = .{ self.scale[0], self.scale[1] };

            const uv_offset = Vec2f{ offset[0], offset[1] };
            const uv = (if (.Triplanar == uv_set) rs.triplanarUv() else rs.uv()) - uv_offset;

            for (0..self.levels) |_| {
                const local_weight = std.math.pow(f32, amplitude, att);

                const local = if (is_cellular) worley2D_1(uv * scale, 1.0) else perlin2D_1(uv * scale);

                value += local * local_weight;

                weight += local_weight;
                amplitude *= 0.5;
                scale *= @splat(2.0);
            }
        }

        value /= weight;

        const unsigned = if (is_cellular) value else (if (self.flags.absolute) @abs(value) else (value + 1.0) * 0.5);

        const a = self.ratio - self.transition;
        const b = self.ratio + self.transition;

        const result = math.saturate((unsigned - a) / (b - a));
        //  const result = math.smoothstep(remapped_noise);

        return if (self.flags.invert) (1.0 - result) else result;
    }

    pub fn evaluateNormalmap(self: Self, rs: Renderstate, uv_set: TexCoordMode, context: Context) Vec2f {
        if (.ObjectPos == uv_set) {
            const dpdx, const dpdy = context.approximateDpDxy(rs);

            const center = self.evaluate1(rs, @splat(0.0), uv_set);
            const left = self.evaluate1(rs, dpdx, uv_set);
            const bottom = self.evaluate1(rs, dpdy, uv_set);

            const nx = left - center;
            const ny = bottom - center;

            const n = math.normalize3(.{ nx, ny, math.length3(dpdx + dpdy), 0.0 });

            return .{ n[0], n[1] };
        } else {
            const dd = @abs(context.screenspaceDifferential(rs, uv_set));

            const shift_x = dd[0] + dd[2];
            const shift_y = dd[1] + dd[3];

            const center = self.evaluate1(rs, @splat(0.0), uv_set);
            const left = self.evaluate1(rs, Vec4f{ shift_x, 0.0, 0.0, 0.0 }, uv_set);
            const top = self.evaluate1(rs, Vec4f{ 0.0, shift_y, 0.0, 0.0 }, uv_set);

            const nx = left - center;
            const ny = top - center;

            const n = math.normalize3(.{ nx, ny, math.length2(.{ shift_x, shift_y }), 0.0 });

            return .{ n[0], n[1] };
        }
    }

    pub fn evaluate3(self: Self, rs: Renderstate, uv_set: TexCoordMode) Vec4f {
        const noise = self.evaluate1(rs, @splat(0.0), uv_set);

        return @splat(noise);
    }

    fn perlin2D_1(p: Vec2f) f32 {
        const fp, const P = floorfrac2(p);

        const uv = fade(Vec2f, fp);

        const P0: Vec4i = .{ P[0], P[0] +% 1, P[0], P[0] +% 1 };
        const P1: Vec4i = .{ P[1], P[1], P[1] +% 1, P[1] +% 1 };

        const fp0: Vec4f = .{ fp[0], fp[0] - 1.0, fp[0], fp[0] - 1.0 };
        const fp1: Vec4f = .{ fp[1], fp[1], fp[1] - 1.0, fp[1] - 1.0 };

        const hash = hash2v(P0, P1);

        const c = gradient2v(hash, fp0, fp1);

        return gradient_scale2D(math.bilinear(f32, c, uv[0], uv[1]));
    }

    fn perlin3D_1(p: Vec4f) f32 {
        const fp, const P = floorfrac3(p);

        const uvw = fade(Vec4f, fp);

        const P0: Vec4i = .{ P[0], P[0] + 1, P[0], P[0] + 1 };
        const P1: Vec4i = .{ P[1], P[1], P[1] + 1, P[1] + 1 };

        const fp0: Vec4f = .{ fp[0], fp[0] - 1.0, fp[0], fp[0] - 1.0 };
        const fp1: Vec4f = .{ fp[1], fp[1], fp[1] - 1.0, fp[1] - 1.0 };

        const hash = hash3v(P0, P1, @splat(P[2]));

        const c0 = gradient3v(hash[0], fp0, fp1, @splat(fp[2]));
        const c1 = gradient3v(hash[1], fp0, fp1, @splat(fp[2] - 1.0));

        const cc = [_]Vec2f{ .{ c0[0], c1[0] }, .{ c0[1], c1[1] }, .{ c0[2], c1[2] }, .{ c0[3], c1[3] } };

        const result = math.bilinear(Vec2f, cc, uvw[0], uvw[1]);

        return gradient_scale3D(math.lerp(result[0], result[1], uvw[2]));
    }

    fn worley2D_1(p: Vec2f, jitter: f32) f32 {
        const localpos, const P = floorfrac2(p);

        var min_dist: f32 = 1.0e6;

        // var min_pos: Vec2f = @splat(0.0);

        var x: i32 = -1;
        while (x <= 1) : (x += 1) {
            var y: i32 = -1;
            while (y <= 1) : (y += 1) {
                const xy = Vec2i{ x, y };

                const dist = worley_distance2(localpos, xy, P, jitter);
                // const cellpos = worley_cell_position(xy, P, jitter) - localpos;

                if (dist < min_dist) {
                    min_dist = dist;
                    // min_pos = cellpos;
                }
            }
        }

        // Voronoi style
        // return cell_noise2_float(min_pos + p);

        return min_dist;
    }

    fn worley3D_1(p: Vec4f, jitter: f32) f32 {
        const localpos, const P = floorfrac3(p);

        var min_dist: f32 = 1.0e6;

        var x: i32 = -1;
        while (x <= 1) : (x += 1) {
            var y: i32 = -1;
            while (y <= 1) : (y += 1) {
                var z: i32 = -1;
                while (z <= 1) : (z += 1) {
                    const xyz = Vec4i{ x, y, z, 0 };

                    const dist = worley_distance3(localpos, xyz, P, jitter);

                    if (dist < min_dist) {
                        min_dist = dist;
                        // min_pos = cellpos;
                    }
                }
            }
        }

        return min_dist;
    }

    fn worley2D_test(p: Vec2f, jitter: f32) Vec4f {
        const localpos, const P = floorfrac2(p);

        var min_dist: f32 = 1.0e6;

        var min_dist2: f32 = 1.0e6;

        // var min_pos: Vec2f = @splat(0.0);

        var x: i32 = -1;
        while (x <= 1) : (x += 1) {
            var y: i32 = -1;
            while (y <= 1) : (y += 1) {
                const xy = Vec2i{ x, y };

                const dist = worley_distance2(localpos, xy, P, jitter);
                // const cellpos = worley_cell_position(xy, P, jitter) - localpos;

                if (dist < min_dist) {
                    min_dist2 = min_dist;
                    min_dist = dist;
                    // min_pos = cellpos;
                } else if (dist < min_dist2) {
                    min_dist2 = dist;
                }
            }
        }

        // Voronoi style
        // return cell_noise2_float(min_pos + p);

        const color_a = Vec4f{ 1.0, 0.0, 0.0, 0.0 };
        const color_b = Vec4f{ 0.0, 0.0, 0.5, 0.0 };

        //  std.debug.print("{} {}\n", .{ min_dist, min_dist2 });

        const result = math.min4(@as(Vec4f, @splat(min_dist)) * color_a + @as(Vec4f, @splat(math.min(min_dist2, 1.0))) * color_b, @splat(1.0));

        std.debug.print("{}\n", .{result});

        return result;
    }

    // float mx_worley_distance(vec2 p, int x, int y, int xoff, int yoff, float jitter, int metric)
    // {
    //     vec2 cellpos = mx_worley_cell_position(x, y, xoff, yoff, jitter);
    //     vec2 diff = cellpos - p;
    //     if (metric == 2)
    //         return abs(diff.x) + abs(diff.y);       // Manhattan distance
    //     if (metric == 3)
    //         return max(abs(diff.x), abs(diff.y));   // Chebyshev distance
    //     // Either Euclidean or Distance^2
    //     return dot(diff, diff);
    // }

    fn worley_distance2(p: Vec2f, xy: Vec2i, offset: Vec2i, jitter: f32) f32 {
        const cellpos = worley_cell_position2(xy, offset, jitter);
        const diff = cellpos - p;

        return math.dot2(diff, diff);
    }

    fn worley_distance3(p: Vec4f, xyz: Vec4i, offset: Vec4i, jitter: f32) f32 {
        const cellpos = worley_cell_position3(xyz, offset, jitter);
        const diff = cellpos - p;

        return math.dot3(diff, diff);
    }

    fn worley_cell_position2(xy: Vec2i, offset: Vec2i, jitter: f32) Vec2f {
        var off = cell_noise2_vec(@floatFromInt(xy + offset));

        off -= @splat(0.5);
        off *= @splat(jitter);
        off += @splat(0.5);

        return @as(Vec2f, @floatFromInt(xy)) + off;
    }

    fn worley_cell_position3(xyz: Vec4i, offset: Vec4i, jitter: f32) Vec4f {
        var off = cell_noise3_vec(@floatFromInt(xyz + offset));

        off -= @splat(0.5);
        off *= @splat(jitter);
        off += @splat(0.5);

        return @as(Vec4f, @floatFromInt(xyz)) + off;
    }

    fn cell_noise2_float(p: Vec2f) f32 {
        // integer part of float might be out of bounds for u32, but we don't care
        @setRuntimeSafety(false);

        const ip: Vec2u = @intFromFloat(@floor(p));

        return bits_to_01(hash2(ip[0], ip[1]));
    }

    fn cell_noise2_vec(p: Vec2f) Vec2f {
        // integer part of float might be out of bounds for u32, but we don't care
        @setRuntimeSafety(false);

        const ip: Vec2i = @intFromFloat(@floor(p));

        return .{
            bits_to_01(hash3(ip[0], ip[1], 0)),
            bits_to_01(hash3(ip[0], ip[1], 1)),
        };
    }

    fn cell_noise3_vec(p: Vec4f) Vec4f {
        // integer part of float might be out of bounds for u32, but we don't care
        @setRuntimeSafety(false);

        const ip: Vec4i = @intFromFloat(@floor(p));

        return .{
            bits_to_01(hash4(ip[0], ip[1], ip[2], 0)),
            bits_to_01(hash4(ip[0], ip[1], ip[2], 1)),
            bits_to_01(hash4(ip[0], ip[1], ip[2], 2)),
            0,
        };
    }

    fn bits_to_01(in: u32) f32 {
        // return @as(f32, @floatFromInt(bits)) / @as(f32, @floatFromInt(0xffffffff));

        var bits = in;

        bits &= 0x007FFFFF;
        bits |= 0x3F800000;

        return @as(f32, @bitCast(bits)) - 1.0;
    }

    fn floorfrac2(v: Vec2f) struct { Vec2f, Vec2i } {
        const flv = @floor(v);
        return .{ v - flv, @as(Vec2i, @intFromFloat(flv)) };
    }

    fn floorfrac3(v: Vec4f) struct { Vec4f, Vec4i } {
        const flv = @floor(v);
        return .{ v - flv, @as(Vec4i, @intFromFloat(flv)) };
    }

    // Perlin 'fade' function.
    fn fade(comptime T: type, t: T) T {
        return switch (@typeInfo(T)) {
            .float => t * t * t * (t * (t * 6.0 - 15.0) + 10.0),
            .vector => t * t * t * (t * (t * @as(T, @splat(6.0)) - @as(T, @splat(15.0))) + @as(T, @splat(10.0))),
            else => comptime unreachable,
        };
    }

    fn fadeDerivative(comptime T: type, t: T) T {
        return switch (@typeInfo(T)) {
            .float => 30.0 * t * t * (t * (t - 2.0) + 1.0),
            .vector => @as(T, @splat(30.0)) * t * t * (t * (t - @as(T, @splat(2.0))) + @as(T, @splat(1.0))),
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

    fn hash2(x: i32, y: i32) u32 {
        const start_val: u32 = 0xdeadbeef + (2 << 2) + 13;
        const a = start_val + @as(u32, @bitCast(x));
        const b = start_val + @as(u32, @bitCast(y));

        return bjfinal(a, b, start_val);
    }

    fn hash2v(x: Vec4i, y: Vec4i) Vec4u {
        const start_val: Vec4u = @splat(0xdeadbeef + (2 << 2) + 13);
        const a = start_val +% @as(Vec4u, @bitCast(x));
        const b = start_val +% @as(Vec4u, @bitCast(y));

        return bjfinal(a, b, start_val);
    }

    fn hash3(x: i32, y: i32, z: i32) u32 {
        const start_val: u32 = 0xdeadbeef + (3 << 2) + 13;
        const a = start_val +% @as(u32, @bitCast(x));
        const b = start_val +% @as(u32, @bitCast(y));
        const c = start_val +% @as(u32, @bitCast(z));

        return bjfinal(a, b, c);
    }

    fn hash4(x: i32, y: i32, z: i32, xx: i32) u32 {
        const start_val: u32 = 0xdeadbeef + (4 << 2) + 13;

        const a, const b, const c = bjmix(
            start_val +% @as(u32, @bitCast(x)),
            start_val +% @as(u32, @bitCast(y)),
            start_val +% @as(u32, @bitCast(z)),
        );

        return bjfinal(a +% @as(u32, @bitCast(xx)), b, c);
    }

    fn hash3v(x: Vec4i, y: Vec4i, z: Vec4i) [2]Vec4u {
        const start_val: Vec4u = @splat(0xdeadbeef + (3 << 2) + 13);
        const a = start_val +% @as(Vec4u, @bitCast(x));
        const b = start_val +% @as(Vec4u, @bitCast(y));
        const c = start_val +% @as(Vec4u, @bitCast(z));

        return .{ bjfinal(a, b, c), bjfinal(a, b, c + @as(Vec4u, @splat(1))) };
    }

    fn bjmix(a_in: u32, b_in: u32, c_in: u32) [3]u32 {
        var a = a_in;
        var b = b_in;
        var c = c_in;

        a -%= c;
        a ^= std.math.rotl(u32, c, 4);
        c +%= b;
        b -%= a;
        b ^= std.math.rotl(u32, a, 6);
        a +%= c;
        c -%= b;
        c ^= std.math.rotl(u32, b, 8);
        b +%= a;
        a -%= c;
        a ^= std.math.rotl(u32, c, 16);
        c +%= b;
        b -%= a;
        b ^= std.math.rotl(u32, a, 19);
        a +%= c;
        c -%= b;
        c ^= std.math.rotl(u32, b, 4);
        b +%= a;

        return .{ a, b, c };
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
