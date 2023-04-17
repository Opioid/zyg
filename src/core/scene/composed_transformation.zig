const math = @import("base").math;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;
const quaternion = math.quaternion;
const Transformation = math.Transformation;
const Ray = math.Ray;

pub const ComposedTransformation = struct {
    rotation: Mat3x3 = undefined,
    position: Vec4f = undefined,

    const Self = @This();

    pub fn init(t: Transformation) Self {
        var self = Self{};

        self.rotation = quaternion.toMat3x3(t.rotation);

        self.rotation.r[0][3] = t.scale[0];
        self.rotation.r[1][3] = t.scale[1];
        self.rotation.r[2][3] = t.scale[2];

        self.position = t.position;

        return self;
    }

    pub fn translate(self: *Self, v: Vec4f) void {
        self.position += v;
    }

    pub fn scaleX(self: Self) f32 {
        return self.rotation.r[0][3];
    }

    pub fn scaleY(self: Self) f32 {
        return self.rotation.r[1][3];
    }

    pub fn scaleZ(self: Self) f32 {
        return self.rotation.r[2][3];
    }

    pub fn scale(self: Self) Vec4f {
        return .{ self.rotation.r[0][3], self.rotation.r[1][3], self.rotation.r[2][3], 1.0 };
    }

    pub fn objectToWorld(self: Self) Mat4x4 {
        return Mat4x4.compose(self.rotation, self.scale(), self.position);
    }

    pub fn objectToWorldVector(self: Self, v: Vec4f) Vec4f {
        const s = self.scale();

        const a = self.rotation.r[0] * @splat(4, s[0]);
        const b = self.rotation.r[1] * @splat(4, s[1]);
        const c = self.rotation.r[2] * @splat(4, s[2]);

        // return Vec4f{
        //     v[0] * a[0] + v[1] * b[0] + v[2] * c[0],
        //     v[0] * a[1] + v[1] * b[1] + v[2] * c[1],
        //     v[0] * a[2] + v[1] * b[2] + v[2] * c[2],
        //     0.0,
        // };

        var result = @splat(4, v[0]); // @shuffle(f32, v, v, [4]i32{ 0, 0, 0, 0 });
        result = result * a;
        var temp = @splat(4, v[1]); // @shuffle(f32, v, v, [4]i32{ 1, 1, 1, 1 });
        temp = temp * b;
        result = result + temp;
        temp = @splat(4, v[2]); // @shuffle(f32, v, v, [4]i32{ 2, 2, 2, 2 });
        temp = temp * c;
        return result + temp;
    }

    pub fn objectToWorldPoint(self: Self, p: Vec4f) Vec4f {
        return self.objectToWorldVector(p) + self.position;
    }

    pub fn objectToWorldNormal(self: Self, n: Vec4f) Vec4f {
        return self.rotation.transformVector(n);
    }

    pub fn worldToObjectVector(self: Self, v: Vec4f) Vec4f {
        const o = self.rotation.transformVectorTransposed(v);
        const s = self.scale();

        return o / s;
    }

    pub fn worldToObjectPoint(self: Self, p: Vec4f) Vec4f {
        return self.worldToObjectVector(p - self.position);
    }

    pub fn worldToObjectNormal(self: Self, n: Vec4f) Vec4f {
        return self.rotation.transformVectorTransposed(n);
    }

    pub fn worldToObjectRay(self: Self, ray: Ray) Ray {
        return Ray.init(
            self.worldToObjectPoint(ray.origin),
            self.worldToObjectVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );
    }
};
