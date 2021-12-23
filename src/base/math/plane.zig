const math = @import("vector4.zig");
const Vec4f = math.Vec4f;

pub fn createNP(normal: Vec4f, point: Vec4f) Vec4f {
    return .{ normal[0], normal[1], normal[2], -math.dot3(normal, point) };
}

pub fn createP3(v0: Vec4f, v1: Vec4f, v2: Vec4f) Vec4f {
    const n = math.normalize3(math.cross3(v2 - v1, v0 - v1));
    return createNP(n, v0);
}

pub fn dot(p: Vec4f, v: Vec4f) f32 {
    return (p[0] * v[0] + p[1] * v[1]) + (p[2] * v[2] + p[3]);
}

pub fn intersection(p0: Vec4f, p1: Vec4f, p2: Vec4f) Vec4f {
    const n1 = p0; //(p0[0], p0[1], p0[2]);

    const d1 = @splat(4, p0[3]);

    const n2 = p1; //(p1[0], p1[1], p1[2]);

    const d2 = @splat(4, p1[3]);

    const n3 = p2; //(p2[0], p2[1], p2[2]);

    const d3 = @splat(4, p2[3]);

    //    d1 ( N2 * N3 ) + d2 ( N3 * N1 ) + d3 ( N1 * N2 )
    // P = ------------------------------------------------
    //                    N1 . ( N2 * N3 )

    return -(d1 * math.cross3(n2, n3) + d2 * math.cross3(n3, n1) + d3 * math.cross3(n1, n2)) /
        @splat(4, math.dot3(n1, math.cross3(n2, n3)));
}
