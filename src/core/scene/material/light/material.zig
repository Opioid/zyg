const Base = @import("../material_base.zig").Base;
const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Emittance = @import("../../light/emittance.zig").Emittance;
const Worker = @import("../../worker.zig").Worker;
const Scene = @import("../../scene.zig").Scene;
const Shape = @import("../../shape/shape.zig").Shape;
const Transformation = @import("../../composed_transformation.zig").ComposedTransformation;
const ts = @import("../../../image/texture/sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Distribution1D = math.Distribution1D;
const Distribution2D = math.Distribution2D;
const Threads = base.thread.Pool;
const spectrum = base.spectrum;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Material = struct {
    super: Base,

    emission_map: Texture = .{},
    distribution: Distribution2D = .{},
    emittance: Emittance = undefined,
    average_emission: Vec4f = @splat(4, @as(f32, -1.0)),
    emission_factor: f32 = 1.0,
    total_weight: f32 = 0.0,

    pub fn init(sampler_key: ts.Key, two_sided: bool) Material {
        return .{ .super = Base.init(sampler_key, two_sided) };
    }

    pub fn deinit(self: *Material, alloc: Allocator) void {
        self.distribution.deinit(alloc);
    }

    pub fn commit(self: *Material) void {
        self.super.properties.set(.EmissionMap, self.emission_map.valid());
    }

    pub fn prepareSampling(
        self: *Material,
        alloc: Allocator,
        shape: Shape,
        area: f32,
        scene: Scene,
        threads: *Threads,
    ) Vec4f {
        if (self.average_emission[0] >= 0.0) {
            // Hacky way to check whether prepare_sampling has been called before
            // average_emission_ is initialized with negative values...
            return self.average_emission;
        }

        if (!self.emission_map.valid()) {
            self.average_emission = self.emittance.radiance(area);
            return self.average_emission;
        }

        const d = self.emission_map.description(scene).dimensions;

        var luminance = alloc.alloc(f32, @intCast(usize, d.v[0] * d.v[1])) catch return @splat(4, @as(f32, 0.0));
        defer alloc.free(luminance);

        var avg = @splat(4, @as(f32, 0.0));

        {
            var context = LuminanceContext{
                .scene = &scene,
                .shape = &shape,
                .texture = &self.emission_map,
                .luminance = luminance.ptr,
                .averages = alloc.alloc(Vec4f, threads.numThreads()) catch
                    return @splat(4, @as(f32, 0.0)),
            };
            defer alloc.free(context.averages);

            _ = threads.runRange(&context, LuminanceContext.calculate, 0, @intCast(u32, d.v[1]), 0);

            for (context.averages) |a| {
                avg += a;
            }
        }

        const average_emission = avg / @splat(4, avg[3]);

        self.average_emission = @splat(4, self.emission_factor) * average_emission;

        self.total_weight = avg[3];

        {
            var context = DistributionContext{
                .al = 0.6 * spectrum.luminance(average_emission),
                .width = @intCast(u32, d.v[0]),
                .conditional = self.distribution.allocate(alloc, @intCast(u32, d.v[1])) catch
                    return @splat(4, @as(f32, 0.0)),
                .luminance = luminance.ptr,
                .alloc = alloc,
            };

            _ = threads.runRange(&context, DistributionContext.calculate, 0, @intCast(u32, d.v[1]), 0);
        }

        self.distribution.configure(alloc) catch
            return @splat(4, @as(f32, 0.0));

        return self.average_emission;
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        var radiance: Vec4f = undefined;

        if (self.emission_map.valid()) {
            const key = ts.resolveKey(self.super.sampler_key, rs.filter);

            const ef = @splat(4, self.emission_factor);
            radiance = ef * ts.sample2D_3(key, self.emission_map, rs.uv, worker.scene.*);
        } else {
            radiance = self.emittance.radiance(worker.scene.lightArea(rs.prop, rs.part));
        }

        var result = Sample.init(rs, wo, radiance);
        result.super.layer.setTangentFrame(rs.t, rs.b, rs.n);
        return result;
    }

    pub fn evaluateRadiance(self: Material, uvw: Vec4f, extent: f32, filter: ?ts.Filter, worker: Worker) Vec4f {
        if (self.emission_map.valid()) {
            const ef = @splat(4, self.emission_factor);
            const key = ts.resolveKey(self.super.sampler_key, filter);
            return ef * ts.sample2D_3(key, self.emission_map, .{ uvw[0], uvw[1] }, worker.scene.*);
        }

        return self.emittance.radiance(extent);
    }

    pub fn radianceSample(self: Material, r3: Vec4f) Base.RadianceSample {
        const result = self.distribution.sampleContinous(.{ r3[0], r3[1] });

        return Base.RadianceSample.init2(result.uv, result.pdf * self.total_weight);
    }

    pub fn emissionPdf(self: Material, uv: Vec2f) f32 {
        if (self.emission_map.valid()) {
            return self.distribution.pdf(self.super.sampler_key.address.address2(uv)) * self.total_weight;
        }

        return 1.0;
    }
};

const LuminanceContext = struct {
    scene: *const Scene,
    shape: *const Shape,
    texture: *const Texture,
    luminance: [*]f32,
    averages: []Vec4f,

    pub fn calculate(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        const self = @intToPtr(*LuminanceContext, context);

        const d = self.texture.description(self.scene.*).dimensions;
        const width = @intCast(u32, d.v[0]);

        const idf = @splat(2, @as(f32, 1.0)) / Vec2f{
            @intToFloat(f32, d.v[0]),
            @intToFloat(f32, d.v[1]),
        };

        var avg = @splat(4, @as(f32, 0.0));

        var y = begin;
        while (y < end) : (y += 1) {
            const v = idf[1] * (@intToFloat(f32, y) + 0.5);

            const row = y * width;
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const u = idf[0] * (@intToFloat(f32, x) + 0.5);

                const uv_weight = self.shape.uvWeight(.{ u, v });

                const radiance = self.texture.get2D_3(@intCast(i32, x), @intCast(i32, y), self.scene.*);
                const wr = @splat(4, uv_weight) * radiance;

                avg += Vec4f{ wr[0], wr[1], wr[2], uv_weight };

                self.luminance[row + x] = spectrum.luminance(wr);
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
        const self = @intToPtr(*DistributionContext, context);

        var y = begin;
        while (y < end) : (y += 1) {
            const rb = y * self.width;
            const re = rb + self.width;
            const luminance_row = self.luminance[rb..re];

            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                const l = luminance_row[x];
                const p = std.math.max(l - self.al, 0.0);
                luminance_row[x] = p;
            }

            self.conditional[y].configure(self.alloc, luminance_row, 0) catch {};
        }
    }
};
