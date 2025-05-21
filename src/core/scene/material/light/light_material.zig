const Base = @import("../material_base.zig").Base;
const Sample = @import("light_sample.zig").Sample;
const Emittance = @import("../../light/emittance.zig").Emittance;
const Context = @import("../../context.zig").Context;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Scene = @import("../../scene.zig").Scene;
const Shape = @import("../../shape/shape.zig").Shape;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const ts = @import("../../../image/texture/texture_sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Distribution1D = math.Distribution1D;
const Distribution2D = math.Distribution2D;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

// Uses "MIS Compensation: Optimizing Sampling Techniques in Multiple Importance Sampling"
// https://twitter.com/VrKomarov/status/1297454856177954816

pub const Material = struct {
    super: Base = .{},

    emittance: Emittance = .{ .value = @splat(1.0) },

    distribution: Distribution2D = .{},
    average_emission: Vec4f = @splat(-1.0),
    total_weight: f32 = 0.0,

    pub fn deinit(self: *Material, alloc: Allocator) void {
        self.distribution.deinit(alloc);
    }

    pub fn commit(self: *Material) void {
        self.super.properties.emissive = math.anyGreaterZero3(self.emittance.value);
        self.super.properties.emission_image_map = self.emittance.emission_map.isImage();
    }

    pub fn prepareSampling(
        self: *Material,
        alloc: Allocator,
        shape: *const Shape,
        area: f32,
        scene: *const Scene,
        threads: *Threads,
    ) Vec4f {
        if (self.average_emission[0] >= 0.0) {
            // Hacky way to check whether prepare_sampling has been called before
            // average_emission_ is initialized with negative values...
            return self.average_emission;
        }

        const rad = self.emittance.averageRadiance(area);
        if (!self.emittance.emission_map.isImage()) {
            self.average_emission = rad;
            return self.average_emission;
        }

        const d = self.emittance.emission_map.description(scene).dimensions;

        const luminance = alloc.alloc(f32, @intCast(d[0] * d[1])) catch return @splat(0.0);
        defer alloc.free(luminance);

        var avg: Vec4f = @splat(0.0);

        {
            var context = LuminanceContext{
                .scene = scene,
                .shape = shape,
                .texture = self.emittance.emission_map,
                .luminance = luminance.ptr,
                .averages = alloc.alloc(Vec4f, threads.numThreads()) catch
                    return @splat(0.0),
            };
            defer alloc.free(context.averages);

            const num = threads.runRange(&context, LuminanceContext.calculate, 0, @intCast(d[1]), 0);
            for (context.averages[0..num]) |a| {
                avg += a;
            }
        }

        const average_emission = avg / @as(Vec4f, @splat(avg[3]));
        self.average_emission = rad * average_emission;

        self.total_weight = avg[3];

        {
            var context = DistributionContext{
                .al = 0.6 * math.hmax3(average_emission),
                .width = @intCast(d[0]),
                .conditional = self.distribution.allocate(alloc, @intCast(d[1])) catch
                    return @splat(0.0),
                .luminance = luminance.ptr,
                .alloc = alloc,
            };

            _ = threads.runRange(&context, DistributionContext.calculate, 0, @intCast(d[1]), 0);
        }

        self.distribution.configure(alloc) catch
            return @splat(0.0);

        return self.average_emission;
    }

    pub fn sample(wo: Vec4f, rs: Renderstate) Sample {
        return Sample.init(rs, wo);
    }

    pub fn evaluateRadiance(
        self: *const Material,
        wi: Vec4f,
        rs: Renderstate,
        sampler: *Sampler,
        context: Context,
    ) Vec4f {
        return self.emittance.radiance(wi, rs, sampler, context);
    }

    pub fn radianceSample(self: *const Material, r3: Vec4f) Base.RadianceSample {
        const result = self.distribution.sampleContinuous(.{ r3[0], r3[1] });

        return Base.RadianceSample.init2(result.uv, result.pdf * self.total_weight);
    }

    pub fn emissionPdf(self: *const Material, uv: Vec2f) f32 {
        if (!self.emittance.emission_map.isUniform()) {
            return self.distribution.pdf(self.emittance.emission_map.mode.address2(uv)) * self.total_weight;
        }

        return 1.0;
    }
};

const LuminanceContext = struct {
    scene: *const Scene,
    shape: *const Shape,
    texture: Texture,
    luminance: [*]f32,
    averages: []Vec4f,

    pub fn calculate(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        const self: *LuminanceContext = @ptrCast(context);

        const d = self.texture.description(self.scene).dimensions;
        const width: u32 = @intCast(d[0]);

        const idf = @as(Vec2f, @splat(1.0)) / Vec2f{
            @floatFromInt(d[0]),
            @floatFromInt(d[1]),
        };

        var avg: Vec4f = @splat(0.0);

        var y = begin;
        while (y < end) : (y += 1) {
            const v = idf[1] * (@as(f32, @floatFromInt(y)) + 0.5);

            const row = y * width;
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const u = idf[0] * (@as(f32, @floatFromInt(x)) + 0.5);

                const uv_weight = self.shape.uvWeight(.{ u, v });

                const radiance = self.texture.image2D_3(@intCast(x), @intCast(y), self.scene);
                const wr = @as(Vec4f, @splat(uv_weight)) * radiance;

                avg += Vec4f{ wr[0], wr[1], wr[2], uv_weight };

                //   self.luminance[row + x] = spectrum.luminance(wr);
                self.luminance[row + x] = math.hmax3(wr); // spectrum.luminance(wr);
            }
        }

        self.averages[id] = avg;
    }
};

const DistributionContext = struct {
    al: f32,
    width: u32,
    conditional: []Distribution1D,
    luminance: [*]f32,
    alloc: Allocator,

    pub fn calculate(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;
        const self: *DistributionContext = @ptrCast(context);

        var y = begin;
        while (y < end) : (y += 1) {
            const rb = y * self.width;
            const re = rb + self.width;
            const luminance_row = self.luminance[rb..re];

            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                const l = luminance_row[x];
                const p = math.max(l - self.al, math.min(l, 0.0025));
                luminance_row[x] = p;
            }

            self.conditional[y].configure(self.alloc, luminance_row, 0) catch {};
        }
    }
};
