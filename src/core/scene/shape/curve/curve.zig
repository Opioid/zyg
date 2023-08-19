const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Partition = struct {
    cp: [4]Vec4f,
    u_range: Vec2f,
};

pub fn partition(cp: [4]Vec4f, p: u32) Partition {
    return switch (p) {
        1 => .{
            .cp = cubicBezierSubdivide2_0(cp),
            .u_range = .{ 0.0, 0.5 },
        },
        2 => .{
            .cp = cubicBezierSubdivide2_1(cp),
            .u_range = .{ 0.5, 1.0 },
        },
        3 => .{
            .cp = cubicBezierSubdivide4_0(cp),
            .u_range = .{ 0.0, 0.25 },
        },
        4 => .{
            .cp = cubicBezierSubdivide4_1(cp),
            .u_range = .{ 0.25, 0.5 },
        },
        5 => .{
            .cp = cubicBezierSubdivide4_2(cp),
            .u_range = .{ 0.5, 0.75 },
        },
        6 => .{
            .cp = cubicBezierSubdivide4_3(cp),
            .u_range = .{ 0.75, 1.0 },
        },
        7 => .{
            .cp = cubicBezierSubdivide8_0(cp),
            .u_range = .{ 0.0, 0.125 },
        },
        8 => .{
            .cp = cubicBezierSubdivide8_1(cp),
            .u_range = .{ 0.125, 0.25 },
        },
        9 => .{
            .cp = cubicBezierSubdivide8_2(cp),
            .u_range = .{ 0.25, 0.375 },
        },
        10 => .{
            .cp = cubicBezierSubdivide8_3(cp),
            .u_range = .{ 0.375, 0.5 },
        },
        11 => .{
            .cp = cubicBezierSubdivide8_4(cp),
            .u_range = .{ 0.5, 0.625 },
        },
        12 => .{
            .cp = cubicBezierSubdivide8_5(cp),
            .u_range = .{ 0.625, 0.75 },
        },
        13 => .{
            .cp = cubicBezierSubdivide8_6(cp),
            .u_range = .{ 0.75, 0.875 },
        },
        14 => .{
            .cp = cubicBezierSubdivide8_7(cp),
            .u_range = .{ 0.875, 1.0 },
        },

        else => .{ .cp = cp, .u_range = .{ 0.0, 1.0 } },
    };
}

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

pub inline fn cubicBezierSubdivide4_0(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide2_0(cubicBezierSubdivide2_0(cp));
}

pub inline fn cubicBezierSubdivide4_1(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide2_1(cubicBezierSubdivide2_0(cp));
}

pub inline fn cubicBezierSubdivide4_2(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide2_0(cubicBezierSubdivide2_1(cp));
}

pub inline fn cubicBezierSubdivide4_3(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide2_1(cubicBezierSubdivide2_1(cp));
}

pub fn cubicBezierSubdivide8_0(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide4_0(cubicBezierSubdivide2_0(cp));
}

pub fn cubicBezierSubdivide8_1(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide4_1(cubicBezierSubdivide2_0(cp));
}

pub fn cubicBezierSubdivide8_2(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide4_2(cubicBezierSubdivide2_0(cp));
}

pub fn cubicBezierSubdivide8_3(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide4_3(cubicBezierSubdivide2_0(cp));
}

pub fn cubicBezierSubdivide8_4(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide4_0(cubicBezierSubdivide2_1(cp));
}

pub fn cubicBezierSubdivide8_5(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide4_1(cubicBezierSubdivide2_1(cp));
}

pub fn cubicBezierSubdivide8_6(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide4_2(cubicBezierSubdivide2_1(cp));
}

pub fn cubicBezierSubdivide8_7(cp: [4]Vec4f) [4]Vec4f {
    return cubicBezierSubdivide4_3(cubicBezierSubdivide2_1(cp));
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

    const axis = cp2[0] - cp2[1];
    if (math.squaredLength3(axis) > 0.0) {
        deriv = @as(Vec4f, @splat(3.0)) * axis;
    } else {
        deriv = cp[0] - cp[3];
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

    const axis = cp2[0] - cp2[1];
    if (math.squaredLength3(axis) > 0.0) {
        return @as(Vec4f, @splat(3.0)) * axis;
    } else {
        return cp[0] - cp[3];
    }
}
