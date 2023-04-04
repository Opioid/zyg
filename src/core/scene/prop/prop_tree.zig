const Prop = @import("prop.zig").Prop;
const Intersection = @import("intersection.zig").Intersection;
const Ray = @import("../ray.zig").Ray;
const Scene = @import("../scene.zig").Scene;
const Interpolation = @import("../shape/intersection.zig").Interpolation;
const Node = @import("../bvh/node.zig").Node;
const NodeStack = @import("../bvh/node_stack.zig").NodeStack;
const Filter = @import("../../image/texture/texture_sampler.zig").Filter;
const Worker = @import("../../rendering/worker.zig").Worker;

const math = @import("base").math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Tree = struct {
    num_nodes: u32 = 0,
    num_indices: u32 = 0,
    num_infinite_props: u32 = 0,
    infinite_t_max: f32 = 0.0,

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

    pub fn setProps(self: *Tree, infinite_props: []const u32, props: []const Prop, scene: *const Scene) void {
        self.num_infinite_props = @intCast(u32, infinite_props.len);
        self.infinite_props = infinite_props.ptr;
        self.props = props.ptr;

        var t_max: f32 = std.math.f32_max;
        for (infinite_props) |i| {
            t_max = std.math.min(t_max, scene.propShape(i).infiniteTMax());
        }
        self.infinite_t_max = t_max;
    }

    pub fn aabb(self: Tree) AABB {
        if (0 == self.num_nodes) {
            return math.aabb.Empty;
        }

        return self.nodes[0].aabb();
    }

    pub fn intersect(self: Tree, ray: *Ray, scene: *const Scene, ipo: Interpolation, isec: *Intersection) bool {
        var stack = NodeStack{};

        var hit = false;
        var prop = Prop.Null;
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    if (props[p].intersect(p, ray, scene, ipo, &isec.geo)) {
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

        if (ray.ray.maxT() >= self.infinite_t_max) {
            for (self.infinite_props[0..self.num_infinite_props]) |p| {
                if (props[p].intersect(p, ray, scene, ipo, &isec.geo)) {
                    prop = p;
                    hit = true;
                }
            }
        }

        isec.prop = prop;
        isec.subsurface = false;
        return hit;
    }

    pub fn intersectShadow(self: Tree, ray: *Ray, scene: *const Scene, isec: *Intersection) bool {
        var stack = NodeStack{};

        var hit = false;
        var prop = Prop.Null;
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    if (props[p].intersectShadow(p, ray, scene, &isec.geo)) {
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

        if (ray.ray.maxT() >= self.infinite_t_max) {
            for (self.infinite_props[0..self.num_infinite_props]) |p| {
                if (props[p].intersectShadow(p, ray, scene, &isec.geo)) {
                    prop = p;
                    hit = true;
                }
            }
        }

        isec.prop = prop;
        isec.subsurface = false;
        return hit;
    }

    pub fn intersectP(self: Tree, ray: Ray, scene: *const Scene) bool {
        var stack = NodeStack{};

        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    if (props[p].intersectP(p, ray, scene)) {
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

        if (ray.ray.maxT() >= self.infinite_t_max) {
            for (self.infinite_props[0..self.num_infinite_props]) |p| {
                if (props[p].intersectP(p, ray, scene)) {
                    return true;
                }
            }
        }

        return false;
    }

    pub fn visibility(self: Tree, ray: Ray, filter: ?Filter, scene: *const Scene) ?Vec4f {
        var stack = NodeStack{};

        var vis = @splat(4, @as(f32, 1.0));
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    vis *= props[p].visibility(p, ray, filter, scene) orelse return null;
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

        if (ray.ray.maxT() >= self.infinite_t_max) {
            for (self.infinite_props[0..self.num_infinite_props]) |p| {
                vis *= props[p].visibility(p, ray, filter, scene) orelse return null;
            }
        }

        return vis;
    }

    pub fn transmittance(self: Tree, ray: Ray, filter: ?Filter, worker: *Worker) ?Vec4f {
        var stack = NodeStack{};

        var tr = @splat(4, @as(f32, 1.0));
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    tr *= props[p].transmittance(p, ray, filter, worker) orelse return null;
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

        if (ray.ray.maxT() >= self.infinite_t_max) {
            for (self.infinite_props[0..self.num_infinite_props]) |p| {
                tr *= props[p].transmittance(p, ray, filter, worker) orelse return null;
            }
        }

        return tr;
    }
};
