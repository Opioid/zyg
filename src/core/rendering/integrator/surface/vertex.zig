const Ray = @import("../../../scene/ray.zig").Ray;

pub const Vertex = struct {
    const PathState = packed struct {
        primary_ray: bool = true,
        treat_as_singular: bool = true,
        is_translucent: bool = false,
        split_photon: bool = false,
        direct: bool = true,
        from_subsurface: bool = false,
    };

    ray: Ray,

    state: PathState = .{},
};
