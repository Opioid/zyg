const Indexed_data = @import("indexed_data.zig").Indexed_data;
const base = @import("base");
usingnamespace base;

//const Vec4f = base.math.Vec4f;
const Ray = base.math.Ray;

pub const Tree = struct {
    pub const Intersection = struct {
        u: f32 = undefined,
        v: f32 = undefined,
        index: u32 = 0xFFFFFFFF,
    };

    data: Indexed_data,

    pub fn intersect(self: Tree, ray: *Ray) ?Intersection {
        var isec: Intersection = .{};

        for (self.data.triangles) |_, i| {
            if (self.data.intersect(ray, i)) |hit| {
                isec.u = hit.u;
                isec.v = hit.v;
                isec.index = @intCast(u32, i);
            }
        }

        return if (0xFFFFFFFF != isec.index) isec else null;
    }

    pub fn intersectP(self: Tree, ray: Ray) bool {
        for (self.data.triangles) |_, i| {
            if (self.data.intersectP(ray, i)) {
                return true;
            }
        }

        return false;
    }
};
