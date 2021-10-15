const Transformation = @import("../../composed_transformation.zig").ComposedTransformation;
const Worker = @import("../../worker.zig").Worker;
const Filter = @import("../../../image/texture/sampler.zig").Filter;
const NodeStack = @import("../node_stack.zig").NodeStack;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;
const Interpolation = int.Interpolation;
pub const bvh = @import("bvh/tree.zig");
const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Part = struct {
    material: u32,
    area: f32,

    pub fn init(self: *Part, part: u32, tree: bvh.Tree) void {
        var total_area: f32 = 0.0;

        var t: u32 = 0;
        //    var mt: u32 = 0;
        const len = tree.numTriangles();
        while (t < len) : (t += 1) {
            if (tree.data.part(t) == part) {
                const area = tree.data.area(t);

                total_area += area;
            }
        }

        self.area = total_area;
    }
};

pub const Mesh = struct {
    tree: bvh.Tree = .{},

    parts: []Part,

    pub fn init(alloc: *Allocator, num_parts: u32) !Mesh {
        return Mesh{ .parts = try alloc.alloc(Part, num_parts) };
    }

    pub fn deinit(self: *Mesh, alloc: *Allocator) void {
        alloc.free(self.parts);
        self.tree.deinit(alloc);
    }

    pub fn numParts(self: Mesh) u32 {
        return @intCast(u32, self.parts.len);
    }

    pub fn numMaterials(self: Mesh) u32 {
        var id: u32 = 0;

        for (self.parts) |p| {
            id = std.math.max(id, p.material);
        }

        return id + 1;
    }

    pub fn partIdToMaterialId(self: Mesh, part: u32) u32 {
        return self.parts[part].material;
    }

    pub fn setMaterialForPart(self: *Mesh, part: usize, material: u32) void {
        self.parts[part].material = material;
    }

    pub fn area(self: Mesh, part: u32, scale: Vec4f) f32 {
        // HACK: This only really works for uniform scales!
        return self.parts[part].area * (scale[0] * scale[1]);
    }

    pub fn intersect(
        self: Mesh,
        ray: *Ray,
        trafo: Transformation,
        nodes: *NodeStack,
        ipo: Interpolation,
        isec: *Intersection,
    ) bool {
        var tray = Ray.init(
            trafo.world_to_object.transformPoint(ray.origin),
            trafo.world_to_object.transformVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );

        if (self.tree.intersect(&tray, nodes)) |hit| {
            ray.setMaxT(tray.maxT());

            const p = self.tree.data.interpolateP(hit.u, hit.v, hit.index);
            isec.p = trafo.objectToWorldPoint(p);

            const geo_n = self.tree.data.normal(hit.index);
            isec.geo_n = trafo.rotation.transformVector(geo_n);

            isec.part = self.tree.data.part(hit.index);
            isec.primitive = hit.index;

            if (.All == ipo) {
                var t: Vec4f = undefined;
                var n: Vec4f = undefined;
                var uv: Vec2f = undefined;
                self.tree.data.interpolateData(hit.u, hit.v, hit.index, &t, &n, &uv);

                const t_w = trafo.rotation.transformVector(t);
                const n_w = trafo.rotation.transformVector(n);
                const b_w = @splat(4, self.tree.data.bitangentSign(hit.index)) * math.cross3(n_w, t_w);

                isec.t = t_w;
                isec.b = b_w;
                isec.n = n_w;
                isec.uv = uv;
            } else if (.NoTangentSpace == ipo) {
                const uv = self.tree.data.interpolateUv(hit.u, hit.v, hit.index);
                isec.uv = uv;
            } else {
                const n = self.tree.data.interpolateShadingNormal(hit.u, hit.v, hit.index);
                const n_w = trafo.rotation.transformVector(n);
                isec.n = n_w;
            }

            return true;
        }

        return false;
    }

    pub fn intersectP(self: Mesh, ray: Ray, trafo: Transformation, nodes: *NodeStack) bool {
        var tray = Ray.init(
            trafo.world_to_object.transformPoint(ray.origin),
            trafo.world_to_object.transformVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );

        return self.tree.intersectP(tray, nodes);
    }

    pub fn visibility(
        self: Mesh,
        ray: Ray,
        trafo: Transformation,
        entity: usize,
        filter: ?Filter,
        worker: *Worker,
    ) ?Vec4f {
        var tray = Ray.init(
            trafo.world_to_object.transformPoint(ray.origin),
            trafo.world_to_object.transformVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );

        return self.tree.visibility(&tray, entity, filter, worker);
    }

    pub fn prepareSampling(self: *Mesh, part: u32) void {
        self.parts[part].init(part, self.tree);
    }
};
