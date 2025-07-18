const Base = @import("../material_base.zig").Base;
const Sample = @import("volumetric_sample.zig").Sample;
const Gridtree = @import("gridtree.zig").Gridtree;
const Builder = @import("gridtree_builder.zig").Builder;
const ccoef = @import("../collision_coefficients.zig");
const CC = ccoef.CC;
const CCE = ccoef.CCE;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Emittance = @import("../../light/emittance.zig").Emittance;
const Context = @import("../../context.zig").Context;
const Scene = @import("../../scene.zig").Scene;
const ts = @import("../../../texture/texture_sampler.zig");
const Texture = @import("../../../texture/texture.zig").Texture;
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

    emittance: Emittance = .{},

    density_map: Texture = Texture.initUniform1(0.0),

    blackbody: math.ifunc.InterpolatedFunction1D(Vec4f) = .{},

    distribution: Distribution3D = .{},

    tree: Gridtree = .{},

    average_emission: Vec4f = @splat(-1.0),
    a_norm: Vec4f = undefined,

    cc: CC = undefined,
    attenuation_distance: f32 = 0.0,

    pdf_factor: f32 = undefined,

    sr_low: u32 = 16,
    sr_high: u32 = 48,
    sr_inv_range: f32 = undefined,

    pub fn init() Material {
        return .{ .super = .{} };
    }

    pub fn deinit(self: *Material, alloc: Allocator) void {
        self.blackbody.deinit(alloc);
        self.distribution.deinit(alloc);
        self.tree.deinit(alloc);
    }

    pub fn commit(self: *Material, alloc: Allocator, scene: *const Scene, threads: *Threads) !void {
        self.average_emission = @splat(-1.0);

        self.super.properties.scattering_volume = math.anyGreaterZero3(self.cc.s) or
            math.anyGreaterZero3(self.emittance.value);
        self.super.properties.emissive = math.anyGreaterZero3(self.emittance.value);
        self.super.properties.emission_image_map = self.density_map.isImage();
        self.super.properties.evaluate_visibility = true;

        self.sr_inv_range = 1.0 / @as(f32, @floatFromInt(self.sr_high - self.sr_low));

        if (!self.density_map.isUniform()) {
            try Builder.build(
                alloc,
                &self.tree,
                self.density_map,
                self.cc,
                scene,
                threads,
            );
        }

        if (!self.emittance.emission_map.isUniform() and 0 == self.blackbody.samples.len) {
            const Num_samples = 16;

            const Start = 2000.0;
            const End = 5000.0;

            self.blackbody = try math.ifunc.InterpolatedFunction1D(Vec4f).init(alloc, 0.0, 1.2, Num_samples);

            for (0..Num_samples) |i| {
                const t = Start + @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(Num_samples - 1)) * (End - Start);

                const c = spectrum.mapping.blackbody(t);

                self.blackbody.samples[i] = self.emittance.value * c;
            }
        }
    }

    pub fn setVolumetric(
        self: *Material,
        attenuation_color: Vec4f,
        subsurface_color: Vec4f,
        distance: f32,
        anisotropy: f32,
    ) void {
        const aniso = math.clamp(anisotropy, -0.999, 0.999);
        const cc = ccoef.attenuation(attenuation_color, subsurface_color, distance, aniso);

        self.cc = cc;
        self.attenuation_distance = distance;
        self.super.properties.scattering_volume = math.anyGreaterZero3(cc.s);
    }

    pub fn setSimilarityRelationRange(self: *Material, low: u32, high: u32) void {
        self.sr_low = low;
        self.sr_high = high;
    }

    pub fn prepareSampling(self: *Material, alloc: Allocator, scene: *const Scene, threads: *Threads) Vec4f {
        if (self.average_emission[0] >= 0.0) {
            // Hacky way to check whether prepare_sampling has been called before
            // average_emission_ is initialized with negative values...
            return self.average_emission;
        }

        if (self.density_map.isUniform()) {
            self.average_emission = self.cc.a * self.emittance.value;
            return self.average_emission;
        }

        const d = self.density_map.dimensions(scene);

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

        const cca = self.cc.a;
        const majorant_a = math.hmax3(cca);
        self.a_norm = @as(Vec4f, @splat(majorant_a)) / cca;
        self.pdf_factor = num_pixels / majorant_a;

        return average_emission;
    }

    pub fn sample(self: *const Material, wo: Vec4f, rs: Renderstate) Sample {
        const gs = self.vanDeHulstAnisotropy(rs.volume_depth);
        return Sample.init(wo, rs, gs);
    }

    pub fn similarityRelationScale(self: *const Material, depth: u32) f32 {
        const gs = self.vanDeHulstAnisotropy(depth);
        return vanDeHulst(self.cc.anisotropy(), gs);
    }

    fn vanDeHulstAnisotropy(self: *const Material, depth: u32) f32 {
        const aniso = self.cc.anisotropy();

        const low = self.sr_low;

        if (depth < low) {
            return aniso;
        }

        if (depth < self.sr_high) {
            const towards_zero = self.sr_inv_range * @as(f32, @floatFromInt(depth - low));
            return math.lerp(aniso, 0.0, towards_zero);
        }

        return 0.0;
    }

    fn vanDeHulst(g: f32, gs: f32) f32 {
        return (1.0 - g) / (1.0 - gs);
    }

    pub fn evaluateRadiance(self: *const Material, rs: Renderstate, context: Context) Vec4f {
        if (self.density_map.isUniform()) {
            return self.average_emission;
        }

        const uvw = rs.uvw;

        const emission = if (!self.emittance.emission_map.isUniform())
            self.blackbody.eval(ts.sample3D_1(self.emittance.emission_map, uvw, rs.stochastic_r, context))
        else
            self.emittance.value;

        const norm_emission = self.a_norm * emission;

        if (2 == self.density_map.numChannels()) {
            const d = ts.sample3D_2(self.density_map, uvw, rs.stochastic_r, context);
            return @as(Vec4f, @splat(d[0] * d[1])) * norm_emission;
        } else {
            const d = ts.sample3D_1(self.density_map, uvw, rs.stochastic_r, context);
            return @as(Vec4f, @splat(d)) * norm_emission;
        }
    }

    pub fn radianceSample(self: *const Material, r3: Vec4f) Base.RadianceSample {
        if (!self.density_map.isUniform()) {
            const result = self.distribution.sampleContinuous(r3);
            return Base.RadianceSample.init3(result, result[3] * self.pdf_factor);
        }

        return Base.RadianceSample.init3(r3, 1.0);
    }

    pub fn emissionPdf(self: *const Material, uvw: Vec4f) f32 {
        if (!self.density_map.isUniform()) {
            return self.distribution.pdf(self.density_map.mode.address3(uvw)) * self.pdf_factor;
        }

        return 1.0;
    }

    pub fn density(self: *const Material, uvw: Vec4f, r: f32, context: Context) f32 {
        if (!self.density_map.isUniform()) {
            return ts.sample3D_1(self.density_map, uvw, r, context);
        }

        return 1.0;
    }

    pub fn collisionCoefficientsEmission(self: *const Material, uvw: Vec4f, cc: CC, sampler: *Sampler, context: Context) CCE {
        const r = sampler.sample1D();
        if (!self.density_map.isUniform() and !self.emittance.emission_map.isUniform()) {
            const t = ts.sample3D_1(self.emittance.emission_map, uvw, r, context);
            const e = self.blackbody.eval(t);

            if (2 == self.density_map.numChannels()) {
                const d = ts.sample3D_2(self.density_map, uvw, r, context);
                return .{
                    .cc = cc.scaled(@splat(d[0])),
                    .e = @as(Vec4f, @splat(d[1])) * e,
                };
            } else {
                const d: Vec4f = @splat(ts.sample3D_1(self.density_map, uvw, r, context));
                return .{
                    .cc = cc.scaled(d),
                    .e = d * e,
                };
            }
        }

        const d = self.density(uvw, r, context);
        return .{
            .cc = cc.scaled(@splat(d)),
            .e = self.emittance.value,
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

        const d = self.material.density_map.dimensions(self.scene);
        const width: u32 = @intCast(d[0]);
        const height: u32 = @intCast(d[1]);

        var avg: Vec4f = @splat(0.0);

        if (2 == mat.density_map.numChannels()) {
            if (!mat.emittance.emission_map.isUniform()) {
                var z = begin;
                while (z < end) : (z += 1) {
                    const slice = z * (width * height);
                    var y: u32 = 0;
                    while (y < height) : (y += 1) {
                        const row = y * width;
                        var x: u32 = 0;
                        while (x < width) : (x += 1) {
                            const density = mat.density_map.image3D_2(@intCast(x), @intCast(y), @intCast(z), self.scene);
                            const t = mat.emittance.emission_map.image3D_1(@intCast(x), @intCast(y), @intCast(z), self.scene);
                            const c = mat.blackbody.eval(t);
                            const radiance = @as(Vec4f, @splat(density[0] * density[1])) * c;

                            self.luminance[slice + row + x] = math.hmax3(radiance);

                            avg += radiance;
                        }
                    }
                }
            } else {
                var z = begin;
                while (z < end) : (z += 1) {
                    const slice = z * (width * height);
                    var y: u32 = 0;
                    while (y < height) : (y += 1) {
                        const row = y * width;
                        var x: u32 = 0;
                        while (x < width) : (x += 1) {
                            const density = mat.density_map.image3D_2(@intCast(x), @intCast(y), @intCast(z), self.scene);
                            const radiance: Vec4f = @splat(density[0] * density[1]);

                            self.luminance[slice + row + x] = math.hmax3(radiance);

                            avg += radiance;
                        }
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
