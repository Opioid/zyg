const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const scn = @import("../constants.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const InfiniteSphere = struct {
    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        if (ray.maxT() < scn.Ray_max_t) {
            return false;
        }

        const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(ray.direction));

        isec.uv.v[0] = std.math.atan2(f32, xyz[0], xyz[2]) * (math.pi_inv * 0.5) + 0.5;
        isec.uv.v[1] = std.math.acos(xyz[1]) * math.pi_inv;

        //  std.debug.print("{}\n", .{isec.uv});

        isec.p = ray.point(scn.Ray_max_t);

        const n = -ray.direction;
        isec.geo_n = n;

        // This is nonsense
        isec.t = trafo.rotation.r[0];
        isec.b = trafo.rotation.r[1];
        isec.n = n;
        isec.part = 0;
        isec.primitive = 0;

        ray.setMaxT(scn.Ray_max_t);

        return true;
    }
};
