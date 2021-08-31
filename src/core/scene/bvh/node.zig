const base = @import("base");
usingnamespace base;
//usingnamespace base.math;
const Vec4f = math.Vec4f;
const AABB = math.AABB;
const Ray = math.Ray;

const infinity = Vec4f.init1(@bitCast(f32, @as(u32, 0x7F800000)));
const neg_infinity = Vec4f.init1(@bitCast(f32, ~@as(u32, 0x7F800000)));

const std = @import("std");

pub const Node = struct {
    const Min = struct {
        v: [3]f32,
        children_or_data: u32,
    };

    const Max = struct {
        v: [3]f32,
        axis: u8,
        num_indices: u8,
        pad: [2]u8,
    };

    min: Min = undefined,
    max: Max = undefined,

    pub fn aabb(self: Node) AABB {
        return AABB.init(
            Vec4f.init3(self.min.v[0], self.min.v[1], self.min.v[2]),
            Vec4f.init3(self.max.v[0], self.max.v[1], self.max.v[2]),
        );
    }

    pub fn children(self: Node) u32 {
        return self.min.children_or_data;
    }

    pub fn numIndices(self: Node) u8 {
        return self.max.num_indices;
    }

    pub fn indicesStart(self: Node) u32 {
        return self.min.children_or_data;
    }

    pub fn indicesEnd(self: Node) u32 {
        return self.min.children_or_data + self.max.num_indices;
    }

    pub fn axis(self: Node) u8 {
        return self.max.axis;
    }

    pub fn setAABB(self: *Node, box: AABB) void {
        self.min.v[0] = box.bounds[0].v[0];
        self.min.v[1] = box.bounds[0].v[1];
        self.min.v[2] = box.bounds[0].v[2];

        self.max.v[0] = box.bounds[1].v[0];
        self.max.v[1] = box.bounds[1].v[1];
        self.max.v[2] = box.bounds[1].v[2];
    }

    pub fn setSplitNode(self: *Node, ch: u32, ax: u8) void {
        self.min.children_or_data = ch;
        self.max.axis = ax;
        self.max.num_indices = 0;
    }

    pub fn setLeafNode(self: *Node, start_primitive: u32, num_primitives: u8) void {
        self.min.children_or_data = start_primitive;
        self.max.num_indices = num_primitives;
    }

    pub fn intersectP(self: Node, ray: Ray) bool {
        const l1 = Vec4f.init3(self.min.v[0], self.min.v[1], self.min.v[2]).sub3(ray.origin).mul3(ray.inv_direction);
        const l2 = Vec4f.init3(self.max.v[0], self.max.v[1], self.max.v[2]).sub3(ray.origin).mul3(ray.inv_direction);

        // the order we use for those min/max is vital to filter out
        // NaNs that happens when an inv_dir is +/- inf and
        // (box_min - pos) is 0. inf * 0 = NaN
        const filtered_l1a = l1.min3(infinity);
        const filtered_l2a = l2.min3(infinity);

        const filtered_l1b = l1.max3(neg_infinity);
        const filtered_l2b = l2.max3(neg_infinity);

        const max_t3 = filtered_l1a.max3(filtered_l2a);
        const min_t3 = filtered_l1b.min3(filtered_l2b);

        const max_t = std.math.min(max_t3.v[0], std.math.min(max_t3.v[1], max_t3.v[2]));
        const min_t = std.math.max(min_t3.v[0], std.math.max(min_t3.v[1], min_t3.v[2]));

        const ray_min_t = ray.minT();
        const ray_max_t = ray.maxT();

        return max_t >= ray_min_t and ray_max_t >= min_t and max_t >= min_t;
    }
};
