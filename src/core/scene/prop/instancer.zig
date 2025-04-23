const Tree = @import("prop_tree.zig").Tree;
const int = @import("../shape/intersection.zig");
const Intersection = int.Intersection;
const Probe = @import("../shape/probe.zig").Probe;
const Scene = @import("../scene.zig").Scene;
const Space = @import("../space.zig").Space;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Worker = @import("../../rendering/worker.zig").Worker;

const math = @import("base").math;
const Ray = math.Ray;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub const Instancer = struct {
    prototypes: List(u32),

    space: Space,

    tree: Tree,

    const Self = @This();

    pub fn init(alloc: Allocator, num_reserve: u32) !Self {
        return .{
            .prototypes = try List(u32).initCapacity(alloc, num_reserve),
            .space = try Space.init(alloc, num_reserve),
            .tree = .{},
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
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

    pub fn intersect(self: *const Self, probe: Probe, trafo: Trafo, isec: *Intersection, scene: *const Scene) bool {
        var local_probe = trafo.worldToObjectProbe(probe);

        if (self.tree.intersectIndexed(&local_probe, isec, self.prototypes.items.ptr, scene, &self.space)) {
            isec.trafo = trafo.transform(isec.trafo);

            return true;
        }

        return false;
    }

    pub fn visibility(self: *const Self, probe: Probe, trafo: Trafo, sampler: *Sampler, worker: *Worker, tr: *Vec4f) bool {
        const local_probe = trafo.worldToObjectProbe(probe);

        return self.tree.visibilityIndexed(local_probe, self.prototypes.items.ptr, sampler, worker, &self.space, tr);
    }
};
