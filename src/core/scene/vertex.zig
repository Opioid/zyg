const math = @import("base").math;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

pub const Vertex = struct {
    ray: Ray,

    depth: u32,
    wavelength: f32,
    time: u64,

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
        };
    }
};

pub const RayDif = struct {
    x_origin: Vec4f,
    x_direction: Vec4f,
    y_origin: Vec4f,
    y_direction: Vec4f,
};
