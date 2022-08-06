const CM = @import("../collision_coefficients.zig").CM;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Ray = math.Ray;
const Vec3i = math.Vec3i;
const Vec3u = math.Vec3u;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Box = struct {
    bounds: [2]Vec3i,
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

    dimensions: Vec3i = undefined,
    num_cells: Vec3u = undefined,

    inv_dimensions: Vec4f = undefined,

    pub const Log2_cell_dim = 5;
    pub const Cell_dim = 1 << Log2_cell_dim;

    pub fn deinit(self: *Gridtree, alloc: Allocator) void {
        alloc.free(self.data[0..self.num_data]);
        alloc.free(self.nodes[0..self.num_nodes]);
    }

    pub fn setDimensions(self: *Gridtree, dimensions: Vec3i, num_cells: Vec3i) void {
        self.dimensions = dimensions;
        self.num_cells = math.vec3iTo3u(num_cells);
        self.inv_dimensions = @splat(4, @as(f32, 1.0)) / math.vec3iTo4f(dimensions);

        std.debug.print("setDimensions({}, {})\n", .{ dimensions, num_cells });
        std.debug.print("{} {} {}\n", .{ self.dimensions, self.num_cells, self.inv_dimensions });
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

        const c = math.vec4fTo3i(math.vec3iTo4f(self.dimensions) * p);
        const v = c.shiftRight(Log2_cell_dim);
        const uv = math.vec3iTo3u(v);

        if (uv.anyGreaterEqual3(self.num_cells)) {
            // std.debug.print("does it happen?? {} {}\n", .{ self.dimensions, self.num_cells });

            return null;
        }

        var index = (uv.v[2] * self.num_cells.v[1] + uv.v[1]) * self.num_cells.v[0] + uv.v[0];

        const b0 = v.shiftLeft(Log2_cell_dim);

        var box = Box{ .bounds = .{ b0, b0.addScalar(Cell_dim) } };

        while (true) {
            const node = self.nodes[index];

            if (!node.isParent()) {
                break;
            }

            index = node.index();

            const half = box.bounds[1].sub(box.bounds[0]).shiftRight(1);
            const center = box.bounds[0].add(half);

            if (c.v[0] < center.v[0]) {
                box.bounds[1].v[0] = center.v[0];
            } else {
                box.bounds[0].v[0] = center.v[0];
                index += 1;
            }

            if (c.v[1] < center.v[1]) {
                box.bounds[1].v[1] = center.v[1];
            } else {
                box.bounds[0].v[1] = center.v[1];
                index += 2;
            }

            if (c.v[2] < center.v[2]) {
                box.bounds[1].v[2] = center.v[2];
            } else {
                box.bounds[0].v[2] = center.v[2];
                index += 4;
            }
        }

        const boxf = AABB.init(
            math.vec3iTo4f(box.bounds[0]) * self.inv_dimensions,
            math.vec3iTo4f(box.bounds[1]) * self.inv_dimensions,
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
