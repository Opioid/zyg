pub const Data = @import("point_motion_data.zig").MotionData;
const Node = @import("../../bvh/node.zig").Node;
const NodeStack = @import("../../bvh/node_stack.zig").NodeStack;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("../intersection.zig").Intersection;
const Probe = @import("../probe.zig").Probe;
const Scene = @import("../../scene.zig").Scene;

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
        return self.nodes[0].aabb();
    }

    pub fn intersect(self: Self, probe: Probe, trafo: Trafo, current_time_start: u64, isec: *Intersection) bool {
        const seconds: Vec4f = @splat(Scene.secondsSince(probe.time, current_time_start));

        const indices = self.indices;
        const positions = self.data.positions;
        const velocities = self.data.velocities;
        const radius = self.data.radius;

        var local_ray = trafo.worldToObjectRay(probe.ray);

        var stack = NodeStack{};
        var n: u32 = 0;

        var hit_t: f32 = undefined;
        var primitive = Intersection.Null;

        const nodes = self.nodes;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                const start = node.indicesStart();
                const end = start + num;
                for (indices[start..end]) |p| {
                    const pos: Vec4f = positions[p * 3 ..][0..4].*;
                    const vel: Vec4f = velocities[p * 3 ..][0..4].*;

                    const ipos = pos + math.lerp(@as(Vec4f, @splat(0.0)), vel, seconds);

                    if (intersectSphere(local_ray, ipos, radius)) |t| {
                        local_ray.max_t = t;
                        hit_t = t;
                        primitive = p;
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

    pub fn intersectP(self: *const Self, probe: Probe, trafo: Trafo, current_time_start: u64) bool {
        const seconds: Vec4f = @splat(Scene.secondsSince(probe.time, current_time_start));

        const indices = self.indices;
        const positions = self.data.positions;
        const velocities = self.data.velocities;
        const radius = self.data.radius;

        const local_ray = trafo.worldToObjectRay(probe.ray);

        var stack = NodeStack{};
        var n: u32 = 0;

        const nodes = self.nodes;

        while (NodeStack.End != n) {
            const node = nodes[n];

            const num = node.numIndices();
            if (0 != num) {
                const start = node.indicesStart();
                const end = start + num;
                for (indices[start..end]) |p| {
                    const pos: Vec4f = positions[p * 3 ..][0..4].*;
                    const vel: Vec4f = velocities[p * 3 ..][0..4].*;

                    const ipos = pos + math.lerp(@as(Vec4f, @splat(0.0)), vel, seconds);

                    if (intersectSphereP(local_ray, ipos, radius)) {
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

    fn intersectSphere(ray: Ray, position: Vec4f, radius: f32) ?f32 {
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

    fn intersectSphereP(ray: Ray, position: Vec4f, radius: f32) bool {
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
