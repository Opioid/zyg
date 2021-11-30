const Base = @import("../scene/material/material_base.zig").Base;
const Sample = @import("../scene/material/light/sample.zig").Sample;
const Renderstate = @import("../scene/renderstate.zig").Renderstate;
const Emittance = @import("../scene/light/emittance.zig").Emittance;
const Worker = @import("../scene/worker.zig").Worker;
const Scene = @import("../scene/scene.zig").Scene;
const Resources = @import("../resource/manager.zig").Manager;
const Shape = @import("../scene/shape/shape.zig").Shape;
const Transformation = @import("../scene/composed_transformation.zig").ComposedTransformation;
const ts = @import("../image/texture/sampler.zig");
const Texture = @import("../image/texture/texture.zig").Texture;
const img = @import("../image/image.zig");
const Image = img.Image;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Distribution1D = math.Distribution1D;
const Distribution2D = math.Distribution2D;
const Threads = base.thread.Pool;
const spectrum = base.spectrum;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Bake_dimensions = Vec2i{ 256, 256 };

pub const Material = struct {
    pub const Mode = enum { Sky, Sun };

    super: Base,

    emission_map: Texture = undefined,
    distribution: Distribution2D = .{},
    emittance: Emittance = undefined,
    average_emission: Vec4f = @splat(4, @as(f32, -1.0)),
    total_weight: f32 = undefined,

    mode: Mode = undefined,

    pub fn init(alloc: *Allocator, sampler_key: ts.Key, mode: Mode, resources: *Resources) !Material {
        if (.Sky == mode) {
            const image = try img.Float3.init(alloc, img.Description.init2D(Bake_dimensions));
            const image_id = resources.images.store(alloc, .{ .Float3 = image });

            const emission_map = Texture{ .type = .Float3, .image = image_id, .scale = .{ 1.0, 1.0 } };

            return Material{
                .super = Base.init(sampler_key, false),
                .emission_map = emission_map,
                .mode = mode,
            };
        }

        var emittance: Emittance = undefined;
        emittance.setRadiance(@splat(4, @as(f32, 40000.0)));

        return Material{
            .super = Base.init(sampler_key, false),
            .emission_map = .{},
            .emittance = emittance,
            .mode = mode,
        };
    }

    pub fn deinit(self: *Material, alloc: *Allocator) void {
        self.distribution.deinit(alloc);
    }

    pub fn commit(self: *Material) void {
        self.super.properties.set(.EmissionMap, self.emission_map.isValid());
    }

    pub fn prepareSampling(
        self: *Material,
        alloc: *Allocator,
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

        if (!self.emission_map.isValid()) {
            self.average_emission = self.emittance.radiance(area);
            return self.average_emission;
        }

        var avg = @splat(4, @as(f32, 0.0));

        {
            var context = Context{
                .shape = &shape,
                .image = scene.imageRef(self.emission_map.image),
                .conditional = self.distribution.allocate(alloc, @intCast(u32, Bake_dimensions[1])) catch
                    return @splat(4, @as(f32, 0.0)),
                .averages = alloc.alloc(Vec4f, threads.numThreads()) catch
                    return @splat(4, @as(f32, 0.0)),
                .alloc = alloc,
            };

            defer alloc.free(context.averages);

            _ = threads.runRange(&context, Context.calculate, 0, @intCast(u32, Bake_dimensions[1]));

            for (context.averages) |a| {
                avg += a;
            }
        }

        const average_emission = avg / @splat(4, avg[3]);

        self.average_emission = average_emission;

        self.total_weight = avg[3];

        self.distribution.configure(alloc) catch
            return @splat(4, @as(f32, 0.0));

        return self.average_emission;
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        var radiance: Vec4f = undefined;

        if (self.emission_map.isValid()) {
            const key = ts.resolveKey(self.super.sampler_key, rs.filter);

            radiance = ts.sample2D_3(key, self.emission_map, rs.uv, worker.scene.*);
        } else {
            radiance = self.emittance.radiance(worker.scene.lightArea(rs.prop, rs.part));
        }

        var result = Sample.init(rs, wo, radiance);
        result.super.layer.setTangentFrame(rs.t, rs.b, rs.n);
        return result;
    }

    pub fn evaluateRadiance(self: Material, uvw: Vec4f, extent: f32, filter: ?ts.Filter, worker: Worker) Vec4f {
        if (self.emission_map.isValid()) {
            const key = ts.resolveKey(self.super.sampler_key, filter);
            return ts.sample2D_3(key, self.emission_map, .{ uvw[0], uvw[1] }, worker.scene.*);
        }

        return self.emittance.radiance(extent);
    }

    pub fn radianceSample(self: Material, r3: Vec4f) Base.RadianceSample {
        const result = self.distribution.sampleContinous(.{ r3[0], r3[1] });

        return Base.RadianceSample.init2(result.uv, result.pdf * self.total_weight);
    }

    pub fn emissionPdf(self: Material, uv: Vec2f) f32 {
        if (self.emission_map.isValid()) {
            return self.distribution.pdf(self.super.sampler_key.address.address(uv)) * self.total_weight;
        }

        return 1.0;
    }
};

const Context = struct {
    shape: *const Shape,
    image: *Image,
    conditional: []Distribution1D,
    averages: []Vec4f,
    alloc: *Allocator,

    pub fn calculate(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        const self = @intToPtr(*Context, context);

        var luminance = self.alloc.alloc(f32, @intCast(usize, Bake_dimensions[0])) catch return;
        defer self.alloc.free(luminance);

        const idf = @splat(2, @as(f32, 1.0)) / math.vec2iTo2f(Bake_dimensions);

        var avg = @splat(4, @as(f32, 0.0));

        var y = begin;
        while (y < end) : (y += 1) {
            const v = idf[1] * (@intToFloat(f32, y) + 0.5);

            var x: u32 = 0;
            while (x < Bake_dimensions[0]) : (x += 1) {
                const u = idf[0] * (@intToFloat(f32, x) + 0.5);

                const uv_weight = self.shape.uvWeight(.{ u, v });

                const li = Vec4f{ 0.0, 0.0, 2.0, 0.0 }; //self.texture.get2D_3(@intCast(i32, x), @intCast(i32, y), self.scene.*);

                self.image.Float3.set2D(@intCast(i32, x), @intCast(i32, y), math.vec4fTo3f(li));

                const wli = @splat(4, uv_weight) * li;

                avg += Vec4f{ wli[0], wli[1], wli[2], uv_weight };

                luminance[x] = spectrum.luminance(wli);
            }

            self.conditional[y].configure(self.alloc, luminance, 0) catch {};
        }

        self.averages[id] = avg;
    }
};
