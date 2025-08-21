const Tree = @import("prop_tree.zig").Tree;
const int = @import("../shape/intersection.zig");
const Fragment = int.Fragment;
const Intersection = int.Intersection;
const Volume = int.Volume;
const Probe = @import("../shape/probe.zig").Probe;
const Context = @import("../context.zig").Context;
const Scene = @import("../scene.zig").Scene;
const Space = @import("../space.zig").Space;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;

const math = @import("base").math;
const AABB = math.AABB;
const Ray = math.Ray;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayList;

pub const Instancer = struct {
    prototypes: List(u32),

    space: Space,

    solid_bvh: Tree,
    volume_bvh: Tree,

    const Self = @This();

    pub fn init(alloc: Allocator, num_reserve: u32) !Self {
        return .{
            .prototypes = try List(u32).initCapacity(alloc, num_reserve),
            .space = try Space.init(alloc, num_reserve),
            .solid_bvh = .{},
            .volume_bvh = .{},
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.volume_bvh.deinit(alloc);
        self.solid_bvh.deinit(alloc);
        self.space.deinit(alloc);
        self.prototypes.deinit(alloc);
    }

    pub fn allocateInstance(self: *Self, alloc: Allocator, prototype: u32) !void {
        try self.prototypes.append(alloc, prototype);
        try self.space.allocateInstance(alloc);
    }

    pub fn calculateWorldBounds(self: *Self, scene: *const Scene) void {
        for (0..self.space.frames.items.len) |entity| {
            const prototype = self.prototypes.items[entity];

            const prop_aabb = scene.prop(prototype).localAabb(scene);

            self.space.calculateWorldBounds(@truncate(entity), prop_aabb, @splat(0.0), scene.num_interpolation_frames);
        }
    }

    pub fn aabb(self: Self) AABB {
        var total = self.solid_bvh.aabb();
        total.mergeAssign(self.volume_bvh.aabb());
        return total;
    }

    pub fn solid(self: Self) bool {
        return self.solid_bvh.num_nodes > 0;
    }

    pub fn volume(self: Self) bool {
        return self.volume_bvh.num_nodes > 0;
    }

    pub fn intersect(self: *const Self, probe: Probe, trafo: Trafo, sampler: *Sampler, scene: *const Scene, isec: *Intersection) bool {
        var local_probe = trafo.worldToObjectProbe(probe);

        if (self.solid_bvh.intersectIndexed(&local_probe, self.prototypes.items.ptr, sampler, scene, &self.space, isec)) {
            isec.trafo = trafo.transform(isec.trafo);

            return true;
        }

        return false;
    }

    pub fn visibility(
        self: *const Self,
        comptime Volumetric: bool,
        probe: Probe,
        trafo: Trafo,
        sampler: *Sampler,
        context: Context,
        tr: *Vec4f,
    ) bool {
        const local_probe = trafo.worldToObjectProbe(probe);

        if (Volumetric) {
            return self.volume_bvh.visibilityIndexed(Volumetric, local_probe, self.prototypes.items.ptr, sampler, context, &self.space, tr);
        } else {
            return self.solid_bvh.visibilityIndexed(Volumetric, local_probe, self.prototypes.items.ptr, sampler, context, &self.space, tr);
        }
    }

    pub fn scatter(
        self: *const Self,
        probe: Probe,
        trafo: Trafo,
        isec: *Intersection,
        throughput: Vec4f,
        sampler: *Sampler,
        context: Context,
    ) Volume {
        var local_probe = trafo.worldToObjectProbe(probe);

        const result = self.volume_bvh.scatterIndexed(&local_probe, self.prototypes.items.ptr, isec, throughput, sampler, context, &self.space);

        if (.Absorb == result.event) {
            isec.trafo = trafo.transform(isec.trafo);
        }

        return result;
    }
};
