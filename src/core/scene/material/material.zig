pub const Debug = @import("debug/material.zig").Material;
pub const Glass = @import("glass/material.zig").Material;
pub const Light = @import("light/material.zig").Material;
pub const Substitute = @import("substitute/material.zig").Material;
pub const Sample = @import("sample.zig").Sample;
const Base = @import("material_base.zig").Base;
const ccoef = @import("collision_coefficients.zig");
const CC = ccoef.CC;
const Renderstate = @import("../renderstate.zig").Renderstate;
const Scene = @import("../scene.zig").Scene;
const Shape = @import("../shape/shape.zig").Shape;
const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Worker = @import("../worker.zig").Worker;
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
    Substitute: Substitute,

    pub fn deinit(self: *Material, alloc: *Allocator) void {
        switch (self.*) {
            .Light => |*m| m.deinit(alloc),
            else => {},
        }
    }

    pub fn super(self: Material) Base {
        return switch (self) {
            .Debug => |m| m.super,
            .Glass => |m| m.super,
            .Light => |m| m.super,
            .Substitute => |m| m.super,
        };
    }

    pub fn commit(self: *Material) void {
        switch (self.*) {
            .Glass => |*m| m.commit(),
            .Light => |*m| m.commit(),
            .Substitute => |*m| m.commit(),
            else => {},
        }
    }

    pub fn prepareSampling(
        self: *Material,
        alloc: *Allocator,
        shape: Shape,
        part: u32,
        trafo: Transformation,
        extent: f32,
        scene: Scene,
        threads: *Threads,
    ) Vec4f {
        _ = part;
        _ = trafo;

        return switch (self.*) {
            .Light => |*m| m.prepareSampling(alloc, shape, extent, scene, threads),
            .Substitute => |m| m.prepareSampling(scene),
            else => @splat(4, @as(f32, 0.0)),
        };
    }

    pub fn isMasked(self: Material) bool {
        return self.super().mask.isValid();
    }

    pub fn isTwoSided(self: Material) bool {
        return switch (self) {
            .Debug => true,
            .Glass => |m| m.thickness > 0.0,
            .Substitute => |m| m.super.properties.is(.TwoSided),
            else => false,
        };
    }

    pub fn hasTintedShadow(self: Material) bool {
        return switch (self) {
            .Glass => |m| m.thickness > 0.0,
            else => false,
        };
    }

    pub fn isEmissive(self: Material) bool {
        return switch (self) {
            .Light => true,
            .Substitute => |m| {
                if (m.super.properties.is(.EmissionMap)) {
                    return true;
                }

                return math.anyGreaterZero(m.super.emission);
            },
            else => false,
        };
    }

    pub fn hasEmissionMap(self: Material) bool {
        return self.super().properties.is(.EmissionMap);
    }

    pub fn isPureEmissive(self: Material) bool {
        return switch (self) {
            .Light => true,
            else => false,
        };
    }

    pub fn isScatteringVolume(self: Material) bool {
        return switch (self) {
            .Substitute => |m| {
                return m.super.properties.is(.ScatteringVolume);
            },
            else => false,
        };
    }

    pub fn ior(self: Material) f32 {
        return self.super().ior;
    }

    pub fn collisionCoefficients(self: Material, uv: Vec2f, filter: ?ts.Filter, worker: Worker) CC {
        const sup = self.super();
        const color_map = sup.color_map;
        if (color_map.isValid()) {
            const key = ts.resolveKey(sup.sampler_key, filter);
            const color = ts.sample2D_3(key, color_map, uv, worker.scene.*);
            return ccoef.scattering(sup.cc.a, color, sup.volumetric_anisotropy);
        }

        return sup.cc;
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        return switch (self) {
            .Debug => .{ .Debug = Debug.sample(wo, rs) },
            .Glass => |g| .{ .Glass = g.sample(wo, rs, worker) },
            .Light => |l| .{ .Light = l.sample(wo, rs, worker) },
            .Substitute => |s| .{ .Substitute = s.sample(wo, rs, worker) },
        };
    }

    pub fn evaluateRadiance(
        self: Material,
        wi: Vec4f,
        n: Vec4f,
        uvw: Vec4f,
        extent: f32,
        filter: ?ts.Filter,
        worker: Worker,
    ) Vec4f {
        return switch (self) {
            .Light => |m| m.evaluateRadiance(uvw, extent, filter, worker),
            .Substitute => |m| m.evaluateRadiance(wi, n, uvw, filter, worker),
            else => @splat(4, @as(f32, 0.0)),
        };
    }

    pub fn radianceSample(self: Material, r3: Vec4f) Base.RadianceSample {
        return switch (self) {
            .Light => |m| m.radianceSample(r3),
            else => Base.RadianceSample.init3(r3, 1.0),
        };
    }

    pub fn emissionPdf(self: Material, uvw: Vec4f) f32 {
        return switch (self) {
            .Light => |m| m.emissionPdf(.{ uvw[0], uvw[1] }),
            else => 1.0,
        };
    }

    pub fn opacity(self: Material, uv: Vec2f, filter: ?ts.Filter, worker: Worker) f32 {
        return self.super().opacity(uv, filter, worker);
    }

    pub fn visibility(self: Material, wi: Vec4f, n: Vec4f, uv: Vec2f, filter: ?ts.Filter, worker: Worker) ?Vec4f {
        return switch (self) {
            .Glass => |m| {
                return m.visibility(wi, n, uv, filter, worker);
            },
            else => {
                const o = self.opacity(uv, filter, worker);
                return if (o < 1.0) @splat(4, 1.0 - o) else null;
            },
        };
    }
};
