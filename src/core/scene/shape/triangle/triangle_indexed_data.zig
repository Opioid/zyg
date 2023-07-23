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

pub const Indexed_data = struct {
    const Triangle = packed struct {
        a: u32,
        b: u32,
        c: u32,
        bts: u1,
        part: u31,
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

        self.triangles = (try alloc.alloc(Triangle, num_triangles)).ptr;
        self.positions = (try alloc.alloc(f32, num_vertices * 3 + 1)).ptr;
        self.frames = (try alloc.alloc(Vec4f, num_vertices)).ptr;
        self.uvs = (try alloc.alloc(Vec2f, num_vertices)).ptr;

        vertices.copy(self.positions, self.frames, self.uvs, num_vertices);
        self.positions[self.num_vertices * 3] = 0.0;
    }

    pub fn setTriangle(
        self: *Self,
        a: u32,
        b: u32,
        c: u32,
        p: u32,
        vertices: VertexBuffer,
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
            .part = @intCast(p),
        };
    }

    inline fn position(self: *const Self, index: u32) Vec4f {
        return self.positions[index * 3 ..][0..4].*;
    }

    pub fn intersect(self: *const Self, ray: Ray, index: u32) ?triangle.Intersection {
        const tri = self.triangles[index];

        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        return triangle.intersect(ray, a, b, c);
    }

    pub fn intersectP(self: *const Self, ray: Ray, index: u32) bool {
        const tri = self.triangles[index];

        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        return triangle.intersectP(ray, a, b, c);
    }

    pub fn interpolateP(self: *const Self, u: f32, v: f32, index: u32) Vec4f {
        const tri = self.triangles[index];

        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        return triangle.interpolate3(a, b, c, u, v);
    }

    pub fn interpolateData(self: *const Self, u: f32, v: f32, index: u32, t: *Vec4f, n: *Vec4f, uv: *Vec2f) void {
        const tri = self.triangles[index];

        const tna = quaternion.toTN(self.frames[tri.a]);
        const uva = self.uvs[tri.a];

        const tua = @shuffle(f32, tna[0], @splat(4, uva[0]), [_]i32{ 0, 1, 2, -1 });
        const nva = @shuffle(f32, tna[1], @splat(4, uva[1]), [_]i32{ 0, 1, 2, -1 });

        const tnb = quaternion.toTN(self.frames[tri.b]);
        const uvb = self.uvs[tri.b];

        const tub = @shuffle(f32, tnb[0], @splat(4, uvb[0]), [_]i32{ 0, 1, 2, -1 });
        const nvb = @shuffle(f32, tnb[1], @splat(4, uvb[1]), [_]i32{ 0, 1, 2, -1 });

        const tnc = quaternion.toTN(self.frames[tri.c]);
        const uvc = self.uvs[tri.c];

        const tuc = @shuffle(f32, tnc[0], @splat(4, uvc[0]), [_]i32{ 0, 1, 2, -1 });
        const nvc = @shuffle(f32, tnc[1], @splat(4, uvc[1]), [_]i32{ 0, 1, 2, -1 });

        const tu = triangle.interpolate3(tua, tub, tuc, u, v);
        const nv = triangle.interpolate3(nva, nvb, nvc, u, v);

        t.* = math.normalize3(tu);
        n.* = math.normalize3(nv);
        uv.* = Vec2f{ tu[3], nv[3] };
    }

    pub fn interpolateShadingNormal(self: *const Self, u: f32, v: f32, index: u32) Vec4f {
        const tri = self.triangles[index];

        const a = quaternion.toNormal(self.frames[tri.a]);
        const b = quaternion.toNormal(self.frames[tri.b]);
        const c = quaternion.toNormal(self.frames[tri.c]);

        return math.normalize3(triangle.interpolate3(a, b, c, u, v));
    }

    pub fn interpolateUv(self: *const Self, u: f32, v: f32, index: u32) Vec2f {
        const tri = self.triangles[index];

        const uva = self.uvs[tri.a];
        const uvb = self.uvs[tri.b];
        const uvc = self.uvs[tri.c];

        return triangle.interpolate2(uva, uvb, uvc, u, v);
    }

    pub fn part(self: *const Self, index: u32) u32 {
        return self.triangles[index].part;
    }

    pub fn normal(self: *const Self, index: u32) Vec4f {
        const tri = self.triangles[index];

        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        const e1 = b - a;
        const e2 = c - a;

        return math.normalize3(math.cross3(e1, e2));
    }

    pub fn crossAxis(self: *const Self, index: u32) Vec4f {
        const tri = self.triangles[index];

        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        const e1 = b - a;
        const e2 = c - a;

        return math.cross3(e1, e2);
    }

    pub fn bitangentSign(self: *const Self, index: u32) f32 {
        return if (0 == self.triangles[index].bts) 1.0 else -1.0;
    }

    pub fn area(self: *const Self, index: u32) f32 {
        const tri = self.triangles[index];

        const a = self.position(tri.a);
        const b = self.position(tri.b);
        const c = self.position(tri.c);

        return triangle.area(a, b, c);
    }

    pub fn triangleP(self: *const Self, index: u32) [3]Vec4f {
        const tri = self.triangles[index];

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

    pub fn trianglePuv(self: *const Self, index: u32) Puv {
        const tri = self.triangles[index];

        return .{
            .p = .{
                self.position(tri.a),
                self.position(tri.b),
                self.position(tri.c),
            },
            .uv = .{ self.uvs[tri.a], self.uvs[tri.b], self.uvs[tri.c] },
        };
    }

    pub fn sample(self: *const Self, index: u32, r2: Vec2f, p: *Vec4f, tc: *Vec2f) void {
        const uv = math.smpl.triangleUniform(r2);

        const tri = self.triangles[index];

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
