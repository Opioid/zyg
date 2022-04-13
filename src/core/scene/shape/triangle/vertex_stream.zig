const math = @import("base").math;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const quaternion = math.quaternion;
const Quaternion = math.Quaternion;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const VertexStream = union(enum) {
    Json: Json,
    Separate: Separate,
    Compact: Compact,
    C: CAPI,

    pub fn deinit(self: *VertexStream, alloc: Allocator) void {
        return switch (self.*) {
            .Json, .C => {},
            .Separate => |*v| v.deinit(alloc),
            .Compact => |*v| v.deinit(alloc),
        };
    }

    pub fn numVertices(self: VertexStream) u32 {
        return switch (self) {
            .Json => |v| @intCast(u32, v.positions.len),
            .Separate => |v| @intCast(u32, v.positions.len),
            .Compact => |v| @intCast(u32, v.positions.len),
            .C => |c| c.num_vertices,
        };
    }

    pub fn position(self: VertexStream, i: usize) Vec4f {
        switch (self) {
            .Json => |v| {
                const p = v.positions[i];
                return .{ p.v[0], p.v[1], p.v[2], 0.0 };
            },
            .Separate => |v| {
                const p = v.positions[i];
                return .{ p.v[0], p.v[1], p.v[2], 0.0 };
            },
            .Compact => |v| {
                const p = v.positions[i];
                return .{ p.v[0], p.v[1], p.v[2], 0.0 };
            },
            .C => |v| {
                const id = i * v.positions_stride;
                return .{ v.positions[id + 0], v.positions[id + 1], v.positions[id + 2], 0.0 };
            },
        }
    }

    pub fn frame(self: VertexStream, i: usize) Quaternion {
        return switch (self) {
            .Json => |v| v.frame(i),
            .Separate => |v| v.frame(i),
            .Compact => |v| v.frame(i),
            .C => |v| v.frame(i),
        };
    }

    pub fn uv(self: VertexStream, i: usize) Vec2f {
        return switch (self) {
            .Json => |v| v.uv(i),
            .Separate => |v| v.uvs[i],
            .Compact => @splat(2, @as(f32, 0.0)),
            .C => |v| v.uv(i),
        };
    }

    pub fn bitangentSign(self: VertexStream, i: usize) bool {
        return switch (self) {
            .Json => |v| v.bitangentSign(i),
            .Separate => |v| v.bitangentSign(i),
            .Compact => false,
            .C => |v| v.bitangentSign(i),
        };
    }
};

const Json = struct {
    positions: []const Pack3f,
    normals: []const Pack3f,
    tangents: []const Pack3f,
    uvs: []const Vec2f,
    bts: []const u8,

    const Self = @This();

    pub fn frame(self: Self, i: usize) Quaternion {
        const n3 = self.normals[i];
        const n = Vec4f{ n3.v[0], n3.v[1], n3.v[2], 0.0 };

        var t: Vec4f = undefined;

        if (self.tangents.len > i) {
            const t3 = self.tangents[i];
            t = Vec4f{ t3.v[0], t3.v[1], t3.v[2], 0.0 };
        } else {
            t = math.tangent3(n);
        }

        return quaternion.initFromTN(t, n);
    }

    pub fn uv(self: Self, i: usize) Vec2f {
        return if (self.uvs.len > i) self.uvs[i] else .{ 0.0, 0.0 };
    }

    pub fn bitangentSign(self: Self, i: usize) bool {
        return if (self.bts.len > i) self.bts[i] > 0 else false;
    }
};

pub const Separate = struct {
    positions: []const Pack3f,
    normals: []const Pack3f,
    tangents: []const Pack3f,
    uvs: []const Vec2f,
    bts: []const u8,

    const Self = @This();

    pub fn init(positions: []Pack3f, normals: []Pack3f, tangents: []Pack3f, uvs: []Vec2f, bts: []u8) Self {
        return Self{
            .positions = positions,
            .normals = normals,
            .tangents = tangents,
            .uvs = uvs,
            .bts = bts,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.bts);
        alloc.free(self.uvs);
        alloc.free(self.tangents);
        alloc.free(self.normals);
        alloc.free(self.positions);
    }

    pub fn frame(self: Self, i: usize) Quaternion {
        const n3 = self.normals[i];
        const n = Vec4f{ n3.v[0], n3.v[1], n3.v[2], 0.0 };
        const t3 = self.tangents[i];
        const t = Vec4f{ t3.v[0], t3.v[1], t3.v[2], 0.0 };

        return quaternion.initFromTN(t, n);
    }

    pub fn bitangentSign(self: Self, i: usize) bool {
        return self.bts[i] > 0;
    }
};

pub const Compact = struct {
    positions: []const Pack3f,
    normals: []const Pack3f,

    const Self = @This();

    pub fn init(positions: []Pack3f, normals: []Pack3f) Self {
        return Self{
            .positions = positions,
            .normals = normals,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.normals);
        alloc.free(self.positions);
    }

    pub fn frame(self: Self, i: usize) Quaternion {
        const n3 = self.normals[i];
        const n = Vec4f{ n3.v[0], n3.v[1], n3.v[2], 0.0 };
        const t = math.tangent3(n);

        return quaternion.initFromTN(t, n);
    }
};

pub const CAPI = struct {
    num_vertices: u32,
    positions_stride: u32,
    normals_stride: u32,
    tangents_stride: u32,
    uvs_stride: u32,

    positions: [*]const f32,
    normals: [*]const f32,
    tangents: [*]const f32,
    uvs: [*]const f32,

    const Self = @This();

    pub fn init(
        num_vertices: u32,
        positions_stride: u32,
        normals_stride: u32,
        tangents_stride: u32,
        uvs_stride: u32,
        positions: [*]const f32,
        normals: [*]const f32,
        tangents: [*]const f32,
        uvs: [*]const f32,
    ) Self {
        return Self{
            .positions = positions,
            .normals = normals,
            .tangents = tangents,
            .uvs = uvs,
            .num_vertices = num_vertices,
            .positions_stride = positions_stride,
            .normals_stride = normals_stride,
            .tangents_stride = tangents_stride,
            .uvs_stride = uvs_stride,
        };
    }

    pub fn frame(self: Self, i: usize) Quaternion {
        const nid = i * self.normals_stride;
        const n = Vec4f{ self.normals[nid + 0], self.normals[nid + 1], self.normals[nid + 2], 0.0 };

        if (0 == self.tangents_stride) {
            const t = math.tangent3(n);

            return quaternion.initFromTN(t, n);
        }

        const tid = i * self.tangents_stride;
        const t = Vec4f{ self.tangents[tid + 0], self.normals[tid + 1], self.normals[tid + 2], 0.0 };

        return quaternion.initFromTN(t, n);
    }

    pub fn bitangentSign(self: Self, i: usize) bool {
        const stride = self.tangents_stride;

        if (stride <= 3) {
            return false;
        }

        const sign = self.tangents[i * stride + 3];
        return sign < 0.0;
    }

    pub fn uv(self: Self, i: usize) Vec2f {
        const id = i * self.uvs_stride;
        return .{ self.uvs[id + 0], self.uvs[id + 1] };
    }
};
