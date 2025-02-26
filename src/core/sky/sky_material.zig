const Sky = @import("sky.zig").Sky;
const Base = @import("../scene/material/material_base.zig").Base;
const Sample = @import("../scene/material/light/light_sample.zig").Sample;
const Renderstate = @import("../scene/renderstate.zig").Renderstate;
const Scene = @import("../scene/scene.zig").Scene;
const Resources = @import("../resource/manager.zig").Manager;
const Shape = @import("../scene/shape/shape.zig").Shape;
const Trafo = @import("../scene/composed_transformation.zig").ComposedTransformation;
const ts = @import("../image/texture/texture_sampler.zig");
const Texture = @import("../image/texture/texture.zig").Texture;
const Sampler = @import("../sampler/sampler.zig").Sampler;
const img = @import("../image/image.zig");

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Distribution1D = math.Distribution1D;
const Distribution2D = math.Distribution2D;
const Threads = base.thread.Pool;
const spectrum = base.spectrum;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Material = struct {
    super: Base,

    emission_map: Texture,
    distribution: Distribution2D = .{},
    sun_radiance: math.InterpolatedFunction1D(Vec4f) = .{},
    average_emission: Vec4f = @splat(-1.0),
    total_weight: f32 = undefined,

    pub fn initSky(emission_map: Texture) Material {
        return Material{
            .super = .{ .sampler_key = .{ .address = .{ .u = .Clamp, .v = .Clamp } } },
            .emission_map = emission_map,
        };
    }

    pub fn initSun(alloc: Allocator) !Material {
        return Material{
            .super = .{ .sampler_key = .{ .address = .{ .u = .Clamp, .v = .Clamp } } },
            .emission_map = .{},
            .sun_radiance = try math.InterpolatedFunction1D(Vec4f).init(alloc, 0.0, 1.0, Sky.Bake_dimensions_sun),
        };
    }

    pub fn deinit(self: *Material, alloc: Allocator) void {
        self.sun_radiance.deinit(alloc);
        self.distribution.deinit(alloc);
    }

    pub fn commit(self: *Material) void {
        self.super.properties.emissive = true;
        self.super.properties.emission_map = self.emission_map.valid();
    }

    pub fn setSunRadiance(self: *Material, rotation: Mat3x3, image: img.Float3) void {
        for (self.sun_radiance.samples, 0..) |*s, i| {
            s.* = math.vec3fTo4f(image.pixels[i]);
        }

        var total: Vec4f = @splat(0.0);
        var tw: f32 = 0.0;
        for (0..self.sun_radiance.samples.len - 1) |i| {
            const s0 = self.sun_radiance.samples[i];
            const s1 = self.sun_radiance.samples[i + 1];

            const v = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(self.sun_radiance.samples.len));
            const wi = Sky.sunWi(rotation, v);

            const w = @sin(v);
            tw += w;

            if (wi[1] >= 0.0) {
                total += (s0 + s1) * @as(Vec4f, @splat(0.5 * w));
            }
        }

        self.average_emission = total / @as(Vec4f, @splat(tw));
    }

    pub fn setSunRadianceZero(self: *Material) void {
        for (self.sun_radiance.samples) |*s| {
            s.* = @splat(0.0);
        }

        self.average_emission = @splat(0.0);
    }

    pub fn prepareSampling(
        self: *Material,
        alloc: Allocator,
        shape: *const Shape,
        scene: *const Scene,
        threads: *Threads,
    ) Vec4f {
        if (self.average_emission[0] >= 0.0) {
            // Hacky way to check whether prepare_sampling has been called before
            // average_emission_ is initialized with negative values...
            return self.average_emission;
        }

        var avg: Vec4f = @splat(0.0);

        {
            const d = self.emission_map.description(scene).dimensions;
            const height: u32 = @intCast(d[1]);

            var context = Context{
                .shape = shape,
                .image = scene.imagePtr(self.emission_map.data.image.id),
                .dimensions = .{ d[0], d[1] },
                .conditional = self.distribution.allocate(alloc, height) catch
                    return @splat(0.0),
                .averages = alloc.alloc(Vec4f, threads.numThreads()) catch
                    return @splat(0.0),
                .alloc = alloc,
            };

            defer alloc.free(context.averages);

            const num = threads.runRange(&context, Context.calculate, 0, height, 0);
            for (context.averages[0..num]) |a| {
                avg += a;
            }
        }

        const average_emission = avg / @as(Vec4f, @splat(avg[3]));

        self.average_emission = average_emission;

        self.total_weight = avg[3];

        self.distribution.configure(alloc) catch
            return @splat(0.0);

        return average_emission;
    }

    pub fn sample(wo: Vec4f, rs: Renderstate) Sample {
        var result = Sample.init(rs, wo);
        result.super.frame = .{ .x = rs.t, .y = rs.b, .z = rs.n };
        return result;
    }

    pub fn evaluateRadiance(
        self: *const Material,
        wi: Vec4f,
        uv: Vec2f,
        trafo: Trafo,
        sampler: *Sampler,
        scene: *const Scene,
    ) Vec4f {
        if (self.emission_map.valid()) {
            return ts.sample2D_3(self.super.sampler_key, self.emission_map, uv, sampler, scene);
        }

        return self.sun_radiance.eval(sunV(trafo.rotation, wi));
    }

    fn sunV(rotation: Mat3x3, wi: Vec4f) f32 {
        const k = wi - rotation.r[2];
        const c = -math.dot3(rotation.r[1], k) / Sky.Radius;
        return math.max((c + 1.0) * 0.5, 0.0);
    }

    pub fn radianceSample(self: *const Material, r3: Vec4f) Base.RadianceSample {
        const result = self.distribution.sampleContinuous(.{ r3[0], r3[1] });

        return Base.RadianceSample.init2(result.uv, result.pdf * self.total_weight);
    }

    pub fn emissionPdf(self: *const Material, uv: Vec2f) f32 {
        if (self.emission_map.valid()) {
            return self.distribution.pdf(self.super.sampler_key.address.address2(uv)) * self.total_weight;
        }

        return 1.0;
    }
};

const Context = struct {
    shape: *const Shape,
    image: *const img.Image,
    dimensions: Vec2i,
    conditional: []Distribution1D,
    averages: []Vec4f,
    alloc: Allocator,

    pub fn calculate(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        const self: *Context = @ptrCast(context);

        const d = self.dimensions;

        var luminance = self.alloc.alloc(f32, @as(usize, @intCast(d[0]))) catch return;
        defer self.alloc.free(luminance);

        const idf = @as(Vec2f, @splat(1.0)) / @as(Vec2f, @floatFromInt(d));

        var avg: Vec4f = @splat(0.0);

        var y = begin;
        while (y < end) : (y += 1) {
            const v = idf[1] * (@as(f32, @floatFromInt(y)) + 0.5);

            var x: u32 = 0;
            while (x < d[0]) : (x += 1) {
                const u = idf[0] * (@as(f32, @floatFromInt(x)) + 0.5);
                const uv_weight = self.shape.uvWeight(.{ u, v });

                const li = math.vec3fTo4f(self.image.Float3.get2D(@as(i32, @intCast(x)), @as(i32, @intCast(y))));
                const wli = @as(Vec4f, @splat(uv_weight)) * li;

                avg += Vec4f{ wli[0], wli[1], wli[2], uv_weight };

                luminance[x] = math.hmax3(wli);
            }

            self.conditional[y].configure(self.alloc, luminance, 0) catch {};
        }

        self.averages[id] = avg;
    }
};
