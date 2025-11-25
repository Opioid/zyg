const Data = @import("triangle_data.zig").Data;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const Context = @import("../../context.zig").Context;
const Scene = @import("../../scene.zig").Scene;
const Vertex = @import("../../vertex.zig").Vertex;
const ro = @import("../../ray_offset.zig");
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
    data: Data = .{},

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
        const nodes = self.nodes;

        var local_ray = trafo.worldToObjectRay(ray);

        var stack = NodeStack{};
        var n: u32 = 0;

        var hpoint: Data.Hit = undefined;
        var primitive = Intersection.Null;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                var i = node.indicesStart();
                const e = i + num;
                while (i < e) : (i += 1) {
                    if (self.data.intersect(local_ray, i)) |hit| {
                        local_ray.max_t = hit.t;
                        hpoint = hit;
                        primitive = i;
                    }
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(local_ray);
            var distb = nodes[b].intersect(local_ray);

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

    pub fn intersectOpacity(
        self: Tree,
        ray: Ray,
        trafo: Trafo,
        entity: u32,
        sampler: *Sampler,
        scene: *const Scene,
        isec: *Intersection,
    ) bool {
        const nodes = self.nodes;

        var local_ray = trafo.worldToObjectRay(ray);

        var stack = NodeStack{};
        var n: u32 = 0;

        var hpoint: Data.Hit = undefined;
        var primitive = Intersection.Null;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                var i = node.indicesStart();
                const e = i + num;
                while (i < e) : (i += 1) {
                    if (self.data.intersect(local_ray, i)) |hit| {
                        const material = scene.propMaterial(entity, self.data.trianglePart(i));

                        if (material.evaluateVisibility()) {
                            const itri = self.data.indexTriangle(i);
                            const uv = self.data.interpolateUv(itri, hit.u, hit.v);

                            if (material.super().stochasticOpacity(uv, sampler, scene.resources)) {
                                local_ray.max_t = hit.t;
                                hpoint = hit;
                                primitive = i;
                            }
                        } else {
                            local_ray.max_t = hit.t;
                            hpoint = hit;
                            primitive = i;
                        }
                    }
                }

                n = stack.pop();
                continue;
            }

            var a = node.children();
            var b = a + 1;

            var dista = nodes[a].intersect(local_ray);
            var distb = nodes[b].intersect(local_ray);

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
        const nodes = self.nodes;

        var stack = NodeStack{};
        var n: u32 = 0;

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

    pub fn visibility(self: Tree, ray: Ray, entity: u32, sampler: *Sampler, context: Context, tr: *Vec4f) bool {
        const nodes = self.nodes;

        const ray_dir = ray.direction;

        var stack = NodeStack{};
        var n: u32 = 0;

        var rs: Renderstate = undefined;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                var i = node.indicesStart();
                const e = i + num;
                while (i < e) : (i += 1) {
                    if (self.data.intersect(ray, i)) |hit| {
                        const material = context.scene.propMaterial(entity, self.data.trianglePart(i));

                        if (material.evaluateVisibility()) {
                            const itri = self.data.indexTriangle(i);
                            rs.geo_n = self.data.normal(itri);
                            const uv = self.data.interpolateUv(itri, hit.u, hit.v);
                            rs.uvw = .{ uv[0], uv[1], 0.0, 0.0 };

                            if (!material.visibility(ray_dir, rs, sampler, context, tr)) {
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
        context: Context,
        tr: *Vec4f,
    ) bool {
        const material = context.scene.propMaterial(entity, 0);
        const data = self.data;
        const RayMaxT = ray.max_t;

        var local_ray = trafo.worldToObjectRay(ray);
        local_ray.max_t = ro.RayMaxT;

        var isec: Intersection = undefined;

        while (true) {
            if (!self.intersect(local_ray, trafo, &isec)) {
                break;
            }

            const n = data.normal(data.indexTriangle(isec.primitive));

            if (math.dot3(n, ray.direction) > 0.0) {
                local_ray.max_t = math.min(isec.t, RayMaxT);

                if (!context.propTransmittance(local_ray, material, entity, depth, sampler, tr)) {
                    return false;
                }
            }

            const ray_min_t = ro.offsetF(isec.t);
            if (ray_min_t > RayMaxT) {
                break;
            }

            local_ray.setMinMaxT(ray_min_t, ro.RayMaxT);
        }

        return true;
    }

    pub fn scatter(
        self: Tree,
        ray: Ray,
        trafo: Trafo,
        throughput: Vec4f,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        context: Context,
    ) Volume {
        const material = context.scene.propMaterial(entity, 0);
        const data = self.data;
        const RayMaxT = ray.max_t;

        var local_ray = trafo.worldToObjectRay(ray);
        local_ray.max_t = ro.RayMaxT;

        var tr: Vec4f = @splat(1.0);

        var isec: Intersection = undefined;

        while (true) {
            if (!self.intersect(local_ray, trafo, &isec)) {
                break;
            }

            const n = data.normal(data.indexTriangle(isec.primitive));

            if (math.dot3(n, ray.direction) > 0.0) {
                local_ray.max_t = math.min(isec.t, RayMaxT);

                var result = context.propScatter(local_ray, throughput, material, entity, depth, sampler);

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

            local_ray.setMinMaxT(ray_min_t, ro.RayMaxT);
        }

        return Volume.initPass(tr);
    }

    pub fn emission(
        self: Tree,
        ray: Ray,
        vertex: *const Vertex,
        frag: *Fragment,
        sampler: *Sampler,
        context: Context,
    ) Vec4f {
        const nodes = self.nodes;

        var stack = NodeStack{};
        var n: u32 = 0;

        var energy: Vec4f = @splat(0.0);

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

                        frag.part = self.data.trianglePart(i);

                        const itri = self.data.indexTriangle(i);

                        const p = self.data.interpolateP(itri, hit.u, hit.v);
                        frag.p = frag.isec.trafo.objectToWorldPoint(p);

                        const geo_n = self.data.normal(itri);
                        frag.geo_n = frag.isec.trafo.objectToWorldNormal(geo_n);

                        const uv = self.data.interpolateUv(itri, hit.u, hit.v);
                        frag.uvw = .{ uv[0], uv[1], 0.0, 0.0 };

                        energy += vertex.evaluateRadiance(frag, sampler, context);
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
};
