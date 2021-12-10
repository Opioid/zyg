const Model = @import("model.zig").Model;
const SkyThing = @import("sky.zig").Sky;
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
const Image = @import("../image/image.zig").Image;

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

pub const Material = struct {
    pub const Mode = enum { Sky, Sun };

    super: Base,

    emission_map: Texture,
    distribution: Distribution2D = .{},
    sun_radiance: math.InterpolatedFunction1D(Vec4f) = .{},
    average_emission: Vec4f = @splat(4, @as(f32, -1.0)),
    total_weight: f32 = undefined,

    mode: Mode = undefined,

    sky: *const SkyThing,

    pub fn initSky(sampler_key: ts.Key, emission_map: Texture, sky: *const SkyThing) Material {
        return Material{
            .super = Base.init(sampler_key, false),
            .emission_map = emission_map,
            .mode = .Sky,
            .sky = sky,
        };
    }

    pub fn initSun(alloc: *Allocator, sampler_key: ts.Key, sky: *const SkyThing) !Material {
        return Material{
            .super = Base.init(sampler_key, false),
            .emission_map = .{},
            .sun_radiance = try math.InterpolatedFunction1D(Vec4f).init(alloc, 0.0, 1.0, 1024),
            .mode = .Sun,
            .sky = sky,
        };
    }

    pub fn deinit(self: *Material, alloc: *Allocator) void {
        self.sun_radiance.deinit(alloc);
        self.distribution.deinit(alloc);
    }

    pub fn commit(self: *Material) void {
        self.super.properties.set(.EmissionMap, self.emission_map.isValid());
    }

    pub fn setSunRadiance(self: *Material, model: Model) void {
        const n = @intToFloat(f32, self.sun_radiance.samples.len - 1);

        for (self.sun_radiance.samples) |*s, i| {
            const v = @intToFloat(f32, i) / n;
            var wi = self.sky.sunWi(v);
            wi[1] = std.math.max(wi[1], 0.0);

            s.* = model.evaluateSkyAndSun(wi);
        }

        self.average_emission = model.evaluateSkyAndSun(-self.sky.sunDirection());
    }

    pub fn prepareSampling(
        self: *Material,
        alloc: *Allocator,
        shape: Shape,
        scene: Scene,
        threads: *Threads,
    ) Vec4f {
        if (self.average_emission[0] >= 0.0) {
            // Hacky way to check whether prepare_sampling has been called before
            // average_emission_ is initialized with negative values...
            return self.average_emission;
        }

        var avg = @splat(4, @as(f32, 0.0));

        {
            const d = self.emission_map.description(scene).dimensions;
            const height = @intCast(u32, d.v[1]);

            var context = Context{
                .shape = &shape,
                .image = scene.imageRef(self.emission_map.image),
                .dimensions = .{ d.v[0], d.v[1] },
                .conditional = self.distribution.allocate(alloc, height) catch
                    return @splat(4, @as(f32, 0.0)),
                .averages = alloc.alloc(Vec4f, threads.numThreads()) catch
                    return @splat(4, @as(f32, 0.0)),
                .alloc = alloc,
            };

            defer alloc.free(context.averages);

            _ = threads.runRange(&context, Context.calculate, 0, height);

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
            radiance = self.sun_radiance.eval(self.sky.sunV(-wo));
        }

        var result = Sample.init(rs, wo, radiance);
        result.super.layer.setTangentFrame(rs.t, rs.b, rs.n);
        return result;
    }

    pub fn evaluateRadiance(self: Material, wi: Vec4f, uvw: Vec4f, filter: ?ts.Filter, worker: Worker) Vec4f {
        if (self.emission_map.isValid()) {
            const key = ts.resolveKey(self.super.sampler_key, filter);
            return ts.sample2D_3(key, self.emission_map, .{ uvw[0], uvw[1] }, worker.scene.*);
        }

        return self.sun_radiance.eval(self.sky.sunV(wi));
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
    image: *const Image,
    dimensions: Vec2i,
    conditional: []Distribution1D,
    averages: []Vec4f,
    alloc: *Allocator,

    pub fn calculate(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        const self = @intToPtr(*Context, context);

        const d = self.dimensions;

        var luminance = self.alloc.alloc(f32, @intCast(usize, d[0])) catch return;
        defer self.alloc.free(luminance);

        const idf = @splat(2, @as(f32, 1.0)) / math.vec2iTo2f(d);

        var avg = @splat(4, @as(f32, 0.0));

        var y = begin;
        while (y < end) : (y += 1) {
            const v = idf[1] * (@intToFloat(f32, y) + 0.5);

            var x: u32 = 0;
            while (x < d[0]) : (x += 1) {
                const u = idf[0] * (@intToFloat(f32, x) + 0.5);

                const uv_weight = self.shape.uvWeight(.{ u, v });

                //       const li = Vec4f{ 0.0, 0.0, 2.0, 0.0 }; //self.texture.get2D_3(@intCast(i32, x), @intCast(i32, y), self.scene.*);

                //      self.image.Float3.set2D(@intCast(i32, x), @intCast(i32, y), math.vec4fTo3f(li));
                const li = math.vec3fTo4f(self.image.Float3.get2D(@intCast(i32, x), @intCast(i32, y)));

                const wli = @splat(4, uv_weight) * li;

                avg += Vec4f{ wli[0], wli[1], wli[2], uv_weight };

                luminance[x] = spectrum.luminance(wli);
            }

            self.conditional[y].configure(self.alloc, luminance, 0) catch {};
        }

        self.averages[id] = avg;
    }
};
