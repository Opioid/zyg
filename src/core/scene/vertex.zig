const math = @import("base").math;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

pub const Vertex = struct {
    pub const State = packed struct {
        primary_ray: bool = true,
        treat_as_singular: bool = true,
        is_translucent: bool = false,
        split_photon: bool = false,
        direct: bool = true,
        from_subsurface: bool = false,
        started_specular: bool = false,
    };

    ray: Ray,

    depth: u32,
    wavelength: f32,
    time: u64,
    state: State,

    pub fn init(
        origin: Vec4f,
        direction: Vec4f,
        min_t: f32,
        max_t: f32,
        depth: u32,
        wavelength: f32,
        time: u64,
    ) Vertex {
        return .{
            .ray = Ray.init(origin, direction, min_t, max_t),
            .depth = depth,
            .wavelength = wavelength,
            .time = time,
            .state = .{},
        };
    }

    pub fn initRay(ray: Ray, depth: u32, time: u64) Vertex {
        return .{
            .ray = ray,
            .depth = depth,
            .wavelength = 0.0,
            .time = time,
            .state = .{},
        };
    }
};

pub const RayDif = struct {
    x_origin: Vec4f,
    x_direction: Vec4f,
    y_origin: Vec4f,
    y_direction: Vec4f,
};
