const Base = @import("../material_base.zig").Base;
const Sample = @import("light_sample.zig").Sample;
const Emittance = @import("../../light/emittance.zig").Emittance;
const Context = @import("../../context.zig").Context;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Scene = @import("../../scene.zig").Scene;
const Shape = @import("../../shape/shape.zig").Shape;
const ShapeSampler = @import("../../shape/shape_sampler.zig").Sampler;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const ts = @import("../../../texture/texture_sampler.zig");
const Texture = @import("../../../texture/texture.zig").Texture;
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

    pub fn commit(self: *Material) void {
        var properties = &self.super.properties;

        properties.evaluate_visibility = self.super.mask.isImage();
        properties.emissive = math.anyGreaterZero3(self.emittance.value);
        properties.emission_image_map = self.emittance.emission_map.isImage();
    }

    pub fn prepareSampling(
        self: *const Material,
        alloc: Allocator,
        shape: *const Shape,
        scene: *const Scene,
        threads: *Threads,
    ) !ShapeSampler {
        const rad = self.emittance.value;
        if (!self.emittance.emission_map.isImage()) {
            return .{
                .impl = .Uniform,
                .average_emission = rad,
                .num_samples = self.emittance.num_samples,
            };
        }

        const d = self.emittance.emission_map.dimensions(scene);

        const luminance = try alloc.alloc(f32, @intCast(d[0] * d[1]));
        defer alloc.free(luminance);

        var avg: Vec4f = @splat(0.0);

        {
            var context = LuminanceContext{
                .scene = scene,
                .shape = shape,
                .texture = self.emittance.emission_map,
                .luminance = luminance.ptr,
                .averages = try alloc.alloc(Vec4f, threads.numThreads()),
            };
            defer alloc.free(context.averages);

            const num = threads.runRange(&context, LuminanceContext.calculate, 0, @intCast(d[1]), 0);
            for (context.averages[0..num]) |a| {
                avg += a;
            }
        }

        const average_emission = avg / @as(Vec4f, @splat(avg[3]));

        var image_sampler = ShapeSampler{
            .impl = .{ .Image = .{
                .total_weight = avg[3],
                .mode = self.emittance.emission_map.mode,
            } },
            .average_emission = rad * average_emission,
            .num_samples = self.emittance.num_samples,
        };

        {
            var context = DistributionContext{
                .al = 0.6 * math.hmax3(average_emission),
                .width = @intCast(d[0]),
                .conditional = try image_sampler.impl.Image.distribution.allocate(alloc, @intCast(d[1])),
                .luminance = luminance.ptr,
                .alloc = alloc,
            };

            _ = threads.runRange(&context, DistributionContext.calculate, 0, @intCast(d[1]), 0);
        }

        try image_sampler.impl.Image.distribution.configure(alloc);

        return image_sampler;
    }

    pub fn sample(wo: Vec4f, rs: Renderstate) Sample {
        return Sample.init(rs, wo);
    }

    pub fn evaluateRadiance(
        self: *const Material,
        wi: Vec4f,
        rs: Renderstate,
        in_camera: bool,
        sampler: *Sampler,
        context: Context,
    ) Vec4f {
        return self.emittance.radiance(wi, rs, in_camera, sampler, context);
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

        const d = self.texture.dimensions(self.scene);
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
