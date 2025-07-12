const math = @import("base").math;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;
const quaternion = math.quaternion;
const Quaternion = math.Quaternion;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Buffer = union(enum) {
    C: CAPI,
    Separate: Separate,
    SeparateQuat: SeparateQuat,

    pub fn deinit(self: *Buffer, alloc: Allocator) void {
        return switch (self.*) {
            .C => {},
            inline else => |*v| v.deinit(alloc),
        };
    }

    pub fn numFrames(self: Buffer) u32 {
        return switch (self) {
            .C => |c| c.num_vertices,
            inline else => |v| @intCast(v.positions.len),
        };
    }

    pub fn numVertices(self: Buffer) u32 {
        return switch (self) {
            .C => |c| c.num_vertices,
            inline else => |v| @intCast(v.positions[0].len),
        };
    }

    pub fn position(self: Buffer, i: u32) Vec4f {
        switch (self) {
            .C => |v| {
                const id = i * v.positions_stride;
                return .{ v.positions[id + 0], v.positions[id + 1], v.positions[id + 2], 0.0 };
            },
            inline else => |v| {
                const p = v.positions[0][i];
                return .{ p.v[0], p.v[1], p.v[2], 0.0 };
            },
        }
    }

    pub fn positionAt(self: Buffer, frame: usize, i: u32) Vec4f {
        switch (self) {
            .C => |v| {
                const id = i * v.positions_stride;
                return .{ v.positions[id + 0], v.positions[id + 1], v.positions[id + 2], 0.0 };
            },
            inline else => |v| {
                const p = v.positions[frame][i];
                return .{ p.v[0], p.v[1], p.v[2], 0.0 };
            },
        }
    }

    pub fn copy(self: Buffer, positions: [*]f32, normals: [*]f32, uvs: [*]Vec2f, count: u32) void {
        return switch (self) {
            inline else => |v| v.copy(positions, normals, uvs, count),
        };
    }
};

pub const Separate = struct {
    positions: []const []const Pack3f,
    normals: []const Pack3f,
    tangents: []const Pack3f,
    uvs: []const Vec2f,
    bts: []const u8,

    own: bool,

    const Self = @This();

    pub fn init(positions: [][]Pack3f, normals: []Pack3f, tangents: []Pack3f, uvs: []Vec2f, bts: []u8) Self {
        return Self{
            .positions = positions,
            .normals = normals,
            .tangents = tangents,
            .uvs = uvs,
            .bts = bts,
            .own = false,
        };
    }

    pub fn initOwned(positions: [][]Pack3f, normals: []Pack3f, tangents: []Pack3f, uvs: []Vec2f, bts: []u8) Self {
        return .{
            .positions = positions,
            .normals = normals,
            .tangents = tangents,
            .uvs = uvs,
            .bts = bts,
            .own = true,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        if (self.own) {
            alloc.free(self.bts);
            alloc.free(self.uvs);
            alloc.free(self.tangents);
            alloc.free(self.normals);

            for (self.positions) |p| {
                alloc.free(p);
            }
            alloc.free(self.positions);
        }
    }

    pub fn copy(self: Self, positions: [*]f32, normals: [*]f32, uvs: [*]Vec2f, count: u32) void {
        const num_components = count * 3;

        var begin: u32 = 0;
        var end: u32 = num_components;

        for (self.positions) |frame_positions| {
            @memcpy(positions[begin..end], @as([*]const f32, @ptrCast(frame_positions.ptr))[0..num_components]);

            begin += num_components;
            end += num_components;
        }

        @memcpy(normals[0..num_components], @as([*]const f32, @ptrCast(self.normals.ptr))[0..num_components]);

        if (count == self.uvs.len) {
            @memcpy(uvs[0..count], self.uvs);
        } else {
            @memset(uvs[0..count], .{ 0.0, 0.0 });
        }
    }
};

pub const SeparateQuat = struct {
    positions: []const []const Pack3f,
    ts: []const Pack4f,
    uvs: []const Vec2f,

    const Self = @This();

    pub fn init(positions: [][]Pack3f, ts: []Pack4f, uvs: []Vec2f) Self {
        return .{
            .positions = positions,
            .ts = ts,
            .uvs = uvs,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.uvs);
        alloc.free(self.ts);

        for (self.positions) |p| {
            alloc.free(p);
        }
        alloc.free(self.positions);
    }

    pub fn copy(self: Self, positions: [*]f32, normals: [*]f32, uvs: [*]Vec2f, count: u32) void {
        const num_components = count * 3;
        @memcpy(positions[0..num_components], @as([*]const f32, @ptrCast(self.positions[0].ptr))[0..num_components]);

        for (self.ts[0..count], 0..count) |ts, i| {
            const frame = Vec4f{ ts.v[0], ts.v[1], ts.v[2], if (ts.v[3] < 0.0) -ts.v[3] else ts.v[3] };
            const normal = quaternion.toNormal(frame);
            normals[i * 3 + 0] = normal[0];
            normals[i * 3 + 1] = normal[1];
            normals[i * 3 + 2] = normal[2];
        }

        @memcpy(uvs[0..count], self.uvs);
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
        return .{
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

    pub fn copy(self: Self, positions: [*]f32, normals: [*]f32, uvs: [*]Vec2f, count: u32) void {
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const dest_id = i * 3;
            const source_id = i * self.positions_stride;

            positions[dest_id + 0] = self.positions[source_id + 0];
            positions[dest_id + 1] = self.positions[source_id + 1];
            positions[dest_id + 2] = self.positions[source_id + 2];
        }

        i = 0;
        while (i < count) : (i += 1) {
            const dest_id = i * 3;
            const source_id = i * self.normals_stride;

            normals[dest_id + 0] = self.normals[source_id + 0];
            normals[dest_id + 1] = self.normals[source_id + 1];
            normals[dest_id + 2] = self.normals[source_id + 2];
        }

        i = 0;
        while (i < count) : (i += 1) {
            const id = i * self.uvs_stride;
            uvs[i] = .{ self.uvs[id + 0], self.uvs[id + 1] };
        }
    }
};
