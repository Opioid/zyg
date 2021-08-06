const VertexStream = @import("../vertex_stream.zig").VertexStream;
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

    triangles: []Triangle = &.{},
    positions: []Vec4f = &.{},
    frames: []Vec4f = &.{},
    uvs: []Vec2f = &.{},

    const Self = @This();

    pub fn init(alloc: *Allocator, num_triangles: u32, vertices: VertexStream) !Indexed_data {
        const num_vertices = vertices.numVertices();

        var data = Indexed_data{
            .triangles = try alloc.alloc(Triangle, num_triangles),
            .positions = try alloc.alloc(Vec4f, num_vertices),
            .frames = try alloc.alloc(Vec4f, num_vertices),
        };

        var i: u32 = 0;
        while (i < num_vertices) : (i += 1) {
            data.positions[i] = vertices.position(i);
            data.frames[i] = vertices.frame(i);
        }

        return data;
    }

    pub fn deinit(self: *Self, alloc: *Allocator) void {
        alloc.free(self.frames);
        alloc.free(self.positions);
        alloc.free(self.triangles);
    }

    pub fn intersect(self: Self, ray: *Ray, index: usize) ?Intersection {
        const tri = self.triangles[index];

        const ap = self.positions[tri.a];
        const bp = self.positions[tri.b];
        const cp = self.positions[tri.c];

        var u: f32 = undefined;
        var v: f32 = undefined;

        if (triangle.intersect(ray, ap, bp, cp, &u, &v)) {
            return Intersection{ .u = u, .v = v };
        }

        return null;
    }

    pub fn intersectP(self: Self, ray: Ray, index: usize) bool {
        const tri = self.triangles[index];

        const ap = self.positions[tri.a];
        const bp = self.positions[tri.b];
        const cp = self.positions[tri.c];

        return triangle.intersectP(ray, ap, bp, cp);
    }

    pub fn interpolateP(self: Self, u: f32, v: f32, index: u32) Vec4f {
        const tri = self.triangles[index];

        const ap = self.positions[tri.a];
        const bp = self.positions[tri.b];
        const cp = self.positions[tri.c];

        return triangle.interpolateP(ap, bp, cp, u, v);
    }

    pub fn interpolateData(self: Self, u: f32, v: f32, index: u32, n: *Vec4f, t: *Vec4f) void {
        _ = self;
        _ = u;
        _ = v;
        _ = index;
        _ = n;
        _ = t;
    }
};
