pub const Debug = @import("debug/material.zig").Material;
pub const Glass = @import("glass/material.zig").Material;
pub const Light = @import("light/material.zig").Material;
pub const Substitute = @import("substitute/material.zig").Material;
pub const Sample = @import("sample.zig").Sample;
const Base = @import("material_base.zig").Base;
const Renderstate = @import("../renderstate.zig").Renderstate;
const Worker = @import("../worker.zig").Worker;
const ts = @import("../../image/texture/sampler.zig");

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Material = union(enum) {
    Debug: Debug,
    Glass: Glass,
    Light: Light,
    Substitute: Substitute,

    pub fn deinit(self: *Material, alloc: *Allocator) void {
        _ = self;
        _ = alloc;
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
        return self.super().hasEmissionMap();
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        return switch (self) {
            .Debug => .{ .Debug = Debug.sample(wo, rs) },
            .Glass => |g| .{ .Glass = g.sample(wo, rs) },
            .Light => |l| .{ .Light = l.sample(wo, rs, worker) },
            .Substitute => |s| .{ .Substitute = s.sample(wo, rs, worker) },
        };
    }

    pub fn opacity(self: Material, uv: Vec2f, filter: ?ts.Filter, worker: Worker) f32 {
        const key = ts.resolveKey(self.super().sampler_key, filter);
        const mask = self.super().mask;
        if (mask.isValid()) {
            return ts.sample2D_1(key, mask, uv, worker.scene);
        }

        return 1.0;
    }

    pub fn visibility(self: Material, uv: Vec2f, filter: ?ts.Filter, worker: Worker, vis: *Vec4f) bool {
        const o = self.opacity(uv, filter, worker);
        vis.* = @splat(4, 1.0 - o);
        return o < 1.0;
    }
};
