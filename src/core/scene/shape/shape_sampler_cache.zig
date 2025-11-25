const Sampler = @import("shape_sampler.zig").Sampler;
const Shape = @import("shape.zig").Shape;
const Scene = @import("../scene.zig").Scene;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Material = @import("../material/material.zig").Material;

const base = @import("base");
const math = base.math;
const Mat3x3 = math.Mat3x3;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

const List = std.ArrayList;

const Key = struct {
    material: u32,
    shape: u32,
    part: u32,
    light_link: u32,
    rotation: Mat3x3,
    shape_sampler: bool,
    emission_map: bool,
    two_sided: bool,
};

const KeyContext = struct {
    const Self = @This();

    pub fn hash(self: Self, k: Key) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);

        if (k.shape_sampler) {
            hasher.update(std.mem.asBytes(&k.shape));
            hasher.update(std.mem.asBytes(&k.part));
            hasher.update(std.mem.asBytes(&k.two_sided));

            if (k.emission_map) {
                hasher.update(std.mem.asBytes(&k.material));
            }
        } else {
            hasher.update(std.mem.asBytes(&k.material));

            if (k.emission_map) {
                hasher.update(std.mem.asBytes(&k.shape));
                hasher.update(std.mem.asBytes(&k.light_link));

                if (Scene.Null != k.light_link) {
                    hasher.update(std.mem.asBytes(&k.rotation));
                }
            }
        }

        return hasher.final();
    }

    pub fn eql(self: Self, a: Key, b: Key) bool {
        _ = self;

        if (a.shape_sampler and b.shape_sampler) {
            if (a.shape != b.shape) {
                return false;
            }

            if (a.part != b.part) {
                return false;
            }

            if (a.two_sided != b.two_sided) {
                return false;
            }

            if (a.emission_map != b.emission_map) {
                return false;
            } else if (a.emission_map) {
                if (a.material != b.material) {
                    return false;
                }
            }

            return true;
        }

        if (a.material != b.material) {
            return false;
        }

        if (a.emission_map) {
            if (a.shape != b.shape) {
                return false;
            }

            if (a.light_link != b.light_link) {
                return false;
            }

            if (Scene.Null != a.light_link) {
                if (!math.equal(a.rotation.r[0], b.rotation.r[0]) or
                    !math.equal(a.rotation.r[1], b.rotation.r[1]) or
                    !math.equal(a.rotation.r[2], b.rotation.r[2]))
                {
                    return false;
                }
            }
        }

        return true;
    }
};

pub const Cache = struct {
    const EntryHashMap = std.HashMapUnmanaged(Key, u32, KeyContext, 80);

    resources: List(Sampler) = .empty,
    entries: EntryHashMap = .empty,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.entries.deinit(alloc);

        for (self.resources.items) |*r| {
            r.impl.deinit(alloc);
        }

        self.resources.deinit(alloc);
    }

    pub fn prepareSampling(
        self: *Self,
        alloc: Allocator,
        trafo: Trafo,
        time: u64,
        shape: *Shape,
        shape_id: u32,
        part: u32,
        material_id: u32,
        light_id: u32,
        scene: *Scene,
        threads: *Threads,
    ) !u32 {
        const material = scene.resources.material(material_id);

        const light_link = scene.light_links.items[light_id];

        const key = Key{
            .material = material_id,
            .shape = shape_id,
            .part = part,
            .light_link = light_link,
            .rotation = trafo.rotation,
            .shape_sampler = shape.hasShapeSampler(),
            .emission_map = material.emissionImageMapped(),
            .two_sided = material.twoSided(),
        };

        if (self.entries.get(key)) |entry| {
            // std.debug.print("We reuse the shape sampler\n", .{});
            return entry;
        }

        const shape_sampler = try shape.prepareSampling(alloc, part, material_id, &scene.light_tree_builder, scene.resources, threads) orelse
            try material.prepareSampling(alloc, trafo, time, shape, light_link, scene, threads);

        try self.resources.append(alloc, shape_sampler);

        const id: u32 = @intCast(self.resources.items.len - 1);
        try self.entries.put(alloc, key, id);

        return id;
    }

    pub fn sampler(self: *const Self, id: u32) *const Sampler {
        return &self.resources.items[id];
    }
};
