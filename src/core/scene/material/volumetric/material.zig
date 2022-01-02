const Base = @import("../material_base.zig").Base;
const Sample = @import("../sample.zig").Sample;
const Volumetric = @import("sample.zig").Sample;
const Gridtree = @import("gridtree.zig").Gridtree;
const Builder = @import("gridtree_builder.zig").Builder;
const Null = @import("../null/sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Scene = @import("../../scene.zig").Scene;
const Worker = @import("../../worker.zig").Worker;
const ts = @import("../../../image/texture/sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const fresnel = @import("../fresnel.zig");
const hlp = @import("../material_helper.zig");
const inthlp = @import("../../../rendering/integrator/helper.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Material = struct {
    super: Base,

    density_map: Texture = .{},

    tree: Gridtree = .{},

    pub fn init(sampler_key: ts.Key) Material {
        var super = Base.init(sampler_key, false);
        super.ior = 1.0;

        return .{ .super = super };
    }

    pub fn deinit(self: *Material, alloc: Allocator) void {
        self.tree.deinit(alloc);
    }

    pub fn commit(self: *Material, alloc: Allocator, scene: Scene, threads: *Threads) void {
        self.super.properties.set(.ScatteringVolume, math.anyGreaterZero3(self.super.cc.s) or
            math.anyGreaterZero3(self.super.emission));

        if (self.density_map.valid()) {
            Builder.build(
                alloc,
                &self.tree,
                self.density_map,
                self.super.cc,
                scene,
                threads,
            ) catch {};
        }
    }

    pub fn prepareSampling(
        self: *Material,
        alloc: Allocator,
        scene: Scene,
        threads: *Threads,
    ) Vec4f {
        _ = alloc;
        _ = scene;
        _ = threads;

        return self.super.cc.a * self.super.emission;
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate) Sample {
        if (rs.subsurface) {
            const gs = self.super.vanDeHulstAnisotropy(rs.depth);
            return .{ .Volumetric = Volumetric.init(wo, rs, gs) };
        }

        return .{ .Null = Null.init(wo, rs) };
    }

    pub fn evaluateRadiance(self: Material, uvw: Vec4f, filter: ?ts.Filter, worker: Worker) Vec4f {
        _ = uvw;
        _ = filter;
        _ = worker;

        return self.super.cc.a * self.super.emission;
    }

    pub fn density(self: Material, uvw: Vec4f, filter: ?ts.Filter, worker: Worker) f32 {
        if (self.density_map.valid()) {
            const key = ts.resolveKey(self.super.sampler_key, filter);
            return ts.sample3D_1(key, self.density_map, uvw, worker.scene.*);
        }

        return 1.0;
    }
};
