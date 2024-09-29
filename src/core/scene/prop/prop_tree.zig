const Prop = @import("prop.zig").Prop;
const Probe = @import("../vertex.zig").Vertex.Probe;
const Scene = @import("../scene.zig").Scene;
const int = @import("../shape/intersection.zig");
const Fragment = int.Fragment;
const Interpolation = int.Interpolation;
const Volume = int.Volume;
const Node = @import("../bvh/node.zig").Node;
const NodeStack = @import("../bvh/node_stack.zig").NodeStack;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
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
        self.num_infinite_props = @intCast(infinite_props.len);
        self.infinite_props = infinite_props.ptr;
        self.props = props.ptr;

        var t_max: f32 = std.math.floatMax(f32);
        for (infinite_props) |i| {
            t_max = math.min(t_max, scene.propShape(i).infiniteTMax());
        }
        self.infinite_t_max = t_max;
    }

    pub fn aabb(self: *const Tree) AABB {
        if (0 == self.num_nodes) {
            return math.aabb.Empty;
        }

        return self.nodes[0].aabb();
    }

    pub fn intersect(self: *const Tree, probe: *Probe, frag: *Fragment, scene: *const Scene, ipo: Interpolation) bool {
        var stack = NodeStack{};

        var prop = Prop.Null;
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    if (props[p].intersect(p, probe, frag, scene)) {
                        prop = p;
                    }
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(probe.ray);
            var distb = nodes[b].intersect(probe.ray);

            if (dista > distb) {
                std.mem.swap(u32, &a, &b);
                std.mem.swap(f32, &dista, &distb);
            }

            if (std.math.floatMax(f32) == dista) {
                n = stack.pop();
            } else {
                n = a;
                if (std.math.floatMax(f32) != distb) {
                    stack.push(b);
                }
            }
        }

        if (probe.ray.maxT() >= self.infinite_t_max) {
            for (self.infinite_props[0..self.num_infinite_props]) |p| {
                if (props[p].intersect(p, probe, frag, scene)) {
                    prop = p;
                }
            }
        }

        const hit = Prop.Null != prop;

        if (hit) {
            props[prop].fragment(probe, ipo, frag, scene);
        }

        frag.prop = prop;
        return hit;
    }

    pub fn intersectP(self: *const Tree, probe: *const Probe, scene: *const Scene) bool {
        var stack = NodeStack{};

        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    if (props[p].intersectP(p, probe, scene)) {
                        return true;
                    }
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(probe.ray);
            var distb = nodes[b].intersect(probe.ray);

            if (dista > distb) {
                std.mem.swap(u32, &a, &b);
                std.mem.swap(f32, &dista, &distb);
            }

            if (std.math.floatMax(f32) == dista) {
                n = stack.pop();
            } else {
                n = a;
                if (std.math.floatMax(f32) != distb) {
                    stack.push(b);
                }
            }
        }

        if (probe.ray.maxT() >= self.infinite_t_max) {
            for (self.infinite_props[0..self.num_infinite_props]) |p| {
                if (props[p].intersectP(p, probe, scene)) {
                    return true;
                }
            }
        }

        return false;
    }

    pub fn visibility(self: *const Tree, probe: *const Probe, sampler: *Sampler, worker: *Worker) ?Vec4f {
        var stack = NodeStack{};

        var vis: Vec4f = @splat(1.0);
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    vis *= props[p].visibility(p, probe, sampler, worker) orelse return null;
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(probe.ray);
            var distb = nodes[b].intersect(probe.ray);

            if (dista > distb) {
                std.mem.swap(u32, &a, &b);
                std.mem.swap(f32, &dista, &distb);
            }

            if (std.math.floatMax(f32) == dista) {
                n = stack.pop();
            } else {
                n = a;
                if (std.math.floatMax(f32) != distb) {
                    stack.push(b);
                }
            }
        }

        if (probe.ray.maxT() >= self.infinite_t_max) {
            for (self.infinite_props[0..self.num_infinite_props]) |p| {
                vis *= props[p].visibility(p, probe, sampler, worker) orelse return null;
            }
        }

        return vis;
    }

    pub fn scatter(self: *const Tree, probe: *Probe, frag: *Fragment, throughput: *Vec4f, sampler: *Sampler, worker: *Worker) bool {
        var stack = NodeStack{};

        var result = Volume.initPass(@splat(1.0));
        var prop = Prop.Null;
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const props = self.props;
        const finite_props = self.indices;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                for (finite_props[node.indicesStart()..node.indicesEnd()]) |p| {
                    const lr = props[p].scatter(p, probe, throughput.*, sampler, worker);

                    if (.Pass != lr.event) {
                        probe.ray.setMaxT(lr.t);
                        result = lr;
                        prop = p;
                    } else if (.Pass == result.event) {
                        result.tr *= lr.tr;
                    }
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(probe.ray);
            var distb = nodes[b].intersect(probe.ray);

            if (dista > distb) {
                std.mem.swap(u32, &a, &b);
                std.mem.swap(f32, &dista, &distb);
            }

            if (std.math.floatMax(f32) == dista) {
                n = stack.pop();
            } else {
                n = a;
                if (std.math.floatMax(f32) != distb) {
                    stack.push(b);
                }
            }
        }

        frag.setVolume(result);
        throughput.* *= result.tr;

        if (.Pass != result.event) {
            frag.prop = prop;
            frag.part = 0;
            frag.p = probe.ray.point(result.t);
            const vn = -probe.ray.direction;
            frag.geo_n = vn;
            frag.n = vn;
            frag.uvw = result.uvw;

            return true;
        }

        return false;
    }
};
