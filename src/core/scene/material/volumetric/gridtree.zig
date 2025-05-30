const CM = @import("../collision_coefficients.zig").CM;

const tracking = @import("../../../rendering/integrator/volume/tracking.zig");
const Context = @import("../../../scene/context.zig").Context;
const Material = @import("../../../scene/material/material.zig").Material;
const Volume = @import("../../../scene/shape/intersection.zig").Volume;
const ro = @import("../../../scene/ray_offset.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Ray = math.Ray;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4u = math.Vec4u;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Box = struct {
    bounds: [2]Vec4i,
};

pub const Node = packed struct {
    has_children: u1,
    children_or_data: u31,

    pub fn isParent(self: Node) bool {
        return 0 != self.has_children;
    }

    pub fn index(self: Node) u32 {
        return @as(u32, self.children_or_data);
    }

    pub fn isEmpty(self: Node) bool {
        return 0x7FFFFFFF == self.children_or_data;
    }

    pub fn setChildren(self: *Node, id: u32) void {
        self.has_children = 1;
        self.children_or_data = @intCast(id);
    }

    pub fn setData(self: *Node, id: u32) void {
        self.has_children = 0;
        self.children_or_data = @intCast(id);
    }

    pub fn setEmpty(self: *Node) void {
        self.has_children = 0;
        self.children_or_data = 0x7FFFFFFF;
    }
};

