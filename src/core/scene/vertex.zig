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

pub const Pool = struct {
    const Num_vertices = 1;

    buffer: [2 * Num_vertices]Vertex,

    current_id: u32 = undefined,
    current_end: u32 = undefined,
    next_id: u32 = undefined,
    next_end: u32 = undefined,

    pub fn empty(self: Pool) bool {
        return self.current_id == self.current_end;
    }

    pub fn start(self: *Pool, vertex: Vertex) void {
        self.buffer[0] = vertex;
        self.current_id = 0;
        self.current_end = 1;
        self.next_id = Num_vertices;
        self.next_end = Num_vertices;
    }

    pub fn consume(self: *Pool) []Vertex {
        const id = self.current_id;
        const end = self.current_end;
        self.current_id = end;
        return self.buffer[id..end];
    }

    pub fn push(self: *Pool, vertex: Vertex) void {
        self.buffer[self.next_end] = vertex;
        self.next_end += 1;
    }

    pub fn cycle(self: *Pool) void {
        self.current_id = self.next_id;
        self.current_end = self.next_end;

        const next_id: u32 = if (Num_vertices == self.next_id) 0 else Num_vertices;
        self.next_id = next_id;
        self.next_end = next_id;
    }
};
