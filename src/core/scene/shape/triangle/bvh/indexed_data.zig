const VertexStream = @import("../vertex_stream.zig").VertexStream;
const triangle = @import("../triangle.zig");

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;
const quaternion = math.quaternion;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Indexed_data = struct {
    pub const Intersection = struct {
        u: f32,
        v: f32,
    };

    const Triangle = packed struct {
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
        alloc.free(self.uvs);
        alloc.free(self.frames);
        alloc.free(self.positions);
        alloc.free(self.triangles);
    }

    pub fn allocateTriangles(self: *Self, alloc: *Allocator, num_triangles: u32, vertices: VertexStream) !void {
        const num_vertices = vertices.numVertices();

        self.triangles = try alloc.alloc(Triangle, num_triangles);
        self.positions = try alloc.alloc(Vec4f, num_vertices);
        self.frames = try alloc.alloc(Vec4f, num_vertices);
        self.uvs = try alloc.alloc(Vec2f, num_vertices);

        var i: u32 = 0;
        while (i < num_vertices) : (i += 1) {
            self.positions[i] = vertices.position(i);
            self.frames[i] = vertices.frame(i);
            self.uvs[i] = vertices.uv(i);
        }
    }

    pub fn setTriangle(
        self: *Self,
        a: u32,
        b: u32,
        c: u32,
        p: u32,
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
            .part = @intCast(u31, p),
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

        return triangle.interpolate3(a, b, c, u, v);
    }

    pub fn interpolateData(self: Self, u: f32, v: f32, index: u32, t: *Vec4f, n: *Vec4f, uv: *Vec2f) void {
        const tri = self.triangles[index];

        const tna = quaternion.initTN(self.frames[tri.a]);
        const tnb = quaternion.initTN(self.frames[tri.b]);
        const tnc = quaternion.initTN(self.frames[tri.c]);

        t.* = math.normalize3(triangle.interpolate3(tna[0], tnb[0], tnc[0], u, v));
        n.* = math.normalize3(triangle.interpolate3(tna[1], tnb[1], tnc[1], u, v));

        const uva = self.uvs[tri.a];
        const uvb = self.uvs[tri.b];
        const uvc = self.uvs[tri.c];

        uv.* = triangle.interpolate2(uva, uvb, uvc, u, v);

        // const tri = self.triangles[index];

        // const tna = quaternion.initTN(self.frames[tri.a]);
        // const tnb = quaternion.initTN(self.frames[tri.b]);
        // const tnc = quaternion.initTN(self.frames[tri.c]);

        // const uva = self.uvs[tri.a];
        // const uvb = self.uvs[tri.b];
        // const uvc = self.uvs[tri.c];

        // const tua = Vec4f{ tna[0][0], tna[0][1], tna[0][2], uva.v[0] };
        // const tub = Vec4f{ tnb[0][0], tnb[0][1], tnb[0][2], uvb.v[0] };
        // const tuc = Vec4f{ tnc[0][0], tnc[0][1], tnc[0][2], uvc.v[0] };

        // const nva = Vec4f{ tna[1][0], tna[1][1], tna[1][2], uva.v[1] };
        // const nvb = Vec4f{ tnb[1][0], tnb[1][1], tnb[1][2], uvb.v[1] };
        // const nvc = Vec4f{ tnc[1][0], tnc[1][1], tnc[1][2], uvc.v[1] };

        // const tu = triangle.interpolate3(tua, tub, tuc, u, v);
        // const nv = triangle.interpolate3(nva, nvb, nvc, u, v);

        // t.* = math.normalize3(tu);
        // n.* = math.normalize3(nv);

        // uv.* = Vec2f.init2(tu[3], nv[3]);
    }

    pub fn interpolateShadingNormal(self: Self, u: f32, v: f32, index: u32) Vec4f {
        const tri = self.triangles[index];

        const a = quaternion.initNormal(self.frames[tri.a]);
        const b = quaternion.initNormal(self.frames[tri.b]);
        const c = quaternion.initNormal(self.frames[tri.c]);

        return math.normalize3(triangle.interpolate3(a, b, c, u, v));
    }

    pub fn interpolateUv(self: Self, u: f32, v: f32, index: u32) Vec2f {
        const tri = self.triangles[index];

        const uva = self.uvs[tri.a];
        const uvb = self.uvs[tri.b];
        const uvc = self.uvs[tri.c];

        return triangle.interpolate2(uva, uvb, uvc, u, v);
    }

    pub fn part(self: Self, index: u32) u32 {
        return self.triangles[index].part;
    }

    pub fn normal(self: Self, index: u32) Vec4f {
        const tri = self.triangles[index];

        const a = self.positions[tri.a];
        const b = self.positions[tri.b];
        const c = self.positions[tri.c];

        const e1 = b - a;
        const e2 = c - a;

        return math.normalize3(math.cross3(e1, e2));
    }

    pub fn bitangentSign(self: Self, index: u32) f32 {
        return if (0 == self.triangles[index].bts) 1.0 else -1.0;
    }
};
