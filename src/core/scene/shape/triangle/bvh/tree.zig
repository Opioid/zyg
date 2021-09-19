pub const Indexed_data = @import("indexed_data.zig").Indexed_data;
const Worker = @import("../../../worker.zig").Worker;
const Filter = @import("../../../../image/texture/sampler.zig").Filter;
const NodeStack = @import("../../node_stack.zig").NodeStack;
const Node = @import("../../../bvh/node.zig").Node;
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const AABB = math.AABB;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Tree = struct {
    pub const Intersection = struct {
        u: f32 = undefined,
        v: f32 = undefined,
        index: u32 = 0xFFFFFFFF,
    };

    nodes: []Node = &.{},
    data: Indexed_data = .{},

    pub fn allocateNodes(self: *Tree, alloc: *Allocator, num_nodes: u32) ![]Node {
        self.nodes = try alloc.alloc(Node, num_nodes);

        return self.nodes;
    }

    pub fn deinit(self: *Tree, alloc: *Allocator) void {
        self.data.deinit(alloc);
        alloc.free(self.nodes);
    }

    pub fn aabb(self: Tree) AABB {
        return self.nodes[0].aabb();
    }

    pub fn intersect(self: Tree, ray: *Ray, nodes: *NodeStack) ?Intersection {
        const ray_signs = [3]u32{
            if (ray.inv_direction[0] >= 0.0) 0 else 1,
            if (ray.inv_direction[1] >= 0.0) 0 else 1,
            if (ray.inv_direction[2] >= 0.0) 0 else 1,
        };

        nodes.push(0xFFFFFFFF);
        var n: u32 = 0;

        var isec: Intersection = .{};

        while (0xFFFFFFFF != n) {
            const node = self.nodes[n];

            if (node.intersectP(ray.*)) {
                if (0 == node.numIndices()) {
                    const a = node.children();
                    const b = a + 1;

                    if (0 == ray_signs[node.axis()]) {
                        nodes.push(b);
                        n = a;
                    } else {
                        nodes.push(a);
                        n = b;
                    }

                    continue;
                }

                var i = node.indicesStart();
                const e = node.indicesEnd();
                while (i < e) : (i += 1) {
                    if (self.data.intersect(ray, i)) |hit| {
                        isec.u = hit.u;
                        isec.v = hit.v;
                        isec.index = i;
                    }
                }
            }

            n = nodes.pop();
        }

        return if (0xFFFFFFFF != isec.index) isec else null;
    }

    pub fn intersectP(self: Tree, ray: Ray, nodes: *NodeStack) bool {
        const ray_signs = [3]u32{
            if (ray.inv_direction[0] >= 0.0) 0 else 1,
            if (ray.inv_direction[1] >= 0.0) 0 else 1,
            if (ray.inv_direction[2] >= 0.0) 0 else 1,
        };

        nodes.push(0xFFFFFFFF);
        var n: u32 = 0;

        while (0xFFFFFFFF != n) {
            const node = self.nodes[n];

            if (node.intersectP(ray)) {
                if (0 == node.numIndices()) {
                    const a = node.children();
                    const b = a + 1;

                    if (0 == ray_signs[node.axis()]) {
                        nodes.push(b);
                        n = a;
                    } else {
                        nodes.push(a);
                        n = b;
                    }

                    continue;
                }

                var i = node.indicesStart();
                const e = node.indicesEnd();
                while (i < e) : (i += 1) {
                    if (self.data.intersectP(ray, i)) {
                        return true;
                    }
                }
            }

            n = nodes.pop();
        }

        return false;
    }

    pub fn visibility(self: Tree, ray: *Ray, entity: usize, filter: ?Filter, worker: *Worker, vis: *Vec4f) bool {
        const ray_signs = [3]u32{
            if (ray.inv_direction[0] >= 0.0) 0 else 1,
            if (ray.inv_direction[1] >= 0.0) 0 else 1,
            if (ray.inv_direction[2] >= 0.0) 0 else 1,
        };

        var nodes = worker.node_stack;

        nodes.push(0xFFFFFFFF);
        var n: u32 = 0;

        var local_vis = @splat(4, @as(f32, 1.0));

        const max_t = ray.maxT();

        while (0xFFFFFFFF != n) {
            const node = self.nodes[n];

            if (node.intersectP(ray.*)) {
                if (0 == node.numIndices()) {
                    const a = node.children();
                    const b = a + 1;

                    if (0 == ray_signs[node.axis()]) {
                        nodes.push(b);
                        n = a;
                    } else {
                        nodes.push(a);
                        n = b;
                    }

                    continue;
                }

                var i = node.indicesStart();
                const e = node.indicesEnd();
                while (i < e) : (i += 1) {
                    if (self.data.intersect(ray, i)) |hit| {
                        const uv = self.data.interpolateUV(hit.u, hit.v, i);

                        const material = worker.scene.propMaterial(entity, self.data.part(i));

                        var tv: Vec4f = undefined;
                        if (!material.visibility(uv, filter, worker.*, &tv)) {
                            return false;
                        }

                        local_vis *= tv;

                        // ray_max_t has changed if intersect() returns true!
                        ray.setMaxT(max_t);
                    }
                }
            }

            n = nodes.pop();
        }

        vis.* = local_vis;
        return true;
    }
};
