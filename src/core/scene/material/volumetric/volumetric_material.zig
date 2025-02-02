const Base = @import("../material_base.zig").Base;
const Sample = @import("volumetric_sample.zig").Sample;
const Gridtree = @import("gridtree.zig").Gridtree;
const Builder = @import("gridtree_builder.zig").Builder;
const ccoef = @import("../collision_coefficients.zig");
const CC = ccoef.CC;
const CCE = ccoef.CCE;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Scene = @import("../../scene.zig").Scene;
const ts = @import("../../../image/texture/texture_sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const fresnel = @import("../fresnel.zig");
const hlp = @import("../material_helper.zig");
const inthlp = @import("../../../rendering/integrator/helper.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Distribution2D = math.Distribution2D;
const Distribution3D = math.Distribution3D;
const spectrum = base.spectrum;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Material = struct {
    super: Base,

    density_map: Texture = .{},
    temperature_map: Texture = .{},

    blackbody: math.InterpolatedFunction1D(Vec4f) = .{},

    distribution: Distribution3D = .{},

    tree: Gridtree = .{},

    average_emission: Vec4f = @splat(-1.0),
    a_norm: Vec4f = undefined,
    pdf_factor: f32 = undefined,

    pub fn init() Material {
        return .{ .super = .{
            .sampler_key = .{ .filter = ts.DefaultFilter, .address = .{ .u = .Clamp, .v = .Clamp } },
            .ior = 0.0,
        } };
    }

    pub fn deinit(self: *Material, alloc: Allocator) void {
        self.blackbody.deinit(alloc);
        self.distribution.deinit(alloc);
        self.tree.deinit(alloc);
    }

    pub fn commit(self: *Material, alloc: Allocator, scene: *const Scene, threads: *Threads) !void {
        self.average_emission = @splat(-1.0);

        self.super.properties.scattering_volume = math.anyGreaterZero3(self.super.cc.s) or
            math.anyGreaterZero3(self.super.emittance.value);
        self.super.properties.emissive = math.anyGreaterZero3(self.super.emittance.value);
        self.super.properties.emission_map = self.density_map.valid();
        self.super.properties.evaluate_visibility = true;

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

        if (self.temperature_map.valid() and 0 == self.blackbody.samples.len) {
            const Num_samples = 16;

            const Start = 2000.0;
            const End = 5000.0;

            self.blackbody = try math.InterpolatedFunction1D(Vec4f).init(alloc, 0.0, 1.2, Num_samples);

            for (0..Num_samples) |i| {
                const t = Start + @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(Num_samples - 1)) * (End - Start);

                const c = spectrum.blackbody(t);

                self.blackbody.samples[i] = self.super.emittance.value * c;
            }
        }
    }

    pub fn prepareSampling(self: *Material, alloc: Allocator, scene: *const Scene, threads: *Threads) Vec4f {
        if (self.average_emission[0] >= 0.0) {
            // Hacky way to check whether prepare_sampling has been called before
            // average_emission_ is initialized with negative values...
            return self.average_emission;
        }

        if (!self.density_map.valid()) {
            self.average_emission = self.super.cc.a * self.super.emittance.value;
            return self.average_emission;
        }

        const d = self.density_map.description(scene).dimensions;

        const luminance = alloc.alloc(f32, @intCast(d[0] * d[1] * d[2])) catch return @splat(0.0);
        defer alloc.free(luminance);

        var avg: Vec4f = @splat(0.0);

        {
            var context = LuminanceContext{
                .material = self,
                .scene = scene,
                .luminance = luminance.ptr,
                .averages = alloc.alloc(Vec4f, threads.numThreads()) catch
                    return @splat(0.0),
            };
            defer alloc.free(context.averages);

            const num = threads.runRange(&context, LuminanceContext.calculate, 0, @intCast(d[2]), 0);
            for (context.averages[0..num]) |a| {
                avg += a;
            }
        }

        const num_pixels: f32 = @floatFromInt(d[0] * d[1] * d[2]);

        const average_emission = avg / @as(Vec4f, @splat(num_pixels));

        {
            var context = DistributionContext{
                .al = 0.6 * math.hmax3(average_emission),
                .d = d,
                .conditional = self.distribution.allocate(alloc, @intCast(d[2])) catch
                    return @splat(0.0),
                .luminance = luminance.ptr,
                .alloc = alloc,
            };

            _ = threads.runRange(&context, DistributionContext.calculate, 0, @intCast(d[2]), 0);
        }

        self.distribution.configure(alloc) catch
            return @splat(0.0);

        self.average_emission = average_emission;

        const cca = self.super.cc.a;
        const majorant_a = math.hmax3(cca);
        self.a_norm = @as(Vec4f, @splat(majorant_a)) / cca;
        self.pdf_factor = num_pixels / majorant_a;

        return average_emission;
    }

    pub fn sample(self: *const Material, wo: Vec4f, rs: Renderstate) Sample {
        const gs = self.super.vanDeHulstAnisotropy(rs.volume_depth);
        return Sample.init(wo, rs, gs);
    }

    pub fn evaluateRadiance(self: *const Material, uvw: Vec4f, sampler: *Sampler, scene: *const Scene) Vec4f {
        if (!self.density_map.valid()) {
            return self.average_emission;
        }

        const key = self.super.sampler_key;

        const emission = if (self.temperature_map.valid())
            self.blackbody.eval(ts.sample3D_1(key, self.temperature_map, uvw, sampler, scene))
        else
            self.super.emittance.value;

        const norm_emission = self.a_norm * emission;

        if (2 == self.density_map.numChannels()) {
            const d = ts.sample3D_2(key, self.density_map, uvw, sampler, scene);
            return @as(Vec4f, @splat(d[0] * d[1])) * norm_emission;
        } else {
            const d = ts.sample3D_1(key, self.density_map, uvw, sampler, scene);
            return @as(Vec4f, @splat(d)) * norm_emission;
        }
    }

    pub fn radianceSample(self: *const Material, r3: Vec4f) Base.RadianceSample {
        if (self.density_map.valid()) {
            const result = self.distribution.sampleContinuous(r3);
            return Base.RadianceSample.init3(result, result[3] * self.pdf_factor);
        }

        return Base.RadianceSample.init3(r3, 1.0);
    }

    pub fn emissionPdf(self: *const Material, uvw: Vec4f) f32 {
        if (self.density_map.valid()) {
            return self.distribution.pdf(self.super.sampler_key.address.address3(uvw)) * self.pdf_factor;
        }

        return 1.0;
    }

    pub fn density(self: *const Material, uvw: Vec4f, sampler: *Sampler, scene: *const Scene) f32 {
        if (self.density_map.valid()) {
            return ts.sample3D_1(self.super.sampler_key, self.density_map, uvw, sampler, scene);
        }

        return 1.0;
    }

    pub fn collisionCoefficientsEmission(self: *const Material, uvw: Vec4f, sampler: *Sampler, scene: *const Scene) CCE {
        const cc = self.super.cc;

        if (self.density_map.valid() and self.temperature_map.valid()) {
            const key = self.super.sampler_key;

            const t = ts.sample3D_1(key, self.temperature_map, uvw, sampler, scene);
            const e = self.blackbody.eval(t);

            if (2 == self.density_map.numChannels()) {
                const d = ts.sample3D_2(key, self.density_map, uvw, sampler, scene);
                const d0: Vec4f = @splat(d[0]);
                return .{
                    .cc = .{ .a = d0 * cc.a, .s = d0 * cc.s },
                    .e = @as(Vec4f, @splat(d[1])) * e,
                };
            } else {
                const d: Vec4f = @splat(ts.sample3D_1(key, self.density_map, uvw, sampler, scene));
                return .{
                    .cc = cc.scaled(d),
                    .e = d * e,
                };
            }
        }

        const d: Vec4f = @splat(self.density(uvw, sampler, scene));
        return .{
            .cc = cc.scaled(d),
            .e = self.super.emittance.value,
        };
    }
};

const LuminanceContext = struct {
    material: *const Material,
    scene: *const Scene,
    luminance: [*]f32,
    averages: []Vec4f,

    pub fn calculate(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        const self: *LuminanceContext = @ptrCast(context);
        const mat = self.material;

        const d = self.material.density_map.description(self.scene).dimensions;
        const width: u32 = @intCast(d[0]);
        const height: u32 = @intCast(d[1]);

        var avg: Vec4f = @splat(0.0);

        if (2 == mat.density_map.numChannels()) {
            var z = begin;
            while (z < end) : (z += 1) {
                const slice = z * (width * height);
                var y: u32 = 0;
                while (y < height) : (y += 1) {
                    const row = y * width;
                    var x: u32 = 0;
                    while (x < width) : (x += 1) {
                        const density = mat.density_map.get3D_2(@intCast(x), @intCast(y), @intCast(z), self.scene);
                        const t = mat.temperature_map.get3D_1(@intCast(x), @intCast(y), @intCast(z), self.scene);
                        const c = mat.blackbody.eval(t);
                        const radiance = @as(Vec4f, @splat(density[0] * density[1])) * c;

                        self.luminance[slice + row + x] = math.hmax3(radiance);

                        avg += radiance;
                    }
                }
            }
        }

        self.averages[id] = avg;
    }
};

const DistributionContext = struct {
    al: f32,
    d: Vec4i,
    conditional: []Distribution2D,
    luminance: [*]f32,
    alloc: Allocator,

    pub fn calculate(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;
        const self: *DistributionContext = @ptrCast(@alignCast(context));
        const d = self.d;
        const width: u32 = @intCast(d[0]);
        const height: u32 = @intCast(d[1]);

        var z = begin;
        while (z < end) : (z += 1) {
            var conditional = self.conditional[z].allocate(self.alloc, height) catch return;
            const slice = z * (width * height);
            var y: u32 = 0;
            while (y < height) : (y += 1) {
                const rb = slice + y * width;
                const re = rb + width;
                const luminance_row = self.luminance[rb..re];

                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    const l = luminance_row[x];
                    const p = math.max(l - self.al, 0.0);
                    luminance_row[x] = p;
                }

                conditional[y].configure(self.alloc, luminance_row, 0) catch {};
            }

            self.conditional[z].configure(self.alloc) catch {};
        }
    }
};
