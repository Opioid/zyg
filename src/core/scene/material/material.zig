pub const Debug = @import("debug/material.zig").Material;
pub const Glass = @import("glass/material.zig").Material;
pub const Light = @import("light/material.zig").Material;
pub const Substitute = @import("substitute/material.zig").Material;
pub const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../renderstate.zig").Renderstate;
const Worker = @import("../worker.zig").Worker;

const math = @import("base").math;
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

    pub fn isEmissive(self: Material) bool {
        return switch (self) {
            .Light => true,
            else => false,
        };
    }

    pub fn isTwoSided(self: Material) bool {
        return switch (self) {
            .Debug => true,
            .Substitute => |m| m.super.properties.is(.Two_sided),
            else => false,
        };
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        return switch (self) {
            .Debug => .{ .Debug = Debug.sample(wo, rs) },
            .Glass => |g| .{ .Glass = g.sample(wo, rs) },
            .Light => |l| .{ .Light = l.sample(wo, rs, worker) },
            .Substitute => |s| .{ .Substitute = s.sample(wo, rs, worker) },
        };
    }
};
