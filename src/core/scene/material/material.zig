pub const Debug = @import("debug/material.zig").Material;
pub const Glass = @import("glass/material.zig").Material;
pub const Light = @import("light/material.zig").Material;
pub const Substitute = @import("substitute/material.zig").Material;
pub const Volumetric = @import("volumetric/material.zig").Material;
const Sky = @import("../../sky/material.zig").Material;
pub const Sample = @import("sample.zig").Sample;
pub const Base = @import("material_base.zig").Base;
const Gridtree = @import("volumetric/gridtree.zig").Gridtree;
const ccoef = @import("collision_coefficients.zig");
const CC = ccoef.CC;
const CCE = ccoef.CCE;
const Renderstate = @import("../renderstate.zig").Renderstate;
const Scene = @import("../scene.zig").Scene;
const Shape = @import("../shape/shape.zig").Shape;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Worker = @import("../worker.zig").Worker;
const image = @import("../../image/image.zig");
const ts = @import("../../image/texture/sampler.zig");

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
    Light: Light,
    Sky: Sky,
    Substitute: Substitute,
    Volumetric: Volumetric,

    pub fn deinit(self: *Material, alloc: Allocator) void {
        switch (self.*) {
            .Light => |*m| m.deinit(alloc),
            .Sky => |*m| m.deinit(alloc),
            .Volumetric => |*m| m.deinit(alloc),
            else => {},
        }
    }

    pub fn super(self: *const Material) *const Base {
        return switch (self.*) {
            .Debug => |*m| &m.super,
            .Glass => |*m| &m.super,
            .Light => |*m| &m.super,
            .Sky => |*m| &m.super,
            .Substitute => |*m| &m.super,
            .Volumetric => |*m| &m.super,
        };
    }

    pub fn commit(self: *Material, alloc: Allocator, scene: *const Scene, threads: *Threads) !void {
        switch (self.*) {
            .Glass => |*m| m.commit(),
            .Light => |*m| m.commit(),
            .Sky => |*m| m.commit(),
            .Substitute => |*m| m.commit(),
            .Volumetric => |*m| try m.commit(alloc, scene, threads),
            else => {},
        }
    }

    pub fn prepareSampling(
        self: *Material,
        alloc: Allocator,
        shape: Shape,
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
            else => @splat(4, @as(f32, 0.0)),
        };
    }

    pub inline fn masked(self: *const Material) bool {
        return self.super().mask.valid();
    }

    pub inline fn twoSided(self: *const Material) bool {
        return switch (self.*) {
            .Debug => true,
            .Glass => |*m| m.thickness > 0.0,
            .Light => |*m| m.super.properties.is(.TwoSided),
            .Substitute => |*m| m.super.properties.is(.TwoSided),
            else => false,
        };
    }

    pub inline fn caustic(self: *const Material) bool {
        return self.super().properties.is(.Caustic);
    }

    pub inline fn tintedShadow(self: *const Material) bool {
        return switch (self.*) {
            .Glass => |*m| m.thickness > 0.0,
            else => false,
        };
    }

    pub inline fn emissive(self: *const Material) bool {
        return switch (self.*) {
            .Sky => true,
            .Light => |*m| math.anyGreaterZero3(m.super.emittance.value),
            .Substitute => |*m| math.anyGreaterZero3(m.super.emittance.value),
            .Volumetric => |*m| math.anyGreaterZero3(m.super.emittance.value),
            else => false,
        };
    }

    pub inline fn emissionMapped(self: *const Material) bool {
        return self.super().properties.is(.EmissionMap);
    }

    pub inline fn pureEmissive(self: *const Material) bool {
        return switch (self.*) {
            .Light, .Sky => true,
            else => false,
        };
    }

    pub inline fn scatteringVolume(self: *const Material) bool {
        return switch (self.*) {
            .Substitute => |*m| m.super.properties.is(.ScatteringVolume),
            .Volumetric => |*m| m.super.properties.is(.ScatteringVolume),
            else => false,
        };
    }

    pub inline fn heterogeneousVolume(self: *const Material) bool {
        return switch (self.*) {
            .Volumetric => |*m| m.density_map.valid(),
            else => false,
        };
    }

    pub inline fn volumetricTree(self: *const Material) ?Gridtree {
        return switch (self.*) {
            .Volumetric => |*m| if (m.density_map.valid()) m.tree else null,
            else => null,
        };
    }

    pub inline fn ior(self: *const Material) f32 {
        return self.super().ior;
    }

    pub fn collisionCoefficients(self: *const Material, uvw: Vec4f, filter: ?ts.Filter, scene: *const Scene) CC {
        const sup = self.super();
        const cc = sup.cc;

        switch (self.*) {
            .Volumetric => |*m| {
                const d = @splat(4, m.density(uvw, filter, scene));
                return .{ .a = d * cc.a, .s = d * cc.s };
            },
            else => {
                const color_map = sup.color_map;
                if (color_map.valid()) {
                    const key = ts.resolveKey(sup.sampler_key, filter);
                    const color = ts.sample2D_3(key, color_map, .{ uvw[0], uvw[1] }, scene);
                    return ccoef.scattering(cc.a, color, sup.volumetric_anisotropy);
                }

                return cc;
            },
        }
    }

    pub fn collisionCoefficientsEmission(self: *const Material, uvw: Vec4f, filter: ?ts.Filter, scene: *const Scene) CCE {
        const sup = self.super();
        const cc = sup.cc;

        switch (self.*) {
            .Volumetric => |*m| {
                return m.collisionCoefficientsEmission(uvw, filter, scene);
            },
            else => {
                const e = self.super().emittance.value;

                const color_map = sup.color_map;
                if (color_map.valid()) {
                    const key = ts.resolveKey(sup.sampler_key, filter);
                    const color = ts.sample2D_3(key, color_map, .{ uvw[0], uvw[1] }, scene);
                    return .{
                        .cc = ccoef.scattering(cc.a, color, sup.volumetric_anisotropy),
                        .e = e,
                    };
                }

                return .{ .cc = cc, .e = e };
            },
        }
    }

    pub fn sample(self: *const Material, wo: Vec4f, rs: *const Renderstate, worker: *const Worker) Sample {
        return switch (self.*) {
            .Debug => .{ .Debug = Debug.sample(wo, rs) },
            .Glass => |*g| .{ .Glass = g.sample(wo, rs, worker.scene) },
            .Light => |*l| .{ .Light = l.sample(wo, rs, worker.scene) },
            .Sky => |*s| .{ .Light = s.sample(wo, rs, worker.scene) },
            .Substitute => |*s| s.sample(wo, rs, worker),
            .Volumetric => |*v| v.sample(wo, rs),
        };
    }

    pub fn evaluateRadiance(
        self: *const Material,
        wi: Vec4f,
        n: Vec4f,
        uvw: Vec4f,
        trafo: Trafo,
        extent: f32,
        filter: ?ts.Filter,
        scene: *const Scene,
    ) Vec4f {
        return switch (self.*) {
            .Light => |*m| m.evaluateRadiance(wi, .{ uvw[0], uvw[1] }, trafo, extent, filter, scene),
            .Sky => |*m| m.evaluateRadiance(wi, .{ uvw[0], uvw[1] }, filter, scene),
            .Substitute => |*m| m.evaluateRadiance(wi, n, .{ uvw[0], uvw[1] }, trafo, extent, filter, scene),
            .Volumetric => |*m| m.evaluateRadiance(uvw, filter, scene),
            else => @splat(4, @as(f32, 0.0)),
        };
    }

    pub fn radianceSample(self: *const Material, r3: Vec4f) Base.RadianceSample {
        return switch (self.*) {
            .Light => |*m| m.radianceSample(r3),
            .Sky => |*m| m.radianceSample(r3),
            .Volumetric => |*m| m.radianceSample(r3),
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

    pub fn opacity(self: *const Material, uv: Vec2f, filter: ?ts.Filter, scene: *const Scene) f32 {
        return self.super().opacity(uv, filter, scene);
    }

    pub fn visibility(self: *const Material, wi: Vec4f, n: Vec4f, uv: Vec2f, filter: ?ts.Filter, scene: *const Scene) ?Vec4f {
        switch (self.*) {
            .Glass => |*m| {
                return m.visibility(wi, n, uv, filter, scene);
            },
            else => {
                const o = self.opacity(uv, filter, scene);
                return if (o < 1.0) @splat(4, 1.0 - o) else null;
            },
        }
    }

    pub fn usefulTextureDescription(self: *const Material, scene: *const Scene) image.Description {
        switch (self.*) {
            .Light => |*m| {
                if (m.emission_map.valid()) {
                    return m.emission_map.description(scene);
                }
            },
            .Sky => |*m| {
                if (m.emission_map.valid()) {
                    return m.emission_map.description(scene);
                }
            },
            .Substitute => |*m| {
                if (m.emission_map.valid()) {
                    return m.emission_map.description(scene);
                }
            },
            .Volumetric => |*m| {
                if (m.density_map.valid()) {
                    return m.density_map.description(scene);
                }
            },
            else => {},
        }

        const color_map = self.super().color_map;
        return if (color_map.valid()) color_map.description(scene) else .{};
    }
};
