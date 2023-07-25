const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;

pub fn cubicBezierBounds(cp: [4]Vec4f) AABB {
    var bounds = AABB.init(math.min4(cp[0], cp[1]), math.max4(cp[0], cp[1]));
    bounds.mergeAssign(AABB.init(math.min4(cp[2], cp[3]), math.max4(cp[2], cp[3])));
    return bounds;
}

pub fn cubicBezierSubdivide(cp: [4]Vec4f) [7]Vec4f {
    const two = @splat(4, @as(f32, 2.0));
    const three = @splat(4, @as(f32, 3.0));
    const four = @splat(4, @as(f32, 4.0));

    return .{
        cp[0],
        (cp[0] + cp[1]) / two,
        (cp[0] + two * cp[1] + cp[2]) / four,
        (cp[0] + three * cp[1] + three * cp[2] + cp[3]) / @splat(4, @as(f32, 8.0)),
        (cp[1] + two * cp[2] + cp[3]) / four,
        (cp[2] + cp[3]) / two,
        cp[3],
    };
}

pub fn cubicBezierEvaluate(cp: [4]Vec4f, u: f32) Vec4f {
    const uv = @splat(4, u);

    const cp1: [3]Vec4f = .{
        math.lerp(cp[0], cp[1], uv),
        math.lerp(cp[1], cp[2], uv),
        math.lerp(cp[2], cp[3], uv),
    };

    const cp2: [2]Vec4f = .{
        math.lerp(cp1[0], cp1[1], uv),
        math.lerp(cp1[1], cp1[2], uv),
    };

    return math.lerp(cp2[0], cp2[1], uv);
}

pub fn cubicBezierEvaluateWithDerivative(cp: [4]Vec4f, u: f32) [2]Vec4f {
    const uv = @splat(4, u);

    const cp1: [3]Vec4f = .{
        math.lerp(cp[0], cp[1], uv),
        math.lerp(cp[1], cp[2], uv),
        math.lerp(cp[2], cp[3], uv),
    };

    const cp2: [2]Vec4f = .{
        math.lerp(cp1[0], cp1[1], uv),
        math.lerp(cp1[1], cp1[2], uv),
    };

    var deriv: Vec4f = undefined;
    if (math.squaredLength3(cp2[1] - cp2[0]) > 0.0) {
        deriv = @splat(4, @as(f32, 3.0)) * (cp2[1] - cp2[0]);
    } else {
        deriv = cp[3] - cp[0];
    }

    return .{ math.lerp(cp2[0], cp2[1], uv), deriv };
}

pub fn cubicBezierEvaluateDerivative(cp: [4]Vec4f, u: f32) Vec4f {
    const uv = @splat(4, u);

    const cp1: [3]Vec4f = .{
        math.lerp(cp[0], cp[1], uv),
        math.lerp(cp[1], cp[2], uv),
        math.lerp(cp[2], cp[3], uv),
    };

    const cp2: [2]Vec4f = .{
        math.lerp(cp1[0], cp1[1], uv),
        math.lerp(cp1[1], cp1[2], uv),
    };

    if (math.squaredLength3(cp2[1] - cp2[0]) > 0.0) {
        return @splat(4, @as(f32, 3.0)) * (cp2[1] - cp2[0]);
    } else {
        return cp[3] - cp[0];
    }
}
