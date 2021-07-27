const shape = @import("../shape/intersection.zig");
const Vec4f = @import("base").math.Vec4f;
usingnamespace @import("../ray_offset.zig");

pub const Intersection = struct {
    geo: shape.Intersection = undefined,

    prop: u32 = undefined,

    pub fn sameHemisphere(self: Intersection, v: Vec4f) bool {
        return self.geo.geo_n.dot3(v) > 0.0;
    }

    pub fn offsetP(self: Intersection, n: Vec4f) Vec4f {
        const p = self.geo.p;

        return offsetRay(p, n);
    }
};
