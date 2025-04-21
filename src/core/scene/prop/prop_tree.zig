const Prop = @import("prop.zig").Prop;
const Vertex = @import("../vertex.zig").Vertex;
const Scene = @import("../scene.zig").Scene;
const int = @import("../shape/intersection.zig");
const Fragment = int.Fragment;
const Volume = int.Volume;
const Probe = @import("../shape/probe.zig").Probe;
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

    nodes: [*]Node = undefined,
    indices: [*]u32 = undefined,

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

    pub fn aabb(self: Tree) AABB {
        if (0 == self.num_nodes) {
            return math.aabb.Empty;
        }

        return self.nodes[0].aabb();
    }

    pub fn intersect(self: Tree, probe: *Probe, frag: *Fragment, scene: *const Scene) bool {
        var stack = NodeStack{};

        var prop = Prop.Null;
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const instances = self.indices;
        const props = scene.props.items.ptr;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                const start = node.indicesStart();
                const end = start + num;
                for (instances[start..end]) |p| {
                    if (props[p].intersect(p, probe.*, frag, scene)) {
                        probe.ray.max_t = frag.isec.t;
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

        const hit = Prop.Null != prop;

        if (hit) {
            props[prop].fragment(probe.*, frag, scene);
        }

        frag.prop = prop;
        return hit;
    }

    pub fn visibility(self: Tree, probe: Probe, sampler: *Sampler, worker: *Worker, tr: *Vec4f) bool {
        var stack = NodeStack{};

        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const instances = self.indices;
        const props = worker.scene.props.items.ptr;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                const start = node.indicesStart();
                const end = start + num;
                for (instances[start..end]) |p| {
                    if (!props[p].visibility(p, probe, sampler, worker, tr)) {
                        return false;
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

        return true;
    }

    pub fn emission(
        self: Tree,
        vertex: *const Vertex,
        frag: *Fragment,
        split_threshold: f32,
        sampler: *Sampler,
        worker: *const Worker,
    ) Vec4f {
        var stack = NodeStack{};

        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        var energy: Vec4f = @splat(0.0);

        const nodes = self.nodes;
        const instances = self.indices;
        const props = worker.scene.props.items.ptr;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                const start = node.indicesStart();
                const end = start + num;
                for (instances[start..end]) |p| {
                    energy += props[p].emission(p, vertex, frag, split_threshold, sampler, worker);
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(vertex.probe.ray);
            var distb = nodes[b].intersect(vertex.probe.ray);

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

        return energy;
    }

    pub fn scatter(self: Tree, probe: *Probe, frag: *Fragment, throughput: *Vec4f, sampler: *Sampler, worker: *Worker) void {
        var stack = NodeStack{};

        var result = Volume.initPass(@splat(1.0));
        var prop = Prop.Null;
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        const nodes = self.nodes;
        const instances = self.indices;
        const props = worker.scene.props.items.ptr;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                const start = node.indicesStart();
                const end = start + num;
                for (instances[start..end]) |p| {
                    const lr = props[p].scatter(p, probe.*, frag, throughput.*, sampler, worker);

                    if (.Pass != lr.event) {
                        probe.ray.max_t = lr.t;
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

        frag.event = result.event;
        frag.vol_li = result.li;

        throughput.* *= result.tr;

        if (.Pass != result.event) {
            frag.prop = prop;
            frag.part = 0;
            frag.p = probe.ray.point(result.t);
            const vn = -probe.ray.direction;
            frag.geo_n = vn;
            frag.n = vn;
            frag.uvw = result.uvw;
        }
    }
};
