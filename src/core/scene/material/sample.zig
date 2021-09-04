const Debug = @import("debug/sample.zig").Sample;
const Glass = @import("glass/sample.zig").Sample;
const Light = @import("light/sample.zig").Sample;
const Substitute = @import("substitute/sample.zig").Sample;
const Base = @import("sample_base.zig").SampleBase;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Sample = union(enum) {
    Debug: Debug,
    Glass: Glass,
    Light: Light,
    Substitute: Substitute,

    pub fn deinit(self: *Sample, alloc: *Allocator) void {
        _ = self;
        _ = alloc;
    }

    pub fn super(self: Sample) Base {
        return switch (self) {
            .Debug => |d| d.super,
            .Glass => |g| g.super,
            .Light => |l| l.super,
            .Substitute => |s| s.super,
        };
    }
};
