usingnamespace @import("base").math;

pub const Composed_transformation = struct {
    world_to_object: Mat4x4 = undefined,
    rotation: Mat3x3 = undefined,
    position: Vec4f = undefined,

    const Self = @This();

    pub fn prepare(self: *Self, t: Transformation) void {
        self.rotation = quaternion.initMat3x3(t.rotation);

        self.rotation.setElem(0, 3, t.scale.v[0]);
        self.rotation.setElem(1, 3, t.scale.v[1]);
        self.rotation.setElem(2, 3, t.scale.v[2]);

        self.position = t.position;
    }

    pub fn setPosition(self: *Self, p: Vec4f) void {
        self.position = p;

        self.world_to_object = self.objectToWorld().affineInverted();
    }

    pub fn scaleX(self: Self) f32 {
        return self.rotation.m(0, 3);
    }

    pub fn scaleY(self: Self) f32 {
        return self.rotation.m(1, 3);
    }

    pub fn objectToWorld(self: Self) Mat4x4 {
        const scale = Vec4f.init3(
            self.rotation.m(0, 3),
            self.rotation.m(1, 3),
            self.rotation.m(2, 3),
        );

        return Mat4x4.compose(self.rotation, scale, self.position);
    }

    pub fn objectToWorldVector(self: Self, v: Vec4f) Vec4f {
        const s = Vec4f.init3(
            self.rotation.m(0, 3),
            self.rotation.m(1, 3),
            self.rotation.m(2, 3),
        );

        const a = self.rotation.r[0].mulScalar3(s.v[0]);
        const b = self.rotation.r[1].mulScalar3(s.v[1]);
        const c = self.rotation.r[2].mulScalar3(s.v[2]);

        return Vec4f.init3(
            (v.v[0] * a.v[0] + v.v[1] * b.v[0] + v.v[2] * c.v[0]),
            (v.v[0] * a.v[1] + v.v[1] * b.v[1] + v.v[2] * c.v[1]),
            (v.v[0] * a.v[2] + v.v[1] * b.v[2] + v.v[2] * c.v[2]),
        );
    }

    pub fn objectToWorldPoint(self: Self, v: Vec4f) Vec4f {
        return self.objectToWorldVector(v).add3(self.position);
    }
};
