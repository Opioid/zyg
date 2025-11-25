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
const Context = @import("../context.zig").Context;
const Scene = @import("../scene.zig").Scene;
const Renderstate = @import("../renderstate.zig").Renderstate;
const Resources = @import("../../resource/manager.zig").Manager;
const Shape = @import("../shape/shape.zig").Shape;
const ShapeSampler = @import("../shape/shape_sampler.zig").Sampler;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const image = @import("../../image/image.zig");
const Texture = @import("../../texture/texture.zig").Texture;
const ts = @import("../../texture/texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;

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
            inline .Sky, .Volumetric => |*m| m.deinit(alloc),
            else => {},
        }
    }

    pub fn super(self: *const Material) *const Base {
        return switch (self.*) {
            inline else => |*m| &m.super,
        };
    }

    pub fn commit(self: *Material, alloc: Allocator, resources: *const Resources) !void {
        switch (self.*) {
            .Debug => {},
            .Volumetric => |*m| try m.commit(alloc, resources),
            inline .Glass, .Substitute => |*m| m.commit(resources),
            inline else => |*m| m.commit(),
        }
    }

    pub fn prepareSampling(
        self: *Material,
        alloc: Allocator,
        trafo: Trafo,
        time: u64,
        shape: *const Shape,
        light_link: u32,
        scene: *const Scene,
    ) !ShapeSampler {
        return switch (self.*) {
            .Light => |*m| m.prepareSampling(alloc, trafo, time, shape, light_link, scene),
            .Sky => |*m| m.prepareSampling(alloc, shape, scene.resources),
            .Substitute => |*m| m.prepareSampling(scene.resources),
            .Volumetric => |*m| m.prepareSampling(alloc, scene.resources),
            else => .{ .impl = .Uniform, .average_emission = @splat(0.0) },
        };
    }

    pub fn totalEmission(self: *const Material, emission: Vec4f, extent: f32) Vec4f {
        return switch (self.*) {
            inline .Light, .Substitute => |*m| m.emittance.totalEmission(emission, extent),
            else => emission * @as(Vec4f, @splat(extent)),
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

    pub fn emissionAngle(self: *const Material) f32 {
        return switch (self.*) {
            inline .Light, .Substitute => |*m| m.emittance.cos_a,
            else => -1.0,
        };
    }

    pub fn collisionCoefficients(self: *const Material) CC {
        return switch (self.*) {
            .Glass => |*m| .{ .a = m.absorption, .s = @splat(0.0) },
            inline .Volumetric => |*m| m.cc,
            else => undefined,
        };
    }

    pub fn collisionCoefficients3D(self: *const Material, uvw: Vec4f, cc: CC, sampler: *Sampler, context: Context) CC {
        return switch (self.*) {
            .Volumetric => |*m| cc.scaled(@splat(m.density(uvw, sampler.sample1D(), context))),
            else => cc,
        };
    }

    pub fn collisionCoefficientsEmission(self: *const Material, uvw: Vec4f, cc: CC, sampler: *Sampler, context: Context) CCE {
        return switch (self.*) {
            .Volumetric => |*m| m.collisionCoefficientsEmission(uvw, cc, sampler, context),
            else => undefined,
        };
    }

    pub fn similarityRelationScale(self: *const Material, depth: u32) f32 {
        return switch (self.*) {
            .Volumetric => |*m| m.similarityRelationScale(depth),
            else => 1.0,
        };
    }

    pub fn sample(self: *const Material, wo: Vec4f, rs: Renderstate, sampler: *Sampler, context: Context) Sample {
        return switch (self.*) {
            .Debug => .{ .Debug = Debug.sample(wo, rs) },
            .Glass => |*m| .{ .Glass = m.sample(wo, rs, sampler, context) },
            .Hair => |*m| .{ .Hair = m.sample(wo, rs, sampler) },
            .Light => .{ .Light = Light.sample(wo, rs) },
            .Sky => .{ .Light = Sky.sample(wo, rs) },
            .Substitute => |*m| m.sample(wo, rs, sampler, context),
            .Volumetric => |*m| .{ .Volumetric = m.sample(wo, rs) },
        };
    }

    pub fn evaluateRadiance(
        self: *const Material,
        wi: Vec4f,
        rs: Renderstate,
        in_camera: bool,
        sampler: *Sampler,
        context: Context,
    ) Vec4f {
        return switch (self.*) {
            .Light => |*m| m.evaluateRadiance(wi, rs, in_camera, sampler, context),
            .Sky => |*m| m.evaluateRadiance(wi, rs, sampler, context),
            .Substitute => |*m| m.evaluateRadiance(wi, rs, in_camera, sampler, context),
            .Volumetric => |*m| m.evaluateRadiance(rs, context),
            else => @splat(0.0),
        };
    }

    pub fn uniformRadiance(self: *const Material) Vec4f {
        return switch (self.*) {
            inline .Light, .Substitute => |*m| m.emittance.value,
            else => @splat(0.0),
        };
    }

    pub fn imageRadiance(self: *const Material, uv: Vec2f, sampler: *Sampler, resources: *const Resources) Vec4f {
        return switch (self.*) {
            inline .Light, .Substitute => |*m| m.emittance.imageRadiance(uv, sampler, resources),
            else => @splat(0.0),
        };
    }

    pub fn visibility(
        self: *const Material,
        wi: Vec4f,
        rs: Renderstate,
        sampler: *Sampler,
        context: Context,
        tr: *Vec4f,
    ) bool {
        switch (self.*) {
            .Glass => |*m| {
                return m.visibility(wi, rs, sampler, context, tr);
            },
            else => {
                const o = self.super().opacity(rs.uv(), sampler, context.scene.resources);
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
