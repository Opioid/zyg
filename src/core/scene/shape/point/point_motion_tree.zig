const Data = @import("point_motion_data.zig").MotionData;
const Probe = @import("../probe.zig").Probe;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const Context = @import("../../context.zig").Context;
const Scene = @import("../../scene.zig").Scene;
const Vertex = @import("../../vertex.zig").Vertex;
const Node = @import("../../bvh/node.zig").Node;
const NodeStack = @import("../../bvh/node_stack.zig").NodeStack;
const int = @import("../../shape/intersection.zig");
const Fragment = int.Fragment;
const Intersection = int.Intersection;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Tree = struct {
    num_nodes: u32 = 0,
    num_indices: u32 = 0,

    nodes: [*]Node = undefined,
    indices: [*]u32 = undefined,

    data: Data = .{},

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.data.deinit(alloc);

        alloc.free(self.indices[0..self.num_indices]);
        alloc.free(self.nodes[0..self.num_nodes]);
    }

    pub fn allocateNodes(self: *Self, alloc: Allocator, num_nodes: u32) !void {
        if (num_nodes != self.num_nodes) {
            self.nodes = (try alloc.realloc(self.nodes[0..self.num_nodes], num_nodes)).ptr;
            self.num_nodes = num_nodes;
        }
    }

    pub fn allocateIndices(self: *Self, alloc: Allocator, num_indices: u32) !void {
        if (num_indices != self.num_indices) {
            self.indices = (try alloc.realloc(self.indices[0..self.num_indices], num_indices)).ptr;
            self.num_indices = num_indices;
        }
    }

    pub fn aabb(self: Self) AABB {
        if (0 == self.num_nodes) {
            return .empty;
        }

        return self.nodes[0].aabb();
    }

    pub fn intersect(self: Self, probe: Probe, trafo: Trafo, isec: *Intersection) bool {
        const nodes = self.nodes;
        const indices = self.indices;
        const frame = self.data.frameAt(probe.time);

        var local_ray = trafo.worldToObjectRay(probe.ray);

        var stack = NodeStack{};
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        var hit_t: f32 = undefined;
        var primitive = Intersection.Null;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                const start = node.indicesStart();
                const end = start + num;
                for (indices[start..end]) |i| {
                    const ipos = self.data.positionAndRadiusAt(i, frame);

                    if (sphereIntersect(local_ray, ipos, ipos[3])) |t| {
                        local_ray.max_t = t;
                        hit_t = t;
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

        isec.t = hit_t;
        isec.primitive = primitive;
        isec.prototype = Intersection.Null;
        isec.trafo = trafo;

        return true;
    }

    pub fn intersectP(self: Self, probe: Probe, trafo: Trafo) bool {
        const nodes = self.nodes;
        const indices = self.indices;
        const frame = self.data.frameAt(probe.time);

        const local_ray = trafo.worldToObjectRay(probe.ray);

        var stack = NodeStack{};
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                const start = node.indicesStart();
                const end = start + num;
                for (indices[start..end]) |i| {
                    const ipos = self.data.positionAndRadiusAt(i, frame);

                    if (sphereIntersectP(local_ray, ipos, ipos[3])) {
                        return true;
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

        return false;
    }

    pub fn emission(
        self: Self,
        ray: Ray,
        vertex: *const Vertex,
        frag: *Fragment,
        split_threshold: f32,
        sampler: *Sampler,
        context: Context,
    ) Vec4f {
        const nodes = self.nodes;
        const indices = self.indices;
        const frame = self.data.frameAt(vertex.probe.time);

        var stack = NodeStack{};
        var n: u32 = if (0 == self.num_nodes) NodeStack.End else 0;

        var energy: Vec4f = @splat(0.0);

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                const start = node.indicesStart();
                const end = start + num;
                for (indices[start..end]) |i| {
                    const ipos = self.data.positionAndRadiusAt(i, frame);

                    if (sphereIntersectFront(ray, ipos, ipos[3])) |t| {
                        frag.isec.t = t;
                        frag.isec.u = 0.0;
                        frag.isec.v = 0.0;
                        frag.isec.primitive = i;

                        frag.part = 0;

                        const p = vertex.probe.ray.point(t);
                        frag.p = p;

                        const origin_w = frag.isec.trafo.objectToWorldPoint(ipos);

                        frag.geo_n = math.normalize3(p - origin_w);
                        frag.uvw = @splat(0.0);

                        if (vertex.evaluateRadiance(frag, sampler, context)) |local_energy| {
                            const weight: Vec4f = @splat(context.scene.lightPdf(vertex, frag, split_threshold));
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

    fn sphereIntersect(ray: Ray, position: Vec4f, radius: f32) ?f32 {
        const idl = 1.0 / math.length3(ray.direction);
        const nd = ray.direction * @as(Vec4f, @splat(idl));

        const v = position - ray.origin;
        const b = math.dot3(nd, v);

        const remedy_term = v - @as(Vec4f, @splat(b)) * nd;
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);

            const t0 = (b - dist) * idl;
            if (t0 >= ray.min_t and ray.max_t >= t0) {
                return t0;
            }

            const t1 = (b + dist) * idl;
            if (t1 >= ray.min_t and ray.max_t >= t1) {
                return t1;
            }
        }

        return null;
    }

    fn sphereIntersectFront(ray: Ray, position: Vec4f, radius: f32) ?f32 {
        const idl = 1.0 / math.length3(ray.direction);
        const nd = ray.direction * @as(Vec4f, @splat(idl));

        const v = position - ray.origin;
        const b = math.dot3(nd, v);

        const remedy_term = v - @as(Vec4f, @splat(b)) * nd;
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);

            const t0 = (b - dist) * idl;
            if (t0 >= ray.min_t and ray.max_t >= t0) {
                return t0;
            }
        }

        return null;
    }

    fn sphereIntersectP(ray: Ray, position: Vec4f, radius: f32) bool {
        const idl = 1.0 / math.length3(ray.direction);
        const nd = ray.direction * @as(Vec4f, @splat(idl));

        const v = position - ray.origin;
        const b = math.dot3(nd, v);

        const remedy_term = v - @as(Vec4f, @splat(b)) * nd;
        const discriminant = radius * radius - math.dot3(remedy_term, remedy_term);

        if (discriminant > 0.0) {
            const dist = @sqrt(discriminant);

            const t0 = (b - dist) * idl;
            if (t0 >= ray.min_t and ray.max_t >= t0) {
                return true;
            }

            const t1 = (b + dist) * idl;
            if (t1 >= ray.min_t and ray.max_t >= t1) {
                return true;
            }
        }

        return false;
    }
};
