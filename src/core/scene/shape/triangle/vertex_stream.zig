const base = @import("base");
usingnamespace base;
usingnamespace base.math;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const VertexStream = union(enum) {
    Json: Json,
    Compact: Compact,

    pub fn deinit(self: *VertexStream, alloc: *std.mem.Allocator) void {
        return switch (self.*) {
            .Json => {},
            .Compact => |*c| c.deinit(alloc),
        };
    }

    pub fn numVertices(self: VertexStream) u32 {
        return switch (self) {
            .Json => |js| @intCast(u32, js.positions.len),
            .Compact => |c| @intCast(u32, c.positions.len),
        };
    }

    pub fn position(self: VertexStream, i: usize) Vec4f {
        switch (self) {
            .Json => |js| {
                const p = js.positions[i];
                return Vec4f.init3(p.v[0], p.v[1], p.v[2]);
            },
            .Compact => |c| {
                const p = c.positions[i];
                return Vec4f.init3(p.v[0], p.v[1], p.v[2]);
            },
        }
    }

    pub fn frame(self: VertexStream, i: usize) Quaternion {
        return switch (self) {
            .Json => |js| js.frame(i),
            .Compact => |c| c.frame(i),
        };
    }

    pub fn bitangentSign(self: VertexStream, i: usize) bool {
        return switch (self) {
            .Json => |js| js.bitangentSign(i),
            .Compact => false,
        };
    }
};

const Json = struct {
    positions: []Vec3f,
    normals: []Vec3f,
    tangents: []Vec4f,

    const Self = @This();

    // pub fn position(self: Self, i: u32) Vec3f {
    //     return self.positions[i];
    // }

    pub fn frame(self: Self, i: usize) Quaternion {
        const n3 = self.normals[i];
        const n = Vec4f.init3(n3.v[0], n3.v[1], n3.v[2]);
        const t = self.tangents[i];

        return quaternion.initFromTN(t, n);
    }

    pub fn bitangentSign(self: Self, i: usize) bool {
        return self.tangents[i].v[3] > 0.0;
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
