pub const IndexedData = @import("triangle_indexed_data.zig").IndexedData;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const Scene = @import("../../scene.zig").Scene;
const ro = @import("../../ray_offset.zig");
const Worker = @import("../../../rendering/worker.zig").Worker;
const Node = @import("../../bvh/node.zig").Node;
const NodeStack = @import("../../bvh/node_stack.zig").NodeStack;
const int = @import("../../shape/intersection.zig");
const Intersection = int.Intersection;
const Volume = int.Volume;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const AABB = math.AABB;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Tree = struct {
    nodes: []Node = &.{},
    data: IndexedData = .{},

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

    pub fn intersect(self: Tree, ray: Ray) Intersection {
        var tray = ray;

        var stack = NodeStack{};
        var n: u32 = 0;

        var hpoint = Intersection{};

        const nodes = self.nodes;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                var i = node.indicesStart();
                const e = i + num;
                while (i < e) : (i += 1) {
                    if (self.data.intersect(tray, i)) |hit| {
                        tray.max_t = hit.t;
                        hpoint.t = hit.t;
                        hpoint.u = hit.u;
                        hpoint.v = hit.v;
                        hpoint.primitive = i;
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

            if (std.math.floatMax(f32) == dista) {
                n = stack.pop();
            } else {
                n = a;
                if (std.math.floatMax(f32) != distb) {
                    stack.push(b);
                }
            }
        }

        return hpoint;
    }

    pub fn intersectP(self: Tree, ray: Ray) bool {
        var stack = NodeStack{};
        var n: u32 = 0;

        const nodes = self.nodes;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                var i = node.indicesStart();
                const e = i + num;
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

            if (std.math.floatMax(f32) == dista) {
                n = stack.pop();
            } else {
                n = a;
                if (std.math.floatMax(f32) != distb) {
                    stack.push(b);
                }
            }
        }

        return false;
    }

    pub fn visibility(self: Tree, ray: Ray, entity: u32, sampler: *Sampler, scene: *const Scene, tr: *Vec4f) bool {
        var stack = NodeStack{};
        var n: u32 = 0;

        const ray_dir = ray.direction;

        const nodes = self.nodes;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                var i = node.indicesStart();
                const e = i + num;
                while (i < e) : (i += 1) {
                    if (self.data.intersect(ray, i)) |hit| {
                        const itri = self.data.indexTriangle(i);
                        const material = scene.propMaterial(entity, itri.part);

                        if (material.evaluateVisibility()) {
                            const normal = self.data.normal(itri);
                            const uv = self.data.interpolateUv(itri, hit.u, hit.v);

                            if (!material.visibility(ray_dir, normal, uv, sampler, scene, tr)) {
                                return false;
                            }
                        } else {
                            return false;
                        }
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

    pub fn transmittance(
        self: Tree,
        ray: Ray,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *Worker,
        tr: *Vec4f,
    ) bool {
        const material = worker.scene.propMaterial(entity, 0);
        const data = self.data;
        const RayMaxT = ray.max_t;

        var tray = ray;
        tray.max_t = ro.RayMaxT;

        while (true) {
            const hit = self.intersect(tray);
            if (Intersection.Null == hit.primitive) {
                break;
            }

            const n = data.normal(data.indexTriangle(hit.primitive));

            if (math.dot3(n, ray.direction) > 0.0) {
                tray.max_t = math.min(hit.t, RayMaxT);

                if (!worker.propTransmittance(tray, material, entity, depth, sampler, tr)) {
                    return false;
                }
            }

            const ray_min_t = ro.offsetF(hit.t);
            if (ray_min_t > RayMaxT) {
                break;
            }

            tray.setMinMaxT(ray_min_t, ro.RayMaxT);
        }

        return true;
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
        const RayMaxT = ray.max_t;

        var tray = ray;
        tray.max_t = ro.RayMaxT;

        var tr: Vec4f = @splat(1.0);

        while (true) {
            const hit = self.intersect(tray);
            if (Intersection.Null == hit.primitive) {
                break;
            }

            const n = data.normal(data.indexTriangle(hit.primitive));

            if (math.dot3(n, ray.direction) > 0.0) {
                tray.max_t = math.min(hit.t, RayMaxT);

                var result = worker.propScatter(tray, throughput, material, entity, depth, sampler);

                tr *= result.tr;

                if (.Pass != result.event) {
                    result.tr = tr;
                    return result;
                }
            }

            const ray_min_t = ro.offsetF(hit.t);
            if (ray_min_t > RayMaxT) {
                break;
            }

            tray.setMinMaxT(ray_min_t, ro.RayMaxT);
        }

        return Volume.initPass(tr);
    }
};
