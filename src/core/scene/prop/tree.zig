const Prop = @import("prop.zig").Prop;
const Intersection = @import("intersection.zig").Intersection;
const Interpolation = @import("../shape/intersection.zig").Interpolation;
const Node = @import("../bvh/node.zig").Node;
const NodeStack = @import("../bvh/node_stack.zig").NodeStack;
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

    pub fn deinit(self: *Tree, alloc: Allocator) void {
        alloc.free(self.indices[0..self.num_indices]);
        alloc.free(self.nodes[0..self.num_nodes]);
    }

    pub fn allocateNodes(self: *Tree, alloc: Allocator, num_nodes: u32) !void {
        if (num_nodes != self.num_nodes) {
            self.nodes = (try alloc.realloc(self.nodes[0..self.num_nodes], num_nodes)).ptr;
            self.num_nodes = num_nodes;
        }
    }

    pub fn allocateIndices(self: *Tree, alloc: Allocator, num_indices: u32) !void {
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

    pub fn intersect(self: *const Tree, ray: *Ray, worker: *Worker, ipo: Interpolation, isec: *Intersection) bool {
        if (0 == self.num_nodes) {
            return false;
        }

        var stack = NodeStack{};

        var hit = false;
        var prop = Prop.Null;
        var n: u32 = 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    if (props[p].intersect(p, ray, worker, ipo, &isec.geo)) {
                        prop = p;
                        hit = true;
                    }
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(ray.ray);
            var distb = nodes[b].intersect(ray.ray);

            if (dista > distb) {
                std.mem.swap(u32, &a, &b);
                std.mem.swap(f32, &dista, &distb);
            }

            if (std.math.f32_max == dista) {
                n = stack.pop();
            } else {
                n = a;
                if (std.math.f32_max != distb) {
                    stack.push(b);
                }
            }
        }

        for (self.infinite_props[0..self.num_infinite_props]) |p| {
            if (props[p].intersect(p, ray, worker, ipo, &isec.geo)) {
                prop = p;
                hit = true;
            }
        }

        isec.prop = prop;
        isec.subsurface = false;
        return hit;
    }

    pub fn intersectShadow(self: *const Tree, ray: *Ray, worker: *Worker, isec: *Intersection) bool {
        if (0 == self.num_nodes) {
            return false;
        }

        var stack = NodeStack{};

        var hit = false;
        var prop = Prop.Null;
        var n: u32 = 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    if (props[p].intersectShadow(p, ray, worker, &isec.geo)) {
                        prop = p;
                        hit = true;
                    }
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(ray.ray);
            var distb = nodes[b].intersect(ray.ray);

            if (dista > distb) {
                std.mem.swap(u32, &a, &b);
                std.mem.swap(f32, &dista, &distb);
            }

            if (std.math.f32_max == dista) {
                n = stack.pop();
            } else {
                n = a;
                if (std.math.f32_max != distb) {
                    stack.push(b);
                }
            }
        }

        for (self.infinite_props[0..self.num_infinite_props]) |p| {
            if (props[p].intersectShadow(p, ray, worker, &isec.geo)) {
                prop = p;
                hit = true;
            }
        }

        isec.prop = prop;
        isec.subsurface = false;
        return hit;
    }

    pub fn intersectP(self: *const Tree, ray: *const Ray, worker: *Worker) bool {
        if (0 == self.num_nodes) {
            return false;
        }

        var stack = NodeStack{};

        var n: u32 = 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    if (props[p].intersectP(p, ray, worker)) {
                        return true;
                    }
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(ray.ray);
            var distb = nodes[b].intersect(ray.ray);

            if (dista > distb) {
                std.mem.swap(u32, &a, &b);
                std.mem.swap(f32, &dista, &distb);
            }

            if (std.math.f32_max == dista) {
                n = stack.pop();
            } else {
                n = a;
                if (std.math.f32_max != distb) {
                    stack.push(b);
                }
            }
        }

        for (self.infinite_props[0..self.num_infinite_props]) |p| {
            if (props[p].intersectP(p, ray, worker)) {
                return true;
            }
        }

        return false;
    }

    pub fn visibility(self: *const Tree, ray: *const Ray, filter: ?Filter, worker: *Worker) ?Vec4f {
        if (0 == self.num_nodes) {
            return @splat(4, @as(f32, 1.0));
        }

        var stack = NodeStack{};

        var vis = @splat(4, @as(f32, 1.0));
        var n: u32 = 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    const tv = props[p].visibility(p, ray, filter, worker) orelse return null;
                    vis *= tv;
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(ray.ray);
            var distb = nodes[b].intersect(ray.ray);

            if (dista > distb) {
                std.mem.swap(u32, &a, &b);
                std.mem.swap(f32, &dista, &distb);
            }

            if (std.math.f32_max == dista) {
                n = stack.pop();
            } else {
                n = a;
                if (std.math.f32_max != distb) {
                    stack.push(b);
                }
            }
        }

        for (self.infinite_props[0..self.num_infinite_props]) |p| {
            const tv = props[p].visibility(p, ray, filter, worker) orelse return null;
            vis *= tv;
        }

        return vis;
    }
};
