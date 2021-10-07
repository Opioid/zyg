const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const AABB = math.AABB;
const Ray = math.Ray;

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

    pub fn initFrom(other: Node, o: u32) Node {
        return .{
            .min = .{ .v = other.min.v, .children_or_data = other.min.children_or_data + o },
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
        self.min.v[0] = box.bounds[0][0];
        self.min.v[1] = box.bounds[0][1];
        self.min.v[2] = box.bounds[0][2];

        self.max.v[0] = box.bounds[1][0];
        self.max.v[1] = box.bounds[1][1];
        self.max.v[2] = box.bounds[1][2];
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

    pub fn offset(self: *Node, o: u32) void {
        self.min.children_or_data += o;
    }

    pub fn intersectP(self: Node, ray: Ray) bool {
        const l1 = (Vec4f{ self.min.v[0], self.min.v[1], self.min.v[2], 0.0 } - ray.origin) * ray.inv_direction;
        const l2 = (Vec4f{ self.max.v[0], self.max.v[1], self.max.v[2], 0.0 } - ray.origin) * ray.inv_direction;

        // the order we use for those min/max is vital to filter out
        // NaNs that happens when an inv_dir is +/- inf and
        // (box_min - pos) is 0. inf * 0 = NaN
        const filtered_l1a = @minimum(l1, math.Infinity);
        const filtered_l2a = @minimum(l2, math.Infinity);

        const filtered_l1b = @maximum(l1, math.Neg_infinity);
        const filtered_l2b = @maximum(l2, math.Neg_infinity);

        // now that we're back on our feet, test those slabs.
        const max_t3 = @maximum(filtered_l1a, filtered_l2a);
        const min_t3 = @minimum(filtered_l1b, filtered_l2b);

        // unfold back. try to hide the latency of the shufps & co.
        var max_t = std.math.min(max_t3[0], max_t3[1]);
        var min_t = std.math.max(min_t3[0], min_t3[1]);

        max_t = std.math.min(max_t, max_t3[2]);
        min_t = std.math.max(min_t, min_t3[2]);

        const ray_min_t = ray.minT();
        const ray_max_t = ray.maxT();

        // return max_t >= ray_min_t and ray_max_t >= min_t and max_t >= min_t;
        return 0 != (@boolToInt(max_t >= ray_min_t) & @boolToInt(ray_max_t >= min_t) & @boolToInt(max_t >= min_t));
    }
};
