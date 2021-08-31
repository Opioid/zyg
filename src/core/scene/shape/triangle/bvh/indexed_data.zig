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

    pub fn deinit(self: *Self, alloc: *Allocator) void {
        alloc.free(self.frames);
        alloc.free(self.positions);
        alloc.free(self.triangles);
    }

    pub fn allocateTriangles(self: *Self, alloc: *Allocator, num_triangles: u32, vertices: VertexStream) !void {
        const num_vertices = vertices.numVertices();

        self.triangles = try alloc.alloc(Triangle, num_triangles);
        self.positions = try alloc.alloc(Vec4f, num_vertices);
        self.frames = try alloc.alloc(Vec4f, num_vertices);

        var i: u32 = 0;
        while (i < num_vertices) : (i += 1) {
            self.positions[i] = vertices.position(i);
            self.frames[i] = vertices.frame(i);
        }
    }

    pub fn setTriangle(
        self: *Self,
        a: u32,
        b: u32,
        c: u32,
        part: u32,
        vertices: VertexStream,
        triangle_id: u32,
    ) void {
        const abts = vertices.bitangentSign(a);
        const bbts = vertices.bitangentSign(b);
        const cbts = vertices.bitangentSign(c);

        const bitangent_sign = (abts and bbts) or (bbts and cbts) or (cbts and abts);

        self.triangles[triangle_id] = .{
            .a = a,
            .b = b,
            .c = c,
            .bts = if (bitangent_sign) 1 else 0,
            .part = @intCast(u31, part),
        };
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

        const tna = quaternion.initTN(self.frames[tri.a]);
        const tnb = quaternion.initTN(self.frames[tri.b]);
        const tnc = quaternion.initTN(self.frames[tri.c]);

        t.* = triangle.interpolateP(tna[0], tnb[0], tnc[0], u, v).normalize3();
        n.* = triangle.interpolateP(tna[1], tnb[1], tnc[1], u, v).normalize3();
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

    pub fn bitangentSign(self: Self, index: u32) f32 {
        return if (0 == self.triangles[index].bts) 1.0 else -1.0;
    }
};
