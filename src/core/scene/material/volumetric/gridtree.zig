const CM = @import("../collision_coefficients.zig").CM;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Ray = math.Ray;
const Vec4i = math.Vec4i;
const Vec4u = math.Vec4u;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Box = struct {
    bounds: [2]Vec4i,
};

pub const Node = packed struct {
    has_children: u1,
    children_or_data: u31,

    pub fn isParent(self: Node) bool {
        return 0 != self.has_children;
    }

    pub fn index(self: Node) u32 {
        return @as(u32, self.children_or_data);
    }

    pub fn isEmpty(self: Node) bool {
        return 0x7FFFFFFF == self.children_or_data;
    }

    pub fn setChildren(self: *Node, id: u32) void {
        self.has_children = 1;
        self.children_or_data = @intCast(u31, id);
    }

    pub fn setData(self: *Node, id: u32) void {
        self.has_children = 0;
        self.children_or_data = @intCast(u31, id);
    }

    pub fn setEmpty(self: *Node) void {
        self.has_children = 0;
        self.children_or_data = 0x7FFFFFFF;
    }
};

pub const Gridtree = struct {
    num_nodes: u32 = 0,
    num_data: u32 = 0,

    nodes: [*]Node = undefined,
    data: [*]CM = undefined,

    dimensions: Vec4i = undefined,
    num_cells: Vec4u = undefined,

    inv_dimensions: Vec4f = undefined,

    pub const Log2_cell_dim: u5 = 5;
    pub const Log2_cell_dim4 = std.meta.Vector(4, u5){ Log2_cell_dim, Log2_cell_dim, Log2_cell_dim, 0 };
    pub const Cell_dim: i32 = 1 << Log2_cell_dim;

    pub fn deinit(self: *Gridtree, alloc: Allocator) void {
        alloc.free(self.data[0..self.num_data]);
        alloc.free(self.nodes[0..self.num_nodes]);
    }

    pub fn setDimensions(self: *Gridtree, dimensions: Vec4i, num_cells: Vec4i) void {
        self.dimensions = dimensions;

        const nc = math.vec4iTo4u(num_cells);
        self.num_cells = .{ nc[0], nc[1], nc[2], std.math.maxInt(u32) };

        const id = @splat(4, @as(f32, 1.0)) / math.vec4iTo4f(dimensions);
        self.inv_dimensions = .{ id[0], id[1], id[2], 0.0 };
    }

    pub fn allocateNodes(self: *Gridtree, alloc: Allocator, num_nodes: u32) ![*]Node {
        if (num_nodes != self.num_nodes) {
            alloc.free(self.nodes[0..self.num_nodes]);
        }

        self.num_nodes = num_nodes;
        self.nodes = (try alloc.alloc(Node, num_nodes)).ptr;
        return self.nodes;
    }

    pub fn allocateData(self: *Gridtree, alloc: Allocator, num_data: u32) ![*]CM {
        if (num_data != self.num_data) {
            alloc.free(self.data[0..self.num_data]);
        }

        self.num_data = num_data;
        self.data = (try alloc.alloc(CM, num_data)).ptr;

        return self.data;
    }

    pub fn intersect(self: Gridtree, ray: *Ray) ?CM {
        const p = ray.point(ray.minT());

        const c = math.vec4fTo4i(math.vec4iTo4f(self.dimensions) * p);
        const v = c >> Log2_cell_dim4;
        const uv = math.vec4iTo4u(v);

        if (math.anyGreaterEqual4u(uv, self.num_cells)) {
            return null;
        }

        var index = (uv[2] * self.num_cells[1] + uv[1]) * self.num_cells[0] + uv[0];

        const b0 = v << Log2_cell_dim4;

        var box = Box{ .bounds = .{ b0, b0 + @splat(4, Cell_dim) } };

        while (true) {
            const node = self.nodes[index];

            if (!node.isParent()) {
                break;
            }

            index = node.index();

            const half = (box.bounds[1] - box.bounds[0]) >> @splat(4, @as(u5, 1));
            const center = box.bounds[0] + half;

            const l = c < center;

            if (l[0]) {
                box.bounds[1][0] = center[0];
            } else {
                box.bounds[0][0] = center[0];
                index += 1;
            }

            if (l[1]) {
                box.bounds[1][1] = center[1];
            } else {
                box.bounds[0][1] = center[1];
                index += 2;
            }

            if (l[2]) {
                box.bounds[1][2] = center[2];
            } else {
                box.bounds[0][2] = center[2];
                index += 4;
            }
        }

        const boxf = AABB.init(
            math.vec4iTo4f(box.bounds[0]) * self.inv_dimensions,
            math.vec4iTo4f(box.bounds[1]) * self.inv_dimensions,
        );

        if (boxf.intersectP(ray.*)) |hit_t| {
            if (ray.maxT() > hit_t) {
                ray.setMaxT(hit_t);
            }
        } else {
            ray.setMaxT(ray.minT());
            return null;
        }

        const node = self.nodes[index];

        if (node.isEmpty()) {
            return null;
        }

        return self.data[node.index()];
    }
};
