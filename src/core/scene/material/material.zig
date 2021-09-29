pub const Debug = @import("debug/material.zig").Material;
pub const Glass = @import("glass/material.zig").Material;
pub const Light = @import("light/material.zig").Material;
pub const Substitute = @import("substitute/material.zig").Material;
pub const Sample = @import("sample.zig").Sample;
const Base = @import("material_base.zig").Base;
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

    pub fn isTwoSided(self: Material) bool {
        return switch (self) {
            .Debug => true,
            .Glass => |m| m.super.properties.is(.TwoSided),
            .Substitute => |m| m.super.properties.is(.TwoSided),
            else => false,
        };
    }

    pub fn isMasked(self: Material) bool {
        return self.super().mask.isValid();
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

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        return switch (self) {
            .Debug => .{ .Debug = Debug.sample(wo, rs) },
            .Glass => |g| .{ .Glass = g.sample(wo, rs) },
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
        _ = wi;
        _ = n;
        return switch (self) {
            .Light => |m| m.evaluateRadiance(extent),
            .Substitute => |m| m.evaluateRadiance(uvw, filter, worker),
            else => @splat(4, @as(f32, 0.0)),
        };
    }

    pub fn opacity(self: Material, uv: Vec2f, filter: ?ts.Filter, worker: Worker) f32 {
        const key = ts.resolveKey(self.super().sampler_key, filter);
        const mask = self.super().mask;
        if (mask.isValid()) {
            return ts.sample2D_1(key, mask, uv, worker.scene.*);
        }

        return 1.0;
    }

    pub fn visibility(self: Material, uv: Vec2f, filter: ?ts.Filter, worker: Worker) ?Vec4f {
        const o = self.opacity(uv, filter, worker);

        if (o < 1.0) {
            return @splat(4, 1.0 - o);
        }

        return null;
    }
};
