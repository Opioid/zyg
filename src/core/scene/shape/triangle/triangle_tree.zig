pub const IndexedData = @import("triangle_indexed_data.zig").IndexedData;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const Vertex = @import("../../vertex.zig").Vertex;
const Scene = @import("../../scene.zig").Scene;
const ro = @import("../../ray_offset.zig");
const Worker = @import("../../../rendering/worker.zig").Worker;
const Node = @import("../../bvh/node.zig").Node;
const NodeStack = @import("../../bvh/node_stack.zig").NodeStack;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const int = @import("../../shape/intersection.zig");
const Fragment = int.Fragment;
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

    pub fn intersect(self: Tree, ray: Ray, trafo: Trafo, isec: *Intersection) bool {
        var tray = ray;

        var stack = NodeStack{};
        var n: u32 = 0;

        var hpoint: IndexedData.Fragment = undefined;
        var primitive = Intersection.Null;

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
                        hpoint = hit;
                        primitive = i;
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

        if (Intersection.Null == primitive) {
            return false;
        }

        isec.t = hpoint.t;
        isec.u = hpoint.u;
        isec.v = hpoint.v;
        isec.primitive = primitive;
        isec.prototype = Intersection.Null;
        isec.trafo = trafo;

        return true;
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

    pub fn visibility(self: Tree, ray: Ray, entity: u32, sampler: *Sampler, worker: *const Worker, tr: *Vec4f) bool {
        var stack = NodeStack{};
        var n: u32 = 0;

        const ray_dir = ray.direction;

        const nodes = self.nodes;

        var rs: Renderstate = undefined;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                var i = node.indicesStart();
                const e = i + num;
                while (i < e) : (i += 1) {
                    if (self.data.intersect(ray, i)) |hit| {
                        const itri = self.data.indexTriangle(i);
                        const material = worker.scene.propMaterial(entity, itri.part);

                        if (material.evaluateVisibility()) {
                            rs.geo_n = self.data.normal(itri);
                            const uv = self.data.interpolateUv(itri, hit.u, hit.v);
                            rs.uvw = .{ uv[0], uv[1], 0.0, 0.0 };

                            if (!material.visibility(ray_dir, rs, sampler, worker, tr)) {
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
        trafo: Trafo,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *const Worker,
        tr: *Vec4f,
    ) bool {
        const material = worker.scene.propMaterial(entity, 0);
        const data = self.data;
        const RayMaxT = ray.max_t;

        var tray = ray;
        tray.max_t = ro.RayMaxT;

        var isec: Intersection = undefined;

        while (true) {
            if (!self.intersect(tray, trafo, &isec)) {
                break;
            }

            const n = data.normal(data.indexTriangle(isec.primitive));

            if (math.dot3(n, ray.direction) > 0.0) {
                tray.max_t = math.min(isec.t, RayMaxT);

                if (!worker.propTransmittance(tray, material, entity, depth, sampler, tr)) {
                    return false;
                }
            }

            const ray_min_t = ro.offsetF(isec.t);
            if (ray_min_t > RayMaxT) {
                break;
            }

            tray.setMinMaxT(ray_min_t, ro.RayMaxT);
        }

        return true;
    }

    pub fn emission(
        self: Tree,
        ray: Ray,
        vertex: *const Vertex,
        frag: *Fragment,
        split_threshold: f32,
        sampler: *Sampler,
        worker: *const Worker,
    ) Vec4f {
        var stack = NodeStack{};
        var n: u32 = 0;

        var energy: Vec4f = @splat(0.0);

        const shading_p = vertex.origin;
        const wo = -vertex.probe.ray.direction;

        const nodes = self.nodes;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                var i = node.indicesStart();
                const e = i + num;
                while (i < e) : (i += 1) {
                    if (self.data.intersect(ray, i)) |hit| {
                        frag.isec.t = hit.t;
                        frag.isec.u = hit.u;
                        frag.isec.v = hit.v;
                        frag.isec.primitive = i;

                        const itri = self.data.indexTriangle(i);

                        frag.part = itri.part;

                        const p = self.data.interpolateP(itri, hit.u, hit.v);
                        frag.p = frag.isec.trafo.objectToWorldPoint(p);

                        const geo_n = self.data.normal(itri);
                        frag.geo_n = frag.isec.trafo.objectToWorldNormal(geo_n);

                        const uv = self.data.interpolateUv(itri, hit.u, hit.v);

                        frag.uvw = .{ uv[0], uv[1], 0.0, 0.0 };

                        if (frag.evaluateRadiance(shading_p, wo, sampler, worker)) |local_energy| {
                            const weight: Vec4f = @splat(worker.scene.lightPdf(vertex, frag, split_threshold));
                            energy += weight * local_energy;
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

        return energy;
    }

    pub fn scatter(
        self: Tree,
        ray: Ray,
        trafo: Trafo,
        throughput: Vec4f,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *const Worker,
    ) Volume {
        const material = worker.scene.propMaterial(entity, 0);
        const data = self.data;
        const RayMaxT = ray.max_t;

        var tray = ray;
        tray.max_t = ro.RayMaxT;

        var tr: Vec4f = @splat(1.0);

        var isec: Intersection = undefined;

        while (true) {
            if (!self.intersect(tray, trafo, &isec)) {
                break;
            }

            const n = data.normal(data.indexTriangle(isec.primitive));

            if (math.dot3(n, ray.direction) > 0.0) {
                tray.max_t = math.min(isec.t, RayMaxT);

                var result = worker.propScatter(tray, throughput, material, entity, depth, sampler);

                tr *= result.tr;

                if (.Pass != result.event) {
                    result.tr = tr;
                    return result;
                }
            }

            const ray_min_t = ro.offsetF(isec.t);
            if (ray_min_t > RayMaxT) {
                break;
            }

            tray.setMinMaxT(ray_min_t, ro.RayMaxT);
        }

        return Volume.initPass(tr);
    }
};
