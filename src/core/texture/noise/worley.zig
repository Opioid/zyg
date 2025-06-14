const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2u = math.Vec2u;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4u = math.Vec4u;
const Vec4f = math.Vec4f;

pub fn worley2D_1(p: Vec2f, jitter: f32) f32 {
    const localpos, const P = math.floorfrac(p);

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

pub fn worley3D_1(p: Vec4f, jitter: f32) f32 {
    const localpos, const P = math.floorfrac(p);

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
    var off = cellNoise2(@floatFromInt(xy + offset));

    off -= @splat(0.5);
    off *= @splat(jitter);
    off += @splat(0.5);

    return @as(Vec2f, @floatFromInt(xy)) + off;
}

fn worley_cell_position3(xyz: Vec4i, offset: Vec4i, jitter: f32) Vec4f {
    var off = cellNoise3(@floatFromInt(xyz + offset));

    off -= @splat(0.5);
    off *= @splat(jitter);
    off += @splat(0.5);

    return @as(Vec4f, @floatFromInt(xyz)) + off;
}

fn cellNoise2(p: Vec2f) Vec2f {
    // integer part of float might be out of bounds for u32, but we don't care
    @setRuntimeSafety(false);

    const ip: Vec2i = @intFromFloat(@floor(p));
    const h = pcg2d(@bitCast(ip));

    return vecTo01(h);
}

fn cellNoise3(p: Vec4f) Vec4f {
    // integer part of float might be out of bounds for u32, but we don't care
    @setRuntimeSafety(false);

    const ip: Vec4i = @intFromFloat(@floor(p));
    const h = pcg3d(@bitCast(ip));

    return vecTo01(h);
}

fn pcg2d(in: Vec2u) Vec2u {
    var v = in * @as(Vec2u, @splat(1664525)) + @as(Vec2u, @splat(1013904223));

    v[0] += v[1] * 1664525;
    v[1] += v[0] * 1664525;

    v ^= v >> @as(Vec2u, @splat(16));

    v[0] += v[1] * 1664525;
    v[1] += v[0] * 1664525;

    v = v ^ (v >> @as(Vec2u, @splat(16)));

    return v;
}

fn pcg3d(in: Vec4u) Vec4u {
    var v = in * @as(Vec4u, @splat(1664525)) + @as(Vec4u, @splat(1013904223));

    v[0] += v[1] * v[2];
    v[1] += v[2] * v[0];
    v[2] += v[0] * v[1];

    v ^= v >> @as(Vec4u, @splat(16));

    v[0] += v[1] * v[2];
    v[1] += v[2] * v[0];
    v[2] += v[0] * v[1];

    return v;
}

fn vecTo01(in: anytype) @Vector(@typeInfo(@TypeOf(in)).vector.len, f32) {
    var bits = in;

    bits &= @as(@TypeOf(in), @splat(0x007FFFFF));
    bits |= @as(@TypeOf(in), @splat(0x3F800000));

    const OutT = @Vector(@typeInfo(@TypeOf(in)).vector.len, f32);

    return @as(OutT, @bitCast(bits)) - @as(OutT, @splat(1.0));
}
