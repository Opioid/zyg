const Debug = @import("debug/material.zig").Material;
const Glass = @import("glass/material.zig").Material;
const Light = @import("light/material.zig").Material;
const Substitute = @import("substitute/material.zig").Material;
pub const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../renderstate.zig").Renderstate;

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

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate) Sample {
        return switch (self) {
            .Debug => |d| .{ .Debug = d.sample(rs, wo) },
            .Glass => |g| .{ .Glass = g.sample(rs, wo) },
            .Light => |l| .{ .Light = l.sample(rs, wo) },
            .Substitute => |s| .{ .Substitute = s.sample(rs, wo) },
        };
    }
};
