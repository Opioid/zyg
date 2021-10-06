const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Ray = struct {
    ray: math.Ray,

    depth: u32,

    time: u64,

    pub fn init(
        origin: Vec4f,
        direction: Vec4f,
        min_t: f32,
        max_t: f32,
        depth: u32,
        time: u64,
    ) Ray {
        return Ray{
            .ray = math.Ray.init(origin, direction, min_t, max_t),
            .depth = depth,
            .time = time,
        };
    }
};