pub const Gridtree = struct {
    dimensions: Vec4f = undefined,
    num_cells: Vec4u = undefined,

    nodes: [*]Node = undefined,
    data: [*]Vec2f = undefined,

    num_nodes: u32 = 0,
    num_data: u32 = 0,

    pub const Log2_cell_dim: u5 = 6;
    pub const Log2_cell_dim4 = @Vector(4, u5){ Log2_cell_dim, Log2_cell_dim, Log2_cell_dim, 0 };
    pub const Cell_dim: i32 = 1 << Log2_cell_dim;
    pub const Cell_dim4: Vec4i = @splat(Cell_dim);

    pub fn deinit(self: *Gridtree, alloc: Allocator) void {
        alloc.free(self.data[0..self.num_data]);
        alloc.free(self.nodes[0..self.num_nodes]);
    }

    pub fn setDimensions(self: *Gridtree, dimensions: Vec4i, num_cells: Vec4i) void {
        const df: Vec4f = @floatFromInt(dimensions);
        self.dimensions = df;

        const nc: Vec4u = @bitCast(num_cells);
        self.num_cells = .{ nc[0], nc[1], nc[2], std.math.maxInt(u32) };
    }

    pub fn allocateNodes(self: *Gridtree, alloc: Allocator, num_nodes: u32) ![*]Node {
        if (num_nodes != self.num_nodes) {
            alloc.free(self.nodes[0..self.num_nodes]);
        }

        self.num_nodes = num_nodes;
        self.nodes = (try alloc.alloc(Node, num_nodes)).ptr;
        return self.nodes;
    }

    pub fn allocateData(self: *Gridtree, alloc: Allocator, num_data: u32) ![*]Vec2f {
        if (num_data != self.num_data) {
            alloc.free(self.data[0..self.num_data]);
        }

        self.num_data = num_data;
        self.data = (try alloc.alloc(Vec2f, num_data)).ptr;

        return self.data;
    }

    pub fn transmittance(
        self: *const Gridtree,
        ray: Ray,
        material: *const Material,
        prop: u32,
        depth: u32,
        sampler: *Sampler,
        context: Context,
        tr: *Vec4f,
    ) bool {
        const d = ray.max_t;

        var local_ray = tracking.objectToTextureRay(ray, prop, context);

        const srs = material.similarityRelationScale(depth);

        var cc = material.collisionCoefficients();
        cc.s *= @splat(srs);

        const cm = cc.minorantMajorantT();

        while (local_ray.min_t < d) {
            const dr = self.intersect(&local_ray);
            if (!tracking.trackingTransmitted(tr, local_ray, cm * dr, cc, material, sampler, context)) {
                return false;
            }

            local_ray.setMinMaxT(ro.offsetF(local_ray.max_t), d);
        }

        return true;
    }

    pub fn scatter(
        self: *const Gridtree,
        ray: Ray,
        throughput: Vec4f,
        material: *const Material,
        prop: u32,
        depth: u32,
        sampler: *Sampler,
        context: Context,
    ) Volume {
        const d = ray.max_t;

        var local_ray = tracking.objectToTextureRay(ray, prop, context);

        const srs = material.similarityRelationScale(depth);

        var cc = material.collisionCoefficients();
        cc.s *= @splat(srs);

        const cm = cc.minorantMajorantT();

        var result = Volume.initPass(@splat(1.0));

        if (material.emissive()) {
            while (local_ray.min_t < d) {
                const dr = self.intersect(&local_ray);
                result = tracking.trackingHeteroEmission(
                    local_ray,
                    cm * dr,
                    cc,
                    material,
                    result.tr,
                    throughput,
                    sampler,
                    context,
                );

                if (.Scatter == result.event) {
                    break;
                }

                if (.Absorb == result.event) {
                    result.uvw = local_ray.point(result.t);
                    return result;
                }

                local_ray.setMinMaxT(ro.offsetF(local_ray.max_t), d);
            }
        } else {
            while (local_ray.min_t < d) {
                const dr = self.intersect(&local_ray);
                result = tracking.trackingHetero(
                    local_ray,
                    cm * dr,
                    cc,
                    material,
                    result.tr,
                    throughput,
                    sampler,
                    context,
                );

                if (.Scatter == result.event) {
                    break;
                }

                local_ray.setMinMaxT(ro.offsetF(local_ray.max_t), d);
            }
        }

        return result;
    }

    fn intersect(self: Gridtree, ray: *Ray) Vec2f {
        const dim = self.dimensions;
        const p = ray.point(ray.min_t);
        const c: Vec4i = @intFromFloat(dim * p);
        const v = c >> Log2_cell_dim4;
        const uv: Vec4u = @bitCast(v);

        if (math.anyGreaterEqual4u(uv, self.num_cells)) {
            return @splat(0.0);
        }

        const b0 = v << Log2_cell_dim4;
        var box = Box{ .bounds = .{ b0, b0 + Cell_dim4 } };

        const index = (uv[2] * self.num_cells[1] + uv[1]) * self.num_cells[0] + uv[0];
        var node = self.nodes[index];

        while (node.isParent()) {
            const half = (box.bounds[1] - box.bounds[0]) >> @as(@Vector(4, u5), @splat(1));
            const center = box.bounds[0] + half;

            const l = c < center;

            box.bounds[0] = @select(i32, l, box.bounds[0], center);
            box.bounds[1] = @select(i32, l, center, box.bounds[1]);

            const ii = @select(u32, l, @Vector(4, u32){ 0, 0, 0, 0 }, @Vector(4, u32){ 1, 2, 4, 0 });
            const o = @reduce(.Add, ii);
            node = self.nodes[node.index() + o];
        }

        const idim = @as(Vec4f, @splat(1.0)) / dim;

        const boxf = AABB.init(
            @as(Vec4f, @floatFromInt(box.bounds[0])) * idim,
            @as(Vec4f, @floatFromInt(box.bounds[1])) * idim,
        );

        const hit_t = boxf.intersectInterval(ray.*);
        if (std.math.floatMax(f32) != hit_t[0]) {
            ray.setMinMaxT(hit_t[0], hit_t[1]);
        } else {
            ray.max_t = ray.min_t;
            return @splat(0.0);
        }

        if (node.isEmpty()) {
            return @splat(0.0);
        }

        return self.data[node.index()];
    }
};
