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

        const a = self.positions[tri.a];
        const b = self.positions[tri.b];
        const c = self.positions[tri.c];

        return triangle.interpolateP(a, b, c, u, v);
    }

    pub fn interpolateData(self: Self, u: f32, v: f32, index: u32, t: *Vec4f, n: *Vec4f) void {
        const tri = self.triangles[index];

        const tna = quaternion.initMat3x3(self.frames[tri.a]);
        const tnb = quaternion.initMat3x3(self.frames[tri.b]);
        const tnc = quaternion.initMat3x3(self.frames[tri.c]);

        t.* = triangle.interpolateP(tna.r[0], tnb.r[0], tnc.r[0], u, v).normalize3();
        n.* = triangle.interpolateP(tna.r[2], tnb.r[2], tnc.r[2], u, v).normalize3();
    }

    pub fn normal(self: Self, index: u32) Vec4f {
        const tri = self.triangles[index];

        const a = self.positions[tri.a];
        const b = self.positions[tri.b];
        const c = self.positions[tri.c];

        const e1 = b.sub3(a);
        const e2 = c.sub3(a);

        return e1.cross3(e2).normalize3();
    }

    pub fn bitangentSign(self: self, index: u32) f32 {
        return if (0 == self.triangles[index].bts) 1.0 else -1.0;
    }
};
