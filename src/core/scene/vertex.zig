const Ray = @import("ray.zig").Ray;
const Intersection = @import("prop/intersection.zig").Intersection;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

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

    isec: Intersection,

    geo_n: Vec4f = @splat(4, @as(f32, 0.0)),
    wo1: Vec4f = @splat(4, @as(f32, 0.0)),

    state: PathState = .{},
};
