const Base = @import("camera_base.zig").Base;
pub const Orthographic = @import("camera_orthographic.zig").Orthographic;
pub const Perspective = @import("camera_perspective.zig").Perspective;
const cs = @import("camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Scene = @import("../scene/scene.zig").Scene;
const vt = @import("../scene/vertex.zig");
const Vertex = vt.Vertex;
const RayDif = vt.RayDif;
const Sampler = @import("../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Camera = union(enum) {
    Orthographic: Orthographic,
    Perspective: Perspective,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        switch (self.*) {
            .Perspective => |*p| p.deinit(alloc),
            else => {},
        }
    }

    pub fn super(self: *Self) *Base {
        return switch (self.*) {
            inline else => |*m| &m.super,
        };
    }

    pub fn resolution(self: *const Self) Vec2i {
        return switch (self.*) {
            inline else => |c| c.super.resolution,
        };
    }

    pub fn crop(self: *const Self) Vec4i {
        return switch (self.*) {
            inline else => |c| c.super.crop,
        };
    }

    pub fn numLayers(self: *const Self) u32 {
        return switch (self.*) {
            .Perspective => |c| c.numLayers(),
            else => 1,
        };
    }

    pub fn layerExtension(self: *const Self, layer: u32) []const u8 {
        return switch (self.*) {
            .Perspective => |c| c.layerExtension(layer),
            else => "",
        };
    }

    pub fn update(self: *Self, time: u64, scene: *const Scene) void {
        return switch (self.*) {
            .Orthographic => |*c| c.update(),
            .Perspective => |*c| c.update(time, scene),
        };
    }

    // Only for CAPI at the moment... lame.
    pub fn setFov(self: *Self, fov: f32) void {
        return switch (self.*) {
            .Perspective => |*c| c.fov = fov,
            else => {},
        };
    }

    pub fn generateVertex(self: *const Self, sample: Sample, layer: u32, frame: u32, scene: *const Scene) Vertex {
        return switch (self.*) {
            .Orthographic => |c| c.generateVertex(sample, frame, scene),
            .Perspective => |c| c.generateVertex(sample, layer, frame, scene),
        };
    }

    pub fn sampleTo(
        self: *const Self,
        layer: u32,
        bounds: Vec4i,
        time: u64,
        p: Vec4f,
        sampler: *Sampler,
        scene: *const Scene,
    ) ?SampleTo {
        return switch (self.*) {
            .Perspective => |c| c.sampleTo(layer, bounds, time, p, sampler, scene),
            else => null,
        };
    }

    pub fn calculateRayDifferential(self: *const Self, layer: u32, p: Vec4f, time: u64, scene: *const Scene) RayDif {
        return switch (self.*) {
            .Orthographic => |c| c.calculateRayDifferential(p, time, scene),
            .Perspective => |c| c.calculateRayDifferential(layer, p, time, scene),
        };
    }
};
