const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const AABB = math.AABB;
const Ray = math.Ray;

const std = @import("std");

pub const Node = struct {
    const Vec = packed struct {
        v: [3]f32,
        data: u32,
    };

    min: Vec = undefined,
    max: Vec = undefined,

    pub fn initFrom(other: Node, o: u32) Node {
        return .{
            .min = .{ .v = other.min.v, .data = other.min.data + o },
            .max = other.max,
        };
    }

    pub fn aabb(self: Node) AABB {
        return AABB.init(
            .{ self.min.v[0], self.min.v[1], self.min.v[2], 0.0 },
            .{ self.max.v[0], self.max.v[1], self.max.v[2], 0.0 },
        );
    }

    pub fn children(self: Node) u32 {
        return self.min.data;
    }

    pub fn numIndices(self: Node) u32 {
        return self.max.data;
    }

    pub fn indicesStart(self: Node) u32 {
        return self.min.data;
    }

    pub fn indicesEnd(self: Node) u32 {
        return self.min.data + self.max.data;
    }

    pub fn setAABB(self: *Node, box: AABB) void {
        self.min.v[0] = box.bounds[0][0];
        self.min.v[1] = box.bounds[0][1];
        self.min.v[2] = box.bounds[0][2];

        self.max.v[0] = box.bounds[1][0];
        self.max.v[1] = box.bounds[1][1];
        self.max.v[2] = box.bounds[1][2];
    }

    pub fn setSplitNode(self: *Node, ch: u32) void {
        self.min.data = ch;
        self.max.data = 0;
    }

    pub fn setLeafNode(self: *Node, start_primitive: u32, num_primitives: u32) void {
        self.min.data = start_primitive;
        self.max.data = num_primitives;
    }

    pub fn offset(self: *Node, o: u32) void {
        self.min.data += o;
    }

    // Raytracing Gems 2 - chapter 2
    pub fn intersect(self: Node, ray: Ray) f32 {
        const lower = (Vec4f{ self.min.v[0], self.min.v[1], self.min.v[2], 0.0 } - ray.origin) * ray.inv_direction;
        const upper = (Vec4f{ self.max.v[0], self.max.v[1], self.max.v[2], 0.0 } - ray.origin) * ray.inv_direction;

        const t0 = @minimum(lower, upper);
        const t1 = @maximum(lower, upper);

        const tmins = Vec4f{ t0[0], t0[1], t0[2], ray.minT() };
        const tmaxs = Vec4f{ t1[0], t1[1], t1[2], ray.maxT() };

        const tboxmin = std.math.max(tmins[0], std.math.max(tmins[1], std.math.max(tmins[2], tmins[3])));
        const tboxmax = std.math.min(tmaxs[0], std.math.min(tmaxs[1], std.math.min(tmaxs[2], tmaxs[3])));

        return if (tboxmin <= tboxmax) tboxmin else std.math.f32_max;
    }
};
