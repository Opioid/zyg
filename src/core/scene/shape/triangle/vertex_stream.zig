const math = @import("base").math;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;
const quaternion = math.quaternion;
const Quaternion = math.Quaternion;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const VertexStream = union(enum) {
    Separate: Separate,
    SeparateQuat: SeparateQuat,
    Compact: Compact,
    C: CAPI,

    pub fn deinit(self: *VertexStream, alloc: Allocator) void {
        return switch (self.*) {
            .C => {},
            inline else => |*v| v.deinit(alloc),
        };
    }

    pub fn numVertices(self: VertexStream) u32 {
        return switch (self) {
            .C => |c| c.num_vertices,
            inline else => |v| @intCast(u32, v.positions.len),
        };
    }

    pub fn position(self: VertexStream, i: usize) Vec4f {
        switch (self) {
            .Separate => |v| {
                const p = v.positions[i];
                return .{ p.v[0], p.v[1], p.v[2], 0.0 };
            },
            .SeparateQuat => |v| {
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

    pub fn copy(self: VertexStream, positions: [*]Vec4f, frames: [*]Vec4f, uvs: [*]Vec2f, count: u32) void {
        return switch (self) {
            inline else => |v| v.copy(positions, frames, uvs, count),
        };
    }

    pub fn bitangentSign(self: VertexStream, i: usize) bool {
        return switch (self) {
            .Compact => false,
            inline else => |v| v.bitangentSign(i),
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

    pub fn copy(self: Self, positions: [*]Vec4f, frames: [*]Vec4f, uvs: [*]Vec2f, count: u32) void {
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const p = self.positions[i];
            positions[i] = .{ p.v[0], p.v[1], p.v[2], 0.0 };
        }

        i = 0;
        if (count == self.tangents.len) {
            while (i < count) : (i += 1) {
                const n3 = self.normals[i];
                const n = Vec4f{ n3.v[0], n3.v[1], n3.v[2], 0.0 };
                const t3 = self.tangents[i];
                const t = Vec4f{ t3.v[0], t3.v[1], t3.v[2], 0.0 };

                frames[i] = quaternion.initFromTN(t, n);
            }
        } else {
            while (i < count) : (i += 1) {
                const n3 = self.normals[i];
                const n = Vec4f{ n3.v[0], n3.v[1], n3.v[2], 0.0 };
                const t = math.tangent3(n);

                frames[i] = quaternion.initFromTN(t, n);
            }
        }

        if (count == self.uvs.len) {
            std.mem.copy(Vec2f, uvs[0..count], self.uvs);
        } else {
            std.mem.set(Vec2f, uvs[0..count], .{ 0.0, 0.0 });
        }
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

    owning: bool,

    const Self = @This();

    pub fn init(positions: []Pack3f, normals: []Pack3f, tangents: []Pack3f, uvs: []Vec2f, bts: []u8) Self {
        return Self{
            .positions = positions,
            .normals = normals,
            .tangents = tangents,
            .uvs = uvs,
            .bts = bts,
            .owning = false,
        };
    }

    pub fn initOwned(positions: []Pack3f, normals: []Pack3f, tangents: []Pack3f, uvs: []Vec2f, bts: []u8) Self {
        return Self{
            .positions = positions,
            .normals = normals,
            .tangents = tangents,
            .uvs = uvs,
            .bts = bts,
            .owning = true,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        if (self.owning) {
            alloc.free(self.bts);
            alloc.free(self.uvs);
            alloc.free(self.tangents);
            alloc.free(self.normals);
            alloc.free(self.positions);
        }
    }

    pub fn copy(self: Self, positions: [*]Vec4f, frames: [*]Vec4f, uvs: [*]Vec2f, count: u32) void {
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const p = self.positions[i];
            positions[i] = .{ p.v[0], p.v[1], p.v[2], 0.0 };
        }

        i = 0;
        if (count == self.tangents.len) {
            while (i < count) : (i += 1) {
                const n3 = self.normals[i];
                const n = Vec4f{ n3.v[0], n3.v[1], n3.v[2], 0.0 };
                const t3 = self.tangents[i];
                const t = Vec4f{ t3.v[0], t3.v[1], t3.v[2], 0.0 };

                frames[i] = quaternion.initFromTN(t, n);
            }
        } else {
            while (i < count) : (i += 1) {
                const n3 = self.normals[i];
                const n = Vec4f{ n3.v[0], n3.v[1], n3.v[2], 0.0 };
                const t = math.tangent3(n);

                frames[i] = quaternion.initFromTN(t, n);
            }
        }

        if (count == self.uvs.len) {
            std.mem.copy(Vec2f, uvs[0..count], self.uvs);
        } else {
            std.mem.set(Vec2f, uvs[0..count], .{ 0.0, 0.0 });
        }
    }

    pub fn bitangentSign(self: Self, i: usize) bool {
        return if (self.bts.len > i) self.bts[i] > 0 else false;
    }
};

pub const SeparateQuat = struct {
    positions: []const Pack3f,
    ts: []const Pack4f,
    uvs: []const Vec2f,

    const Self = @This();

    pub fn init(positions: []Pack3f, ts: []Pack4f, uvs: []Vec2f) Self {
        return Self{
            .positions = positions,
            .ts = ts,
            .uvs = uvs,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.uvs);
        alloc.free(self.ts);
        alloc.free(self.positions);
    }

    pub fn copy(self: Self, positions: [*]Vec4f, frames: [*]Vec4f, uvs: [*]Vec2f, count: u32) void {
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const p = self.positions[i];
            positions[i] = .{ p.v[0], p.v[1], p.v[2], 0.0 };
        }

        i = 0;
        while (i < count) : (i += 1) {
            const ts = self.ts[i];
            frames[i] = .{ ts.v[0], ts.v[1], ts.v[2], if (ts.v[3] < 0.0) -ts.v[3] else ts.v[3] };
        }

        std.mem.copy(Vec2f, uvs[0..count], self.uvs);
    }

    pub fn bitangentSign(self: Self, i: usize) bool {
        return self.ts[i].v[3] < 0.0;
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

    pub fn copy(self: Self, positions: [*]Vec4f, frames: [*]Vec4f, uvs: [*]Vec2f, count: u32) void {
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const p = self.positions[i];
            positions[i] = .{ p.v[0], p.v[1], p.v[2], 0.0 };
        }

        i = 0;
        while (i < count) : (i += 1) {
            const n3 = self.normals[i];
            const n = Vec4f{ n3.v[0], n3.v[1], n3.v[2], 0.0 };
            const t = math.tangent3(n);

            frames[i] = quaternion.initFromTN(t, n);
        }

        std.mem.set(Vec2f, uvs[0..count], .{ 0.0, 0.0 });
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

    pub fn copy(self: Self, positions: [*]Vec4f, frames: [*]Vec4f, uvs: [*]Vec2f, count: u32) void {
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const id = i * self.positions_stride;
            positions[i] = .{ self.positions[id + 0], self.positions[id + 1], self.positions[id + 2], 0.0 };
        }

        i = 0;
        while (i < count) : (i += 1) {
            const nid = i * self.normals_stride;
            const n = Vec4f{ self.normals[nid + 0], self.normals[nid + 1], self.normals[nid + 2], 0.0 };

            if (0 == self.tangents_stride) {
                const t = math.tangent3(n);

                frames[i] = quaternion.initFromTN(t, n);
            } else {
                const tid = i * self.tangents_stride;
                const t = Vec4f{ self.tangents[tid + 0], self.normals[tid + 1], self.normals[tid + 2], 0.0 };

                frames[i] = quaternion.initFromTN(t, n);
            }
        }

        i = 0;
        while (i < count) : (i += 1) {
            const id = i * self.uvs_stride;
            uvs[i] = .{ self.uvs[id + 0], self.uvs[id + 1] };
        }
    }

    pub fn bitangentSign(self: Self, i: usize) bool {
        const stride = self.tangents_stride;

        if (stride <= 3) {
            return false;
        }

        const sign = self.tangents[i * stride + 3];
        return sign < 0.0;
    }
};
