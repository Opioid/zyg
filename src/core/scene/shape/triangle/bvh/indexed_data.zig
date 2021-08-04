const triangle = @import("../triangle.zig");

const base = @import("base");
usingnamespace base;
usingnamespace base.math;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Indexed_data = struct {
    pub const Intersection = struct {
        u: f32,
        v: f32,
    };

    const Triangle = struct {
        a: u32,
        b: u32,
        c: u32,
        bts: u1,
        part: u31,
    };

    triangles: []Triangle,
    positions: []Vec4f,
    frames: []Vec4f,
    uvs: []Vec2f,

    const Self = @This();

    pub fn intersect(self: Self, ray: *Ray, index: usize) ?Intersection {
        _ = self;
        _ = ray;
        _ = index;

        return null;
    }

    pub fn intersectP(self: Self, ray: Ray, index: usize) bool {
        _ = self;
        _ = ray;
        _ = index;

        return false;
    }

    pub fn interpolateP(self: Self, u: f32, v: f32, index: u32) Vec4f {
        const tri = self.triangles[index];

        const ap = self.positions[tri.a];
        const bp = self.positions[tri.b];
        const cp = self.positions[tri.c];

        return triangle.interpolateP(ap, bp, cp, u, v);
    }
};
