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

    pub fn deinit(self: *VertexStream, alloc: Allocator) void {
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
            .Json => |v| v.uv(i),
            .Separate => |v| v.uvs[i],
            .Compact => @splat(2, @as(f32, 0.0)),
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
    positions: []Pack3f,
    normals: []Pack3f,
    tangents: []Pack3f,
    uvs: []Vec2f,
    bts: []u8,

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
    positions: []Pack3f,
    normals: []Pack3f,
    tangents: []Pack3f,
    uvs: []Vec2f,
    bts: []u8,

    const Self = @This();

    pub fn init(positions: []Pack3f, normals: []Pack3f, tangents: []Pack3f, uvs: []Vec2f, bts: []u8) !Self {
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
    positions: []Pack3f,
    normals: []Pack3f,

    const Self = @This();

    pub fn init(positions: []Pack3f, normals: []Pack3f) !Self {
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
