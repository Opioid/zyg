const math = @import("base").math;
const Distribution1D = math.Distribution1D;
const Mat4x4 = math.Mat4x4;
const Vec2u = math.Vec2u;
const Vec2f = math.Vec2f;
const Transformation = math.Transformation;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub const Prototype = struct {
    shape_type: []u8,
    shape_file: []u8,
    materials: [][]u8,

    trafo: Transformation,

    position_jitter: Vec2f,
    incline_jitter: Vec2f,
    scale_range: Vec2f,

    pub fn deinit(self: *Prototype, alloc: Allocator) void {
        for (self.materials) |m| {
            alloc.free(m);
        }

        alloc.free(self.materials);
        alloc.free(self.shape_file);
        alloc.free(self.shape_type);
    }
};

pub const Instance = struct {
    prototype: u32,
    transformation: Mat4x4,
};

pub const Project = struct {
    const Particles = struct {
        num_particles: u32 = 0,
        radius: f32 = 0.001,
        frame: u32 = 0,
    };

    scene_filename: []u8 = &.{},

    mount_folder: []u8 = &.{},

    materials: List(u8) = .empty,

    prototypes: []Prototype = &.{},

    prototype_distribution: Distribution1D = .{},

    depth_offset_range: Vec2f = @splat(0.0),

    density: f32 = 1.0,

    align_to_normal: bool = true,
    tileable: bool = false,
    triplanar: bool = false,

    particles: Particles = .{},

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.prototype_distribution.deinit(alloc);

        for (self.prototypes) |*p| {
            p.deinit(alloc);
        }

        alloc.free(self.prototypes);
        self.materials.deinit(alloc);
        alloc.free(self.mount_folder);
        alloc.free(self.scene_filename);
    }
};
