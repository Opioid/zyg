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
const ts = @import("../../../image/texture/sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const fresnel = @import("../fresnel.zig");
const hlp = @import("../material_helper.zig");
const inthlp = @import("../../../rendering/integrator/helper.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec3i = math.Vec3i;
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

    average_emission: Vec4f = @splat(4, @as(f32, -1.0)),
    a_norm: Vec4f = undefined,
    pdf_factor: f32 = undefined,

    pub fn init() Material {
        return .{ .super = .{
            .sampler_key = .{ .filter = .Linear, .address = .{ .u = .Clamp, .v = .Clamp } },
            .ior = 1.0,
        } };
    }

    pub fn deinit(self: *Material, alloc: Allocator) void {
        self.blackbody.deinit(alloc);
        self.distribution.deinit(alloc);
        self.tree.deinit(alloc);
    }

    pub fn commit(self: *Material, alloc: Allocator, scene: Scene, threads: *Threads) !void {
        self.average_emission = @splat(4, @as(f32, -1.0));

        self.super.properties.set(.ScatteringVolume, math.anyGreaterZero3(self.super.cc.s) or
            math.anyGreaterZero3(self.super.emittance.value));
        self.super.properties.set(.EmissionMap, self.density_map.valid());

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

            var i: u32 = 0;
            while (i < Num_samples) : (i += 1) {
                const t = Start + @intToFloat(f32, i) / @intToFloat(f32, Num_samples - 1) * (End - Start);

                const c = spectrum.blackbody(t);

                self.blackbody.samples[i] = self.super.emittance.value * c;
            }
        }
    }

    pub fn prepareSampling(
        self: *Material,
        alloc: Allocator,
        scene: Scene,
        threads: *Threads,
    ) Vec4f {
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

        var luminance = alloc.alloc(f32, @intCast(usize, d.v[0] * d.v[1] * d.v[2])) catch return @splat(4, @as(f32, 0.0));
        defer alloc.free(luminance);

        var avg = @splat(4, @as(f32, 0.0));

        {
            var context = LuminanceContext{
                .material = self,
                .scene = &scene,
                .luminance = luminance.ptr,
                .averages = alloc.alloc(Vec4f, threads.numThreads()) catch
                    return @splat(4, @as(f32, 0.0)),
            };
            defer alloc.free(context.averages);

            const num = threads.runRange(&context, LuminanceContext.calculate, 0, @intCast(u32, d.v[2]), 0);
            for (context.averages[0..num]) |a| {
                avg += a;
            }
        }

        const num_pixels = @intToFloat(f32, d.v[0] * d.v[1] * d.v[2]);

        const average_emission = avg / @splat(4, num_pixels);

        {
            var context = DistributionContext{
                .al = 0.6 * spectrum.luminance(average_emission),
                .d = d,
                .conditional = self.distribution.allocate(alloc, @intCast(u32, d.v[2])) catch
                    return @splat(4, @as(f32, 0.0)),
                .luminance = luminance.ptr,
                .alloc = alloc,
            };

            _ = threads.runRange(&context, DistributionContext.calculate, 0, @intCast(u32, d.v[2]), 0);
        }

        self.distribution.configure(alloc) catch
            return @splat(4, @as(f32, 0.0));

        self.average_emission = average_emission;

        const cca = self.super.cc.a;
        const majorant_a = math.maxComponent3(cca);
        self.a_norm = @splat(4, majorant_a) / cca;
        self.pdf_factor = num_pixels / majorant_a;

        return average_emission;
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate) Sample {
        if (rs.subsurface) {
            const gs = self.super.vanDeHulstAnisotropy(rs.depth);
            return .{ .Volumetric = Volumetric.init(wo, rs, gs) };
        }

        return .{ .Null = Null.init(wo, rs) };
    }

    pub fn evaluateRadiance(self: Material, uvw: Vec4f, filter: ?ts.Filter, scene: Scene) Vec4f {
        if (!self.density_map.valid()) {
            return self.average_emission;
        }

        const key = ts.resolveKey(self.super.sampler_key, filter);

        const emission = if (self.temperature_map.valid())
            self.blackbody.eval(ts.sample3D_1(key, self.temperature_map, uvw, scene))
        else
            self.super.emittance.value;

        if (2 == self.density_map.numChannels()) {
            const d = ts.sample3D_2(key, self.density_map, uvw, scene);
            return @splat(4, d[0] * d[1]) * self.a_norm * emission;
        } else {
            const d = ts.sample3D_1(key, self.density_map, uvw, scene);
            return @splat(4, d) * self.a_norm * emission;
        }
    }

    pub fn radianceSample(self: Material, r3: Vec4f) Base.RadianceSample {
        if (self.density_map.valid()) {
            const result = self.distribution.sampleContinuous(r3);
            return Base.RadianceSample.init3(result, result[3] * self.pdf_factor);
        }

        return Base.RadianceSample.init3(r3, 1.0);
    }

    pub fn emissionPdf(self: Material, uvw: Vec4f) f32 {
        if (self.density_map.valid()) {
            return self.distribution.pdf(self.super.sampler_key.address.address3(uvw)) * self.pdf_factor;
        }

        return 1.0;
    }

    pub fn density(self: Material, uvw: Vec4f, filter: ?ts.Filter, scene: Scene) f32 {
        if (self.density_map.valid()) {
            const key = ts.resolveKey(self.super.sampler_key, filter);
            return ts.sample3D_1(key, self.density_map, uvw, scene);
        }

        return 1.0;
    }

    pub fn collisionCoefficientsEmission(self: Material, uvw: Vec4f, filter: ?ts.Filter, scene: Scene) CCE {
        const cc = self.super.cc;

        if (self.density_map.valid() and self.temperature_map.valid()) {
            const key = ts.resolveKey(self.super.sampler_key, filter);

            const t = ts.sample3D_1(key, self.temperature_map, uvw, scene);
            const e = self.blackbody.eval(t);

            if (2 == self.density_map.numChannels()) {
                const d = ts.sample3D_2(key, self.density_map, uvw, scene);
                const d0 = @splat(4, d[0]);
                return .{
                    .cc = .{ .a = d0 * cc.a, .s = d0 * cc.s },
                    .e = @splat(4, d[1]) * e,
                };
            } else {
                const d = @splat(4, ts.sample3D_1(key, self.density_map, uvw, scene));
                return .{
                    .cc = .{ .a = d * cc.a, .s = d * cc.s },
                    .e = d * e,
                };
            }
        }

        const d = @splat(4, self.density(uvw, filter, scene));
        return .{
            .cc = .{ .a = d * cc.a, .s = d * cc.s },
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
        const self = @intToPtr(*LuminanceContext, context);
        const mat = self.material;

        const d = self.material.density_map.description(self.scene.*).dimensions;
        const width = @intCast(u32, d.v[0]);
        const height = @intCast(u32, d.v[1]);

        var avg = @splat(4, @as(f32, 0.0));

        if (2 == mat.density_map.numChannels()) {
            var z = begin;
            while (z < end) : (z += 1) {
                const slice = z * (width * height);
                var y: u32 = 0;
                while (y < height) : (y += 1) {
                    const row = y * width;
                    var x: u32 = 0;
                    while (x < width) : (x += 1) {
                        const density = mat.density_map.get3D_2(
                            @intCast(i32, x),
                            @intCast(i32, y),
                            @intCast(i32, z),
                            self.scene.*,
                        );
                        const t = mat.temperature_map.get3D_1(
                            @intCast(i32, x),
                            @intCast(i32, y),
                            @intCast(i32, z),
                            self.scene.*,
                        );
                        const c = mat.blackbody.eval(t);
                        const radiance = @splat(4, density[0] * density[1]) * c;

                        self.luminance[slice + row + x] = spectrum.luminance(radiance);

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
    d: Vec3i,
    conditional: []Distribution2D,
    luminance: [*]f32,
    alloc: Allocator,

    pub fn calculate(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;
        const self = @intToPtr(*DistributionContext, context);
        const d = self.d;
        const width = @intCast(u32, d.v[0]);
        const height = @intCast(u32, d.v[1]);

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
                    const p = std.math.max(l - self.al, 0.0);
                    luminance_row[x] = p;
                }

                conditional[y].configure(self.alloc, luminance_row, 0) catch {};
            }

            self.conditional[z].configure(self.alloc) catch {};
        }
    }
};
