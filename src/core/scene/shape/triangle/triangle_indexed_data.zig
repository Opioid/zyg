const VertexBuffer = @import("vertex_buffer.zig").Buffer;
const triangle = @import("triangle.zig");

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;
const quaternion = math.quaternion;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const IndexedData = struct {
    const Triangle = packed struct {
        a: u32,
        b: u32,
        c: u32,
        part: u32,
    };

    num_triangles: u32 = 0,
    num_vertices: u32 = 0,

    triangles: [*]Triangle = undefined,
    positions: [*]f32 = undefined,
    frames: [*]Vec4f = undefined,
    uvs: [*]Vec2f = undefined,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.uvs[0..self.num_vertices]);
        alloc.free(self.frames[0..self.num_vertices]);
        alloc.free(self.positions[0 .. self.num_vertices * 3 + 1]);
        alloc.free(self.triangles[0..self.num_triangles]);
    }

    pub fn allocateTriangles(self: *Self, alloc: Allocator, num_triangles: u32, vertices: VertexBuffer) !void {
        const num_vertices = vertices.numVertices();

        self.num_triangles = num_triangles;
        self.num_vertices = num_vertices;

        self.triangles = (try alloc.alignedAlloc(Triangle, 16, num_triangles)).ptr;
        self.positions = (try alloc.alloc(f32, num_vertices * 3 + 1)).ptr;
        self.frames = (try alloc.alloc(Vec4f, num_vertices)).ptr;
        self.uvs = (try alloc.alloc(Vec2f, num_vertices)).ptr;

        vertices.copy(self.positions, self.frames, self.uvs, num_vertices);
        self.positions[num_vertices * 3] = 0.0;
    }

    pub fn setTriangle(self: *Self, triangle_id: u32, a: u32, b: u32, c: u32, p: u32) void {
        self.triangles[triangle_id] = .{ .a = a, .b = b, .c = c, .part = p };
    }

    inline fn position(self: Self, index: u32) Vec4f {
        return self.positions[index * 3 ..][0..4].*;
    }

    pub fn intersect(self: Self, ray: Ray, index: u32) ?triangle.Fragment {
        const tri = self.triangles[index];

        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        return triangle.intersect(ray, a, b, c);
    }

    pub fn intersectP(self: Self, ray: Ray, index: u32) bool {
        const tri = self.triangles[index];

        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        return triangle.intersectP(ray, a, b, c);
    }

    pub fn indexTriangle(self: Self, index: u32) Triangle {
        return self.triangles[index];
    }

    pub fn interpolateP(self: Self, tri: Triangle, u: f32, v: f32) Vec4f {
        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        return triangle.interpolate3(a, b, c, u, v);
    }

    pub fn interpolateData(self: Self, tri: Triangle, u: f32, v: f32, t: *Vec4f, n: *Vec4f, uv: *Vec2f, bit_sign: *f32) void {
        const tna = quaternion.signedToTN(self.frames[tri.a]);
        const uva = self.uvs[tri.a];

        const tnb = quaternion.signedToTN(self.frames[tri.b]);
        const uvb = self.uvs[tri.b];

        const tnc = quaternion.signedToTN(self.frames[tri.c]);
        const uvc = self.uvs[tri.c];

        const ti = triangle.interpolate3(tna[0], tnb[0], tnc[0], u, v);
        const ni = triangle.interpolate3(tna[1], tnb[1], tnc[1], u, v);
        const uvi = triangle.interpolate2(uva, uvb, uvc, u, v);

        t.* = math.normalize3(ti);
        n.* = math.normalize3(ni);
        uv.* = uvi;
        bit_sign.* = std.math.copysign(@as(f32, 1.0), tna[0][3] + tnb[0][3] + tnc[0][3]);
    }

    pub fn interpolateUv(self: Self, tri: Triangle, u: f32, v: f32) Vec2f {
        const a = self.uvs[tri.a];
        const b = self.uvs[tri.b];
        const c = self.uvs[tri.c];

        return triangle.interpolate2(a, b, c, u, v);
    }

    pub fn normal(self: Self, tri: Triangle) Vec4f {
        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        const e1 = b - a;
        const e2 = c - a;

        return math.normalize3(math.cross3(e1, e2));
    }

    pub fn crossAxis(self: Self, tri: Triangle) Vec4f {
        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        const e1 = b - a;
        const e2 = c - a;

        return math.cross3(e1, e2);
    }

    pub fn triangleArea(self: Self, tri: Triangle) f32 {
        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        return triangle.area(a, b, c);
    }

    pub fn triangleP(self: Self, tri: Triangle) [3]Vec4f {
        return .{
            self.position(tri.a),
            self.position(tri.b),
            self.position(tri.c),
        };
    }

    const Puv = struct {
        p: [3]Vec4f,
        uv: [3]Vec2f,
    };

    pub fn trianglePuv(self: Self, tri: Triangle) Puv {
        return .{
            .p = .{
                self.position(tri.a),
                self.position(tri.b),
                self.position(tri.c),
            },
            .uv = .{ self.uvs[tri.a], self.uvs[tri.b], self.uvs[tri.c] },
        };
    }

    pub fn sample(self: Self, tri: Triangle, r2: Vec2f, p: *Vec4f, tc: *Vec2f) void {
        const uv = math.smpl.triangleUniform(r2);

        const pa = self.position(tri.a);
        const pb = self.position(tri.b);
        const pc = self.position(tri.c);

        p.* = triangle.interpolate3(pa, pb, pc, uv[0], uv[1]);

        const uva = self.uvs[tri.a];
        const uvb = self.uvs[tri.b];
        const uvc = self.uvs[tri.c];

        tc.* = triangle.interpolate2(uva, uvb, uvc, uv[0], uv[1]);
    }
};
