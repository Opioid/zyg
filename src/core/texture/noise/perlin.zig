const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4u = math.Vec4u;
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn perlin2D_1(p: Vec2f, period: Vec2f) f32 {
    const fp, const P = math.floorfrac(p);

    const uv = fade(Vec2f, fp);

    var P01 = Vec2i{ P[0], P[0] +% 1 };
    var P11 = Vec2i{ P[1], P[1] +% 1 };

    const periodi: Vec2i = @intFromFloat(period);

    if (periodi[0] > 0) {
        P01 = @mod(P01, @as(Vec2i, @splat(periodi[0])));
    }

    if (periodi[1] > 0) {
        P11 = @mod(P11, @as(Vec2i, @splat(periodi[1])));
    }

    const P0: Vec4i = .{ P01[0], P01[1], P01[0], P01[1] };
    const P1: Vec4i = .{ P11[0], P11[0], P11[1], P11[1] };

    const fp0: Vec4f = .{ fp[0], fp[0] - 1.0, fp[0], fp[0] - 1.0 };
    const fp1: Vec4f = .{ fp[1], fp[1], fp[1] - 1.0, fp[1] - 1.0 };

    const hash = hash2v(P0, P1);

    const c = gradient2v(hash, fp0, fp1);

    return gradient_scale2D(math.bilinear(f32, c, uv[0], uv[1]));
}

pub fn perlin3D_1(p: Vec4f) f32 {
    const fp, const P = math.floorfrac(p);

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

// Perlin 'fade' function.
fn fade(comptime T: type, t: T) T {
    return switch (@typeInfo(T)) {
        .float => t * t * t * @mulAdd(T, t, (@mulAdd(T, t, 6.0, -15.0)), 10.0),
        .vector => t * t * t * @mulAdd(T, t, (@mulAdd(T, t, @splat(6.0), @splat(-15.0))), @splat(10.0)),
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
