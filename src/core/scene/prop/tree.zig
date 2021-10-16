const Prop = @import("prop.zig").Prop;
const Intersection = @import("intersection.zig").Intersection;
const Interpolation = @import("../shape/intersection.zig").Interpolation;
const Node = @import("../bvh/node.zig").Node;
const Ray = @import("../ray.zig").Ray;
const Filter = @import("../../image/texture/sampler.zig").Filter;
const Worker = @import("../worker.zig").Worker;
const math = @import("base").math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Tree = struct {
    num_nodes: u32 = 0,
    num_indices: u32 = 0,
    num_infinite_props: u32 = 0,

    nodes: [*]Node = undefined,
    indices: [*]u32 = undefined,
    infinite_props: [*]const u32 = undefined,
    props: [*]const Prop = undefined,

    pub fn deinit(self: *Tree, alloc: *Allocator) void {
        alloc.free(self.indices[0..self.num_indices]);
        alloc.free(self.nodes[0..self.num_nodes]);
    }

    pub fn allocateNodes(self: *Tree, alloc: *Allocator, num_nodes: u32) !void {
        if (num_nodes != self.num_nodes) {
            self.nodes = (try alloc.realloc(self.nodes[0..self.num_nodes], num_nodes)).ptr;
            self.num_nodes = num_nodes;
        }
    }

    pub fn allocateIndices(self: *Tree, alloc: *Allocator, num_indices: u32) !void {
        if (num_indices != self.num_indices) {
            self.indices = (try alloc.realloc(self.indices[0..self.num_indices], num_indices)).ptr;
            self.num_indices = num_indices;
        }
    }

    pub fn setProps(self: *Tree, infinite_props: []const u32, props: []const Prop) void {
        self.num_infinite_props = @intCast(u32, infinite_props.len);
        self.infinite_props = infinite_props.ptr;
        self.props = props.ptr;
    }

    pub fn aabb(self: Tree) AABB {
        if (0 == self.num_nodes) {
            return math.aabb.empty;
        }

        return self.nodes[0].aabb();
    }

    pub fn intersect(self: Tree, ray: *Ray, worker: *Worker, ipo: Interpolation, isec: *Intersection) bool {
        var stack = &worker.node_stack;
        stack.clear();
        if (0 != self.num_nodes) {
            stack.push(0);
        }

        var hit = false;
        var prop = Prop.Null;
        var n: u32 = 0;

        const ray_signs = [4]u32{
            @boolToInt(ray.ray.inv_direction[0] < 0.0),
            @boolToInt(ray.ray.inv_direction[1] < 0.0),
            @boolToInt(ray.ray.inv_direction[2] < 0.0),
            @boolToInt(ray.ray.inv_direction[3] < 0.0),
        };

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (!stack.empty()) {
            const node = &nodes[n];

            if (node.intersectP(ray.ray)) {
                if (0 == node.numIndices()) {
                    const a = node.children();
                    const b = a + 1;

                    if (0 == ray_signs[node.axis()]) {
                        stack.push(b);
                        n = a;
                    } else {
                        stack.push(a);
                        n = b;
                    }

                    continue;
                }

                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    if (props[p].intersect(p, ray, worker, ipo, &isec.geo)) {
                        prop = p;
                        hit = true;
                    }
                }
            }

            n = stack.pop();
        }

        for (self.infinite_props[0..self.num_infinite_props]) |p| {
            if (props[p].intersect(p, ray, worker, ipo, &isec.geo)) {
                prop = p;
                hit = true;
            }
        }

        isec.prop = prop;

        return hit;
    }

    pub fn intersectP(self: Tree, ray: Ray, worker: *Worker) bool {
        var stack = &worker.node_stack;
        stack.clear();
        if (0 != self.num_nodes) {
            stack.push(0);
        }

        var n: u32 = 0;

        const ray_signs = [4]u32{
            @boolToInt(ray.ray.inv_direction[0] < 0.0),
            @boolToInt(ray.ray.inv_direction[1] < 0.0),
            @boolToInt(ray.ray.inv_direction[2] < 0.0),
            @boolToInt(ray.ray.inv_direction[3] < 0.0),
        };

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (!stack.empty()) {
            const node = &nodes[n];

            if (node.intersectP(ray.ray)) {
                if (0 == node.numIndices()) {
                    const a = node.children();
                    const b = a + 1;

                    if (0 == ray_signs[node.axis()]) {
                        stack.push(b);
                        n = a;
                    } else {
                        stack.push(a);
                        n = b;
                    }

                    continue;
                }

                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    if (props[p].intersectP(p, ray, worker)) {
                        return true;
                    }
                }
            }

            n = stack.pop();
        }

        for (self.infinite_props[0..self.num_infinite_props]) |p| {
            if (props[p].intersectP(p, ray, worker)) {
                return true;
            }
        }

        return false;
    }

    pub fn visibility(self: Tree, ray: Ray, filter: ?Filter, worker: *Worker) ?Vec4f {
        var stack = &worker.node_stack;
        stack.clear();
        if (0 != self.num_nodes) {
            stack.push(0);
        }

        var vis = @splat(4, @as(f32, 1.0));
        var n: u32 = 0;

        const ray_signs = [4]u32{
            @boolToInt(ray.ray.inv_direction[0] < 0.0),
            @boolToInt(ray.ray.inv_direction[1] < 0.0),
            @boolToInt(ray.ray.inv_direction[2] < 0.0),
            @boolToInt(ray.ray.inv_direction[3] < 0.0),
        };

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (!stack.empty()) {
            const node = &nodes[n];

            if (node.intersectP(ray.ray)) {
                if (0 == node.numIndices()) {
                    const a = node.children();
                    const b = a + 1;

                    if (0 == ray_signs[node.axis()]) {
                        stack.push(b);
                        n = a;
                    } else {
                        stack.push(a);
                        n = b;
                    }

                    continue;
                }

                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    const tv = props[p].visibility(p, ray, filter, worker) orelse return null;
                    vis *= tv;
                }
            }

            n = stack.pop();
        }

        for (self.infinite_props[0..self.num_infinite_props]) |p| {
            const tv = props[p].visibility(p, ray, filter, worker) orelse return null;
            vis *= tv;
        }

        return vis;
    }
};
