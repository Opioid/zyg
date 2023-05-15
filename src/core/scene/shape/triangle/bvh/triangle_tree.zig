pub const Indexed_data = @import("indexed_data.zig").Indexed_data;
const Trafo = @import("../../../composed_transformation.zig").ComposedTransformation;
const Scene = @import("../../../scene.zig").Scene;
const ro = @import("../../../ray_offset.zig");
const Worker = @import("../../../../rendering/worker.zig").Worker;
const Node = @import("../../../bvh/node.zig").Node;
const NodeStack = @import("../../../bvh/node_stack.zig").NodeStack;
const Volume = @import("../../../shape/intersection.zig").Volume;
const Sampler = @import("../../../../sampler/sampler.zig").Sampler;

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

        const nodes = self.nodes;

        while (NodeStack.End != n) {
            const node = nodes[n];

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

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(tray);
            var distb = nodes[b].intersect(tray);

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

        const nodes = self.nodes;

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                var i = node.indicesStart();
                const e = node.indicesEnd();
                while (i < e) : (i += 1) {
                    if (self.data.intersectP(ray, i)) {
                        return true;
                    }
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(ray);
            var distb = nodes[b].intersect(ray);

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

        return false;
    }

    pub fn visibility(self: Tree, ray: Ray, entity: u32, sampler: *Sampler, scene: *const Scene) ?Vec4f {
        var stack = NodeStack{};
        var n: u32 = 0;

        const ray_dir = ray.direction;

        const nodes = self.nodes;

        var vis = @splat(4, @as(f32, 1.0));

        while (NodeStack.End != n) {
            const node = nodes[n];

            if (0 != node.numIndices()) {
                var i = node.indicesStart();
                const e = node.indicesEnd();
                while (i < e) : (i += 1) {
                    if (self.data.intersect(ray, i)) |hit| {
                        const material = scene.propMaterial(entity, self.data.part(i));

                        if (material.evaluateVisibility()) {
                            const normal = self.data.normal(i);
                            const uv = self.data.interpolateUv(hit.u, hit.v, i);

                            const tv = material.visibility(ray_dir, normal, uv, sampler, scene) orelse return null;

                            vis *= tv;
                        } else return null;
                    }
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(ray);
            var distb = nodes[b].intersect(ray);

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

        return vis;
    }

    pub fn transmittance(
        self: Tree,
        ray: Ray,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *Worker,
    ) ?Vec4f {
        const material = worker.scene.propMaterial(entity, 0);
        const data = self.data;
        const ray_max_t = ray.maxT();

        var tray = ray;
        var tr = @splat(4, @as(f32, 1.0));

        while (true) {
            const hit = self.intersect(tray) orelse break;
            const n = data.normal(hit.index);

            if (math.dot3(n, ray.direction) > 0.0) {
                tray.setMaxT(hit.t);

                tr *= worker.propTransmittance(tray, material, entity, depth, sampler) orelse return null;
            }

            const ray_min_t = ro.offsetF(hit.t);
            if (ray_min_t > ray_max_t) {
                break;
            }

            tray.setMinMaxT(ray_min_t, ray_max_t);
        }

        return tr;
    }

    pub fn scatter(
        self: Tree,
        ray: Ray,
        throughput: Vec4f,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *Worker,
    ) Volume {
        const material = worker.scene.propMaterial(entity, 0);
        const data = self.data;
        const ray_max_t = ray.maxT();

        var tray = ray;
        var tr = @splat(4, @as(f32, 1.0));

        while (true) {
            const hit = self.intersect(tray) orelse break;
            const n = data.normal(hit.index);

            if (math.dot3(n, ray.direction) > 0.0) {
                tray.setMaxT(hit.t);

                var result = worker.propScatter(tray, throughput, material, entity, depth, sampler);

                tr *= result.tr;

                if (.Pass != result.event) {
                    result.tr = tr;
                    return result;
                }
            }

            const ray_min_t = ro.offsetF(hit.t);
            if (ray_min_t > ray_max_t) {
                break;
            }

            tray.setMinMaxT(ray_min_t, ray_max_t);
        }

        return Volume.initPass(tr);
    }
};
