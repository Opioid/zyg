const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;

pub fn cubicBezierBounds(cp: [4]Vec4f) AABB {
    var bounds = AABB.init(math.min4(cp[0], cp[1]), math.max4(cp[0], cp[1]));
    bounds.mergeAssign(AABB.init(math.min4(cp[2], cp[3]), math.max4(cp[2], cp[3])));
    return bounds;
}
