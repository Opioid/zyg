const Tree = @import("instancer_tree.zig").Tree;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;
const Probe = @import("../probe.zig").Probe;
const Scene = @import("../../scene.zig").Scene;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const TrafoCollection = @import("../../transformation_collection.zig").TransformationCollection;

const math = @import("base").math;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub const Instancer = struct {
    prototypes: List(u32),

    trafos: TrafoCollection,

    tree: Tree,

    const Self = @This();

    pub fn init(alloc: Allocator, num_reserve: u32) !Self {
        return .{
            .prototypes = try List(u32).initCapacity(alloc, num_reserve),
            .trafos = try TrafoCollection.init(alloc, num_reserve),
            .tree = undefined,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.trafos.deinit(alloc);
    }

    pub fn allocateInstance(self: *Self, alloc: Allocator, prototype: u32) !void {
        try self.prototypes.append(alloc, prototype);
        try self.trafos.allocateInstance(alloc);
    }

    pub fn intersect(self: *const Self, probe: Probe, trafo: Trafo) Intersection {
        // const local_ray = trafo.worldToObjectRay(ray);
        // return self.tree.intersect(local_ray);

        _ = self;
        _ = probe;
        _ = trafo;

        //   const prototype = self.prototypes.items[0];

        //  scene.prop(prototype).intersect(prototype, probe: Probe, frag: *Fragment, scene);

        return .{};
    }
};
