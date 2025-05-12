const math = @import("base").math;
const Distribution1D = math.Distribution1D;
const Mat4x4 = math.Mat4x4;
const Vec2u = math.Vec2u;
const Vec2f = math.Vec2f;

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

pub const Prototype = struct {
    shape_file: []u8,
    materials: [][]u8,

    scale_range: Vec2f,

    pub fn deinit(self: *Prototype, alloc: Allocator) void {
        for (self.materials) |m| {
            alloc.free(m);
        }

        alloc.free(self.materials);
        alloc.free(self.shape_file);
    }
};

pub const Instance = struct {
    prototype: u32,
    transformation: Mat4x4,
};

pub const Project = struct {
    scene_filename: []u8 = &.{},

    mount_folder: []u8 = &.{},

    prototypes: []Prototype = &.{},

    prototype_distribution: Distribution1D = .{},

    density: f32 = 1.0,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.prototype_distribution.deinit(alloc);

        for (self.prototypes) |*p| {
            p.deinit(alloc);
        }

        alloc.free(self.prototypes);
        alloc.free(self.mount_folder);
        alloc.free(self.scene_filename);
    }
};
