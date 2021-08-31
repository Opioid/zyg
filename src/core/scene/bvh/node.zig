const base = @import("base");
usingnamespace base;
//usingnamespace base.math;
const Vec4f = math.Vec4f;
const AABB = math.AABB;

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
};
