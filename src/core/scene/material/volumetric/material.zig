const Base = @import("../material_base.zig").Base;
const Sample = @import("../sample.zig").Sample;
const Volumetric = @import("sample.zig").Sample;
const Gridtree = @import("gridtree.zig").Gridtree;
const Builder = @import("gridtree_builder.zig").Builder;
const ccoef = @import("../collision_coefficients.zig");
const CC = ccoef.CC;
const CCE = ccoef.CCE;
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
const spectrum = base.spectrum;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Material = struct {
    super: Base,

    density_map: Texture = .{},
    temperature_map: Texture = .{},

    blackbody: math.InterpolatedFunction1D(Vec4f) = .{},

    tree: Gridtree = .{},

    pub fn init(sampler_key: ts.Key) Material {
        var super = Base.init(sampler_key, false);
        super.ior = 1.0;

        return .{ .super = super };
    }

    pub fn deinit(self: *Material, alloc: Allocator) void {
        self.tree.deinit(alloc);
    }

    pub fn commit(self: *Material, alloc: Allocator, scene: Scene, threads: *Threads) !void {
        self.super.properties.set(.ScatteringVolume, math.anyGreaterZero3(self.super.cc.s) or
            math.anyGreaterZero3(self.super.emission));

        if (self.density_map.valid()) {
            try Builder.build(
                alloc,
                &self.tree,
                self.density_map,
                self.super.cc,
                scene,
                threads,
            );
        }

        if (self.temperature_map.valid()) {
            std.debug.print("Have our selves a blackbody\n", .{});

            const Num_samples = 16;

            const Start = 2000.0;
            const End = 5000.0;

            self.blackbody = try math.InterpolatedFunction1D(Vec4f).init(alloc, 0.0, 1.2, Num_samples);

            var i: u32 = 0;
            while (i < Num_samples) : (i += 1) {
                const t = Start + @intToFloat(f32, i) / @intToFloat(f32, Num_samples - 1) * (End - Start);

                const c = spectrum.blackbody(t);

                self.blackbody.samples[i] = self.super.emission * c;
            }
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

    pub fn collisionCoefficientsEmission(self: Material, uvw: Vec4f, filter: ?ts.Filter, worker: Worker) CCE {
        const cc = self.super.cc;

        if (self.density_map.valid() and self.temperature_map.valid()) {
            const key = ts.resolveKey(self.super.sampler_key, filter);

            const t = ts.sample3D_1(key, self.temperature_map, uvw, worker.scene.*);
            const e = self.blackbody.eval(t);

            if (2 == self.density_map.numChannels()) {
                const d = ts.sample3D_2(key, self.density_map, uvw, worker.scene.*);
                const d0 = @splat(4, d[0]);
                return .{
                    .cc = .{ .a = d0 * cc.a, .s = d0 * cc.s },
                    .e = @splat(4, d[1]) * e,
                };
            } else {
                const d = @splat(4, ts.sample3D_1(key, self.density_map, uvw, worker.scene.*));
                return .{
                    .cc = .{ .a = d * cc.a, .s = d * cc.s },
                    .e = d * e,
                };
            }
        }

        const d = @splat(4, self.density(uvw, filter, worker));
        return .{
            .cc = .{ .a = d * cc.a, .s = d * cc.s },
            .e = self.super.emission,
        };
    }
};
