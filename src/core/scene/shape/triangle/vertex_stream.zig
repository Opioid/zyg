const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec3f = math.Vec3f;
const Vec4f = math.Vec4f;
const quaternion = math.quaternion;
const Quaternion = math.Quaternion;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const VertexStream = union(enum) {
    Json: Json,
    Separate: Separate,
    Compact: Compact,

    pub fn deinit(self: *VertexStream, alloc: *std.mem.Allocator) void {
        return switch (self.*) {
            .Json => {},
            .Separate => |*v| v.deinit(alloc),
            .Compact => |*v| v.deinit(alloc),
        };
    }

    pub fn numVertices(self: VertexStream) u32 {
        return switch (self) {
            .Json => |v| @intCast(u32, v.positions.len),
            .Separate => |v| @intCast(u32, v.positions.len),
            .Compact => |v| @intCast(u32, v.positions.len),
        };
    }

    pub fn position(self: VertexStream, i: usize) Vec4f {
        switch (self) {
            .Json => |v| {
                const p = v.positions[i];
                return Vec4f.init3(p.v[0], p.v[1], p.v[2]);
            },
            .Separate => |v| {
                const p = v.positions[i];
                return Vec4f.init3(p.v[0], p.v[1], p.v[2]);
            },
            .Compact => |v| {
                const p = v.positions[i];
                return Vec4f.init3(p.v[0], p.v[1], p.v[2]);
            },
        }
    }

    pub fn frame(self: VertexStream, i: usize) Quaternion {
        return switch (self) {
            .Json => |v| v.frame(i),
            .Separate => |v| v.frame(i),
            .Compact => |v| v.frame(i),
        };
    }

    pub fn uv(self: VertexStream, i: usize) Vec2f {
        return switch (self) {
            .Json => |v| v.uvs[i],
            .Separate => |v| v.uvs[i],
            .Compact => Vec2f.init1(0.0),
        };
    }

    pub fn bitangentSign(self: VertexStream, i: usize) bool {
        return switch (self) {
            .Json => |v| v.bitangentSign(i),
            .Separate => |v| v.bitangentSign(i),
            .Compact => false,
        };
    }
};

const Json = struct {
    positions: []Vec3f,
    normals: []Vec3f,
    tangents: []Vec3f,
    uvs: []Vec2f,
    bts: []u8,

    const Self = @This();

    pub fn frame(self: Self, i: usize) Quaternion {
        const n3 = self.normals[i];
        const n = Vec4f.init3(n3.v[0], n3.v[1], n3.v[2]);
        const t3 = self.tangents[i];
        const t = Vec4f.init3(t3.v[0], t3.v[1], t3.v[2]);

        return quaternion.initFromTN(t, n);
    }

    pub fn bitangentSign(self: Self, i: usize) bool {
        return self.bts[i] > 0;
    }
};

pub const Separate = struct {
    positions: []Vec3f,
    normals: []Vec3f,
    tangents: []Vec3f,
    uvs: []Vec2f,
    bts: []u8,

    const Self = @This();

    pub fn init(positions: []Vec3f, normals: []Vec3f, tangents: []Vec3f, uvs: []Vec2f, bts: []u8) !Self {
        return Self{
            .positions = positions,
            .normals = normals,
            .tangents = tangents,
            .uvs = uvs,
            .bts = bts,
        };
    }

    pub fn deinit(self: *Self, alloc: *std.mem.Allocator) void {
        alloc.free(self.bts);
        alloc.free(self.uvs);
        alloc.free(self.tangents);
        alloc.free(self.normals);
        alloc.free(self.positions);
    }

    pub fn frame(self: Self, i: usize) Quaternion {
        const n3 = self.normals[i];
        const n = Vec4f.init3(n3.v[0], n3.v[1], n3.v[2]);
        const t3 = self.tangents[i];
        const t = Vec4f.init3(t3.v[0], t3.v[1], t3.v[2]);

        return quaternion.initFromTN(t, n);
    }

    pub fn bitangentSign(self: Self, i: usize) bool {
        return self.bts[i] > 0;
    }
};

pub const Compact = struct {
    positions: []Vec3f,
    normals: []Vec3f,

    const Self = @This();

    pub fn init(positions: []Vec3f, normals: []Vec3f) !Self {
        return Self{
            .positions = positions,
            .normals = normals,
        };
    }

    pub fn deinit(self: *Self, alloc: *std.mem.Allocator) void {
        alloc.free(self.normals);
        alloc.free(self.positions);
    }

    pub fn frame(self: Self, i: usize) Quaternion {
        const n3 = self.normals[i];
        const n = Vec4f.init3(n3.v[0], n3.v[1], n3.v[2]);
        const t = n.tangent3();

        return quaternion.initFromTN(t, n);
    }
};
