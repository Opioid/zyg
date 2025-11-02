const Fragment = @import("intersection.zig").Fragment;

const math = @import("base").math;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

pub const Probe = struct {
    pub const Depth = struct {
        surface: u16 = 0,
        volume: u16 = 0,

        pub fn total(self: Depth) u32 {
            return self.surface + self.volume;
        }

        pub fn increment(self: *Depth, frag: *const Fragment) void {
            if (frag.subsurface()) {
                self.volume += 1;
            } else {
                self.surface += 1;
            }
        }
    };

    ray: Ray,

    depth: Depth,
    wavelength: f32,
    time: u64,

    pub fn init(ray: Ray, time: u64) Probe {
        return .{
            .ray = ray,
            .depth = .{},
            .wavelength = 0.0,
            .time = time,
        };
    }

    pub fn clone(self: Probe, ray: Ray) Probe {
        return .{
            .ray = ray,
            .depth = self.depth,
            .wavelength = self.wavelength,
            .time = self.time,
        };
    }
};
