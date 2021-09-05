const Transformation = @import("../../composed_transformation.zig").Composed_transformation;
const NodeStack = @import("../node_stack.zig").NodeStack;
const Intersection = @import("../intersection.zig").Intersection;
pub const bvh = @import("bvh/tree.zig");
const base = @import("base");
usingnamespace base;

const Vec4f = base.math.Vec4f;
const Ray = base.math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Part = struct {
    material: u32,
    area: f32,
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
        return self.parts[part].area * (scale.v[0] * scale.v[1]);
    }

    pub fn intersect(self: Mesh, ray: *Ray, trafo: Transformation, nodes: *NodeStack, isec: *Intersection) bool {
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

            var t: Vec4f = undefined;
            var n: Vec4f = undefined;
            self.tree.data.interpolateData(hit.u, hit.v, hit.index, &t, &n);

            const t_w = trafo.rotation.transformVector(t);
            const n_w = trafo.rotation.transformVector(n);
            const b_w = n_w.cross3(t_w).mulScalar3(self.tree.data.bitangentSign(hit.index));

            isec.t = t_w;
            isec.b = b_w;
            isec.n = n_w;

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
};
