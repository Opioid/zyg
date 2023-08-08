const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;

pub const IndexCurve = struct {
    pos: u32 = undefined,
    width: u32 = undefined,
};

pub fn cubicBezierBounds(cp: [4]Vec4f) AABB {
    var bounds = AABB.init(math.min4(cp[0], cp[1]), math.max4(cp[0], cp[1]));
    bounds.mergeAssign(AABB.init(math.min4(cp[2], cp[3]), math.max4(cp[2], cp[3])));
    return bounds;
}

pub fn cubicBezierSubdivide(cp: [4]Vec4f) [7]Vec4f {
    const two: Vec4f = @splat(2.0);
    const three: Vec4f = @splat(3.0);
    const four: Vec4f = @splat(4.0);

    return .{
        cp[0],
        (cp[0] + cp[1]) / two,
        (cp[0] + two * cp[1] + cp[2]) / four,
        (cp[0] + three * cp[1] + three * cp[2] + cp[3]) / @as(Vec4f, @splat(8.0)),
        (cp[1] + two * cp[2] + cp[3]) / four,
        (cp[2] + cp[3]) / two,
        cp[3],
    };
}

pub inline fn cubicBezierSubdivide2_0(cp: [4]Vec4f) [4]Vec4f {
    const two: Vec4f = @splat(2.0);
    const three: Vec4f = @splat(3.0);

    return .{
        cp[0],
        (cp[0] + cp[1]) / two,
        (cp[0] + two * cp[1] + cp[2]) / @as(Vec4f, @splat(4.0)),
        (cp[0] + three * cp[1] + three * cp[2] + cp[3]) / @as(Vec4f, @splat(8.0)),
    };
}

pub inline fn cubicBezierSubdivide2_1(cp: [4]Vec4f) [4]Vec4f {
    const two: Vec4f = @splat(2.0);
    const three: Vec4f = @splat(3.0);

    return .{
        (cp[0] + three * cp[1] + three * cp[2] + cp[3]) / @as(Vec4f, @splat(8.0)),
        (cp[1] + two * cp[2] + cp[3]) / @as(Vec4f, @splat(4.0)),
        (cp[2] + cp[3]) / two,
        cp[3],
    };
}

pub fn cubicBezierSubdivide4_0(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide2_0(cubicBezierSubdivide2_0(cp));
}

pub fn cubicBezierSubdivide4_1(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide2_1(cubicBezierSubdivide2_0(cp));
}

pub fn cubicBezierSubdivide4_2(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide2_0(cubicBezierSubdivide2_1(cp));
}

pub fn cubicBezierSubdivide4_3(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide2_1(cubicBezierSubdivide2_1(cp));
}

pub fn cubicBezierEvaluate(cp: [4]Vec4f, u: f32) Vec4f {
    const uv: Vec4f = @splat(u);

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
    const uv: Vec4f = @splat(u);

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

    const axis = cp2[1] - cp2[0];
    if (math.squaredLength3(axis) > 0.0) {
        deriv = @as(Vec4f, @splat(3.0)) * axis;
    } else {
        deriv = cp[3] - cp[0];
    }

    return .{ math.lerp(cp2[0], cp2[1], uv), deriv };
}

pub fn cubicBezierEvaluateDerivative(cp: [4]Vec4f, u: f32) Vec4f {
    const uv: Vec4f = @splat(u);

    const cp1: [3]Vec4f = .{
        math.lerp(cp[0], cp[1], uv),
        math.lerp(cp[1], cp[2], uv),
        math.lerp(cp[2], cp[3], uv),
    };

    const cp2: [2]Vec4f = .{
        math.lerp(cp1[0], cp1[1], uv),
        math.lerp(cp1[1], cp1[2], uv),
    };

    const axis = cp2[1] - cp2[0];
    if (math.squaredLength3(axis) > 0.0) {
        return @as(Vec4f, @splat(3.0)) * axis;
    } else {
        return cp[3] - cp[0];
    }
}
