pub const Debug = @import("debug/debug_material.zig").Material;
pub const Glass = @import("glass/glass_material.zig").Material;
pub const Hair = @import("hair/hair_material.zig").Material;
pub const Light = @import("light/light_material.zig").Material;
pub const Substitute = @import("substitute/substitute_material.zig").Material;
pub const Volumetric = @import("volumetric/volumetric_material.zig").Material;
const Sky = @import("../../sky/sky_material.zig").Material;
pub const Sample = @import("material_sample.zig").Sample;
pub const Base = @import("material_base.zig").Base;
const Gridtree = @import("volumetric/gridtree.zig").Gridtree;
const ccoef = @import("collision_coefficients.zig");
const CC = ccoef.CC;
const CCE = ccoef.CCE;
const Renderstate = @import("../renderstate.zig").Renderstate;
const Scene = @import("../scene.zig").Scene;
const Shape = @import("../shape/shape.zig").Shape;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Worker = @import("../../rendering/worker.zig").Worker;
const image = @import("../../image/image.zig");
const Texture = @import("../../image/texture/texture.zig").Texture;
const ts = @import("../../image/texture/texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const LowThreshold = @import("../../rendering/integrator/helper.zig").LightSampling.LowThreshold;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Material = union(enum) {
    Debug: Debug,
    Glass: Glass,
    Hair: Hair,
    Light: Light,
    Sky: Sky,
    Substitute: Substitute,
    Volumetric: Volumetric,

    pub fn deinit(self: *Material, alloc: Allocator) void {
        switch (self.*) {
            inline .Light, .Sky, .Volumetric => |*m| m.deinit(alloc),
            else => {},
        }
    }

    pub fn super(self: *const Material) *const Base {
        return switch (self.*) {
            inline else => |*m| &m.super,
        };
    }

    pub fn commit(self: *Material, alloc: Allocator, scene: *const Scene, threads: *Threads) !void {
        switch (self.*) {
            .Debug => {},
            .Volumetric => |*m| try m.commit(alloc, scene, threads),
            inline else => |*m| m.commit(),
        }
    }

    pub fn prepareSampling(
        self: *Material,
        alloc: Allocator,
        shape: *const Shape,
        part: u32,
        trafo: Trafo,
        extent: f32,
        scene: *const Scene,
        threads: *Threads,
    ) Vec4f {
        _ = part;
        _ = trafo;

        return switch (self.*) {
            .Light => |*m| m.prepareSampling(alloc, shape, extent, scene, threads),
            .Sky => |*m| m.prepareSampling(alloc, shape, scene, threads),
            .Substitute => |*m| m.prepareSampling(extent, scene),
            .Volumetric => |*m| m.prepareSampling(alloc, scene, threads),
            else => @splat(0.0),
        };
    }

    pub fn twoSided(self: *const Material) bool {
        return self.super().properties.two_sided;
    }

    pub fn caustic(self: *const Material) bool {
        return self.super().properties.caustic;
    }

    pub fn evaluateVisibility(self: *const Material) bool {
        return self.super().properties.evaluate_visibility;
    }

    pub fn emissive(self: *const Material) bool {
        return self.super().properties.emissive;
    }

    pub fn emissionImageMapped(self: *const Material) bool {
        return self.super().properties.emission_image_map;
    }

    pub fn scatteringVolume(self: *const Material) bool {
        return self.super().properties.scattering_volume;
    }

    pub fn pureEmissive(self: *const Material) bool {
        return switch (self.*) {
            .Light => true,
            else => false,
        };
    }

    pub fn heterogeneousVolume(self: *const Material) bool {
        return switch (self.*) {
            .Volumetric => |*m| !m.density_map.isUniform(),
            else => false,
        };
    }

    pub fn denseSSSOptimization(self: *const Material) bool {
        return self.super().properties.dense_sss_optimization;
    }

    pub fn volumetricTree(self: *const Material) ?Gridtree {
        return switch (self.*) {
            .Volumetric => |*m| if (!m.density_map.isUniform()) m.tree else null,
            else => null,
        };
    }

    pub fn ior(self: *const Material) f32 {
        return switch (self.*) {
            inline .Glass, .Hair, .Substitute => |*m| m.ior,
            .Volumetric => 0.0,
            else => 1.0,
        };
    }

    pub fn numSamples(self: *const Material, split_threshold: f32) u32 {
        if (split_threshold <= LowThreshold) {
            return 1;
        }

        return switch (self.*) {
            inline .Light, .Substitute => |*m| m.emittance.num_samples,
            else => 1,
        };
    }

    pub fn emissionAngle(self: *const Material) f32 {
        return switch (self.*) {
            inline .Light, .Substitute => |*m| m.emittance.cos_a,
            else => -1.0,
        };
    }

    pub fn collisionCoefficients(self: *const Material) CC {
        return switch (self.*) {
            .Glass => |*m| .{ .a = m.absorption, .s = @splat(0.0) },
            inline .Substitute, .Volumetric => |*m| m.cc,
            else => undefined,
        };
    }

    pub fn collisionCoefficients2D(self: *const Material, mat_sample: *const Sample) CC {
        const sup = self.super();
        const cc = self.collisionCoefficients();

        if (sup.properties.color_map) {
            const color = mat_sample.super().albedo;
            return ccoef.scattering(cc.a, color, cc.anisotropy());
        }

        return cc;
    }

    pub fn collisionCoefficients3D(self: *const Material, uvw: Vec4f, cc: CC, sampler: *Sampler, scene: *const Scene) CC {
        return switch (self.*) {
            .Volumetric => |*m| cc.scaled(@splat(m.density(uvw, sampler, scene))),
            else => cc,
        };
    }

    pub fn collisionCoefficientsEmission(self: *const Material, uvw: Vec4f, cc: CC, sampler: *Sampler, scene: *const Scene) CCE {
        return switch (self.*) {
            .Volumetric => |*m| m.collisionCoefficientsEmission(uvw, cc, sampler, scene),
            else => undefined,
        };
    }

    pub fn similarityRelationScale(self: *const Material, depth: u32) f32 {
        return switch (self.*) {
            .Volumetric => |*m| m.similarityRelationScale(depth),
            else => 1.0,
        };
    }

    pub fn sample(self: *const Material, wo: Vec4f, rs: Renderstate, sampler: *Sampler, worker: *const Worker) Sample {
        return switch (self.*) {
            .Debug => .{ .Debug = Debug.sample(wo, rs) },
            .Glass => |*m| .{ .Glass = m.sample(wo, rs, sampler, worker.scene) },
            .Hair => |*m| .{ .Hair = m.sample(wo, rs, sampler) },
            .Light => .{ .Light = Light.sample(wo, rs) },
            .Sky => .{ .Light = Sky.sample(wo, rs) },
            .Substitute => |*m| m.sample(wo, rs, sampler, worker),
            .Volumetric => |*m| .{ .Volumetric = m.sample(wo, rs) },
        };
    }

    pub fn evaluateRadiance(self: *const Material, wi: Vec4f, rs: Renderstate, sampler: *Sampler, scene: *const Scene) Vec4f {
        return switch (self.*) {
            .Light => |*m| m.evaluateRadiance(wi, rs, sampler, scene),
            .Sky => |*m| m.evaluateRadiance(wi, rs, sampler, scene),
            .Substitute => |*m| m.evaluateRadiance(wi, rs, sampler, scene),
            .Volumetric => |*m| m.evaluateRadiance(rs, sampler, scene),
            else => @splat(0.0),
        };
    }

    pub fn imageRadiance(self: *const Material, uv: Vec2f, sampler: *Sampler, scene: *const Scene) Vec4f {
        return switch (self.*) {
            inline .Light, .Substitute => |*m| m.emittance.imageRadiance(uv, m.super.sampler_key, sampler, scene),
            else => @splat(0.0),
        };
    }

    pub fn radianceSample(self: *const Material, r3: Vec4f) Base.RadianceSample {
        return switch (self.*) {
            inline .Light, .Sky, .Volumetric => |*m| m.radianceSample(r3),
            else => Base.RadianceSample.init3(r3, 1.0),
        };
    }

    pub fn emissionPdf(self: *const Material, uvw: Vec4f) f32 {
        return switch (self.*) {
            .Light => |*m| m.emissionPdf(.{ uvw[0], uvw[1] }),
            .Sky => |*m| m.emissionPdf(.{ uvw[0], uvw[1] }),
            .Volumetric => |*m| m.emissionPdf(uvw),
            else => 1.0,
        };
    }

    pub fn visibility(
        self: *const Material,
        wi: Vec4f,
        rs: Renderstate,
        sampler: *Sampler,
        scene: *const Scene,
        tr: *Vec4f,
    ) bool {
        switch (self.*) {
            .Glass => |*m| {
                return m.visibility(wi, rs, sampler, scene, tr);
            },
            else => {
                const o = self.super().opacity(rs, sampler, scene);
                if (o < 1.0) {
                    tr.* *= @splat(1.0 - o);
                    return true;
                }
                return false;
            },
        }
    }

    pub fn usefulTexture(self: *const Material) ?Texture {
        const texture = switch (self.*) {
            .Light => |*m| m.emittance.emission_map,
            .Sky => |*m| m.emission_map,
            .Substitute => |*m| m.emittance.emission_map,
            .Volumetric => |*m| m.density_map,
            inline else => |*m| m.super.mask,
        };

        return if (!texture.isUniform()) texture else null;
    }
};
