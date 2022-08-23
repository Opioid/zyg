const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Ray = struct {
    ray: math.Ray,

    depth: u32,
    wavelength: f32,
    time: u64,

    pub inline fn init(
        origin: Vec4f,
        direction: Vec4f,
        min_t: f32,
        max_t: f32,
        depth: u32,
        wavelength: f32,
        time: u64,
    ) Ray {
        return .{
            .ray = math.Ray.init(origin, direction, min_t, max_t),
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
