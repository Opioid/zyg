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
        t: f32 = undefined,
        u: f32 = undefined,
        v: f32 = undefined,
        index: u32 = 0xFFFFFFFF,
    };

    nodes: []Node = &.{},
    data: Indexed_data = .{},

    pub fn allocateNodes(self: *Tree, alloc: Allocator, num_nodes: u32) !void {
        self.nodes = try alloc.alloc(Node, num_nodes);
    }

    pub fn deinit(self: *Tree, alloc: Allocator) void {
        self.data.deinit(alloc);
        alloc.free(self.nodes);
    }

    pub fn numTriangles(self: Tree) u32 {
        return self.data.num_triangles;
    }

    pub fn aabb(self: Tree) AABB {
        return self.nodes[0].aabb();
    }

    pub fn intersect(self: Tree, ray: Ray) ?Intersection {
        var tray = ray;

        var stack = NodeStack{};
        var n: u32 = 0;

        var isec: Intersection = .{};

        while (true) {
            const node = self.nodes[n];

            if (0 != node.numIndices()) {
                var i = node.indicesStart();
                const e = node.indicesEnd();
                while (i < e) : (i += 1) {
                    if (self.data.intersect(tray, i)) |hit| {
                        tray.setMaxT(hit.t);
                        isec.u = hit.u;
                        isec.v = hit.v;
                        isec.index = i;
                    }
                }

                if (stack.empty()) {
                    break;
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = self.nodes[a].intersectP(tray);
            var distb = self.nodes[b].intersectP(tray);

            if (dista > distb) {
                std.mem.swap(u32, &a, &b);
                std.mem.swap(f32, &dista, &distb);
            }

            if (std.math.f32_max == dista) {
                if (stack.empty()) {
                    break;
                }

                n = stack.pop();
            } else {
                n = a;
                if (std.math.f32_max != distb) {
                    stack.push(b);
                }
            }
        }

        if (0xFFFFFFFF != isec.index) {
            isec.t = tray.maxT();
            return isec;
        } else {
            return null;
        }
    }

    pub fn intersectP(self: Tree, ray: Ray) bool {
        var stack = NodeStack{};
        var n: u32 = 0;

        while (true) {
            const node = self.nodes[n];

            if (0 != node.numIndices()) {
                var i = node.indicesStart();
                const e = node.indicesEnd();
                while (i < e) : (i += 1) {
                    if (self.data.intersectP(ray, i)) {
                        return true;
                    }
                }

                if (stack.empty()) {
                    break;
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = self.nodes[a].intersectP(ray);
            var distb = self.nodes[b].intersectP(ray);

            if (dista > distb) {
                std.mem.swap(u32, &a, &b);
                std.mem.swap(f32, &dista, &distb);
            }

            if (std.math.f32_max == dista) {
                if (stack.empty()) {
                    break;
                }

                n = stack.pop();
            } else {
                n = a;
                if (std.math.f32_max != distb) {
                    stack.push(b);
                }
            }
        }

        return false;
    }

    pub fn visibility(self: Tree, ray: Ray, entity: usize, filter: ?Filter, worker: *Worker) ?Vec4f {
        var stack = NodeStack{};
        var n: u32 = 0;

        const ray_dir = ray.direction;

        var vis = @splat(4, @as(f32, 1.0));

        while (true) {
            const node = self.nodes[n];

            if (0 != node.numIndices()) {
                var i = node.indicesStart();
                const e = node.indicesEnd();
                while (i < e) : (i += 1) {
                    if (self.data.intersect(ray, i)) |hit| {
                        const normal = self.data.normal(i);
                        const uv = self.data.interpolateUv(hit.u, hit.v, i);

                        const material = worker.scene.propMaterial(entity, self.data.part(i));

                        const tv = material.visibility(ray_dir, normal, uv, filter, worker.scene.*) orelse return null;

                        vis *= tv;
                    }
                }

                if (stack.empty()) {
                    break;
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = self.nodes[a].intersectP(ray);
            var distb = self.nodes[b].intersectP(ray);

            if (dista > distb) {
                std.mem.swap(u32, &a, &b);
                std.mem.swap(f32, &dista, &distb);
            }

            if (std.math.f32_max == dista) {
                if (stack.empty()) {
                    break;
                }

                n = stack.pop();
            } else {
                n = a;
                if (std.math.f32_max != distb) {
                    stack.push(b);
                }
            }
        }

        return vis;
    }
};
