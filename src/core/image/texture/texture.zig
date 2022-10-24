const Null = @import("../../resource/cache.zig").Null;
const Description = @import("../typed_image.zig").Description;
const Scene = @import("../../scene/scene.zig").Scene;
const enc = @import("encoding.zig");

const base = @import("base");
const math = base.math;
const spectrum = base.spectrum;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Vec4i = math.Vec4i;

pub const Texture = struct {
    pub const Type = enum {
        Byte1_unorm,
        Byte2_unorm,
        Byte2_snorm,
        Byte3_sRGB,
        Half3,
        Half4,
        Float1,
        Float1Sparse,
        Float2,
        Float3,
        Float4,
    };

    type: Type = undefined,
    image: u32 = Null,
    scale: Vec2f = undefined,

    pub fn equal(self: Texture, other: Texture) bool {
        return self.type == other.type and self.image == other.image and self.image == other.image;
    }

    pub fn valid(self: Texture) bool {
        return self.image != Null;
    }

    pub fn numChannels(self: Texture) u32 {
        if (Null == self.image) {
            return 0;
        }

        return switch (self.type) {
            .Byte1_unorm, .Float1, .Float1Sparse => 1,
            .Byte2_unorm, .Byte2_snorm, .Float2 => 2,
            .Byte3_sRGB, .Half3, .Float3 => 3,
            .Half4, .Float4 => 4,
        };
    }

    pub fn get2D_1(self: Texture, x: i32, y: i32, scene: *const Scene) f32 {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte1_unorm => {
                const value = image.Byte1.get2D(x, y);
                return enc.cachedUnormToFloat(value);
            },
            .Float1 => image.Float1.get2D(x, y),
            else => 0.0,
        };
    }

    pub fn gather2D_1(self: Texture, xy_xy1: Vec4i, scene: *const Scene) [4]f32 {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte1_unorm => {
                const values = image.Byte1.gather2D(xy_xy1);
                return .{
                    enc.cachedUnormToFloat(values[0]),
                    enc.cachedUnormToFloat(values[1]),
                    enc.cachedUnormToFloat(values[2]),
                    enc.cachedUnormToFloat(values[3]),
                };
            },
            .Float1 => image.Float1.gather2D(xy_xy1),
            else => .{ 0.0, 0.0, 0.0, 0.0 },
        };
    }

    pub fn get2D_2(self: Texture, x: i32, y: i32, scene: *const Scene) Vec2f {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte2_unorm => {
                const value = image.Byte2.get2D(x, y);
                return enc.cachedUnormToFloat2(value);
            },
            .Byte2_snorm => {
                const value = image.Byte2.get2D(x, y);
                return enc.cachedSnormToFloat2(value);
            },
            .Float2 => image.Float2.get2D(x, y),
            else => @splat(2, @as(f32, 0.0)),
        };
    }

    pub fn gather2D_2(self: Texture, xy_xy1: Vec4i, scene: *const Scene) [4]Vec2f {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte2_unorm => {
                const values = image.Byte2.gather2D(xy_xy1);
                return .{
                    enc.cachedUnormToFloat2(values[0]),
                    enc.cachedUnormToFloat2(values[1]),
                    enc.cachedUnormToFloat2(values[2]),
                    enc.cachedUnormToFloat2(values[3]),
                };
            },
            .Byte2_snorm => {
                const values = image.Byte2.gather2D(xy_xy1);
                return .{
                    enc.cachedSnormToFloat2(values[0]),
                    enc.cachedSnormToFloat2(values[1]),
                    enc.cachedSnormToFloat2(values[2]),
                    enc.cachedSnormToFloat2(values[3]),
                };
            },
            .Float2 => image.Float2.gather2D(xy_xy1),
            else => .{
                @splat(2, @as(f32, 0.0)),
                @splat(2, @as(f32, 0.0)),
                @splat(2, @as(f32, 0.0)),
                @splat(2, @as(f32, 0.0)),
            },
        };
    }

    pub fn get2D_3(self: Texture, x: i32, y: i32, scene: *const Scene) Vec4f {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte1_unorm => {
                const value = image.Byte1.get2D(x, y);
                return .{ enc.cachedUnormToFloat(value), 0.0, 0.0, 0.0 };
            },
            .Byte3_sRGB => {
                const value = image.Byte3.get2D(x, y);
                return spectrum.sRGBtoAP1(enc.cachedSrgbToFloat3(value));
            },
            .Half3 => {
                const value = image.Half3.get2D(x, y);
                return .{
                    @floatCast(f32, value.v[0]),
                    @floatCast(f32, value.v[1]),
                    @floatCast(f32, value.v[2]),
                    0.0,
                };
            },
            .Float3 => {
                const value = image.Float3.get2D(x, y);
                return .{ value.v[0], value.v[1], value.v[2], 0.0 };
            },
            else => @splat(4, @as(f32, 0.0)),
        };
    }

    pub fn gather2D_3(self: Texture, xy_xy1: Vec4i, scene: *const Scene) [4]Vec4f {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte1_unorm => {
                const values = image.Byte1.gather2D(xy_xy1);
                return .{
                    .{ enc.cachedUnormToFloat(values[0]), 0.0, 0.0, 0.0 },
                    .{ enc.cachedUnormToFloat(values[1]), 0.0, 0.0, 0.0 },
                    .{ enc.cachedUnormToFloat(values[2]), 0.0, 0.0, 0.0 },
                    .{ enc.cachedUnormToFloat(values[3]), 0.0, 0.0, 0.0 },
                };
            },
            .Byte3_sRGB => {
                const values = image.Byte3.gather2D(xy_xy1);
                return .{
                    spectrum.sRGBtoAP1(enc.cachedSrgbToFloat3(values[0])),
                    spectrum.sRGBtoAP1(enc.cachedSrgbToFloat3(values[1])),
                    spectrum.sRGBtoAP1(enc.cachedSrgbToFloat3(values[2])),
                    spectrum.sRGBtoAP1(enc.cachedSrgbToFloat3(values[3])),
                };
            },
            .Half3 => {
                const values = image.Half3.gather2D(xy_xy1);
                return .{
                    .{
                        @floatCast(f32, values[0].v[0]),
                        @floatCast(f32, values[0].v[1]),
                        @floatCast(f32, values[0].v[2]),
                        0.0,
                    },
                    .{
                        @floatCast(f32, values[1].v[0]),
                        @floatCast(f32, values[1].v[1]),
                        @floatCast(f32, values[1].v[2]),
                        0.0,
                    },
                    .{
                        @floatCast(f32, values[2].v[0]),
                        @floatCast(f32, values[2].v[1]),
                        @floatCast(f32, values[2].v[2]),
                        0.0,
                    },
                    .{
                        @floatCast(f32, values[3].v[0]),
                        @floatCast(f32, values[3].v[1]),
                        @floatCast(f32, values[3].v[2]),
                        0.0,
                    },
                };
            },
            .Float3 => {
                const values = image.Float3.gather2D(xy_xy1);
                return .{
                    .{ values[0].v[0], values[0].v[1], values[0].v[2], 0.0 },
                    .{ values[1].v[0], values[1].v[1], values[1].v[2], 0.0 },
                    .{ values[2].v[0], values[2].v[1], values[2].v[2], 0.0 },
                    .{ values[3].v[0], values[3].v[1], values[3].v[2], 0.0 },
                };
            },
            else => .{
                @splat(4, @as(f32, 0.0)),
                @splat(4, @as(f32, 0.0)),
                @splat(4, @as(f32, 0.0)),
                @splat(4, @as(f32, 0.0)),
            },
        };
    }

    pub fn get2D_4(self: Texture, x: i32, y: i32, scene: *const Scene) Vec4f {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte1_unorm => {
                const value = image.Byte1.get2D(x, y);
                return .{ enc.cachedUnormToFloat(value), 0.0, 0.0, 1.0 };
            },
            .Byte3_sRGB => {
                const value = image.Byte3.get2D(x, y);
                const ap = spectrum.sRGBtoAP1(enc.cachedSrgbToFloat3(value));
                return .{ ap[0], ap[1], ap[2], 1.0 };
            },
            .Half3 => {
                const value = image.Half3.get2D(x, y);
                return .{
                    @floatCast(f32, value.v[0]),
                    @floatCast(f32, value.v[1]),
                    @floatCast(f32, value.v[2]),
                    1.0,
                };
            },
            .Float3 => {
                const value = image.Float3.get2D(x, y);
                return .{ value.v[0], value.v[1], value.v[2], 1.0 };
            },
            .Half4 => {
                const value = image.Half4.get2D(x, y);
                return .{
                    @floatCast(f32, value.v[0]),
                    @floatCast(f32, value.v[1]),
                    @floatCast(f32, value.v[2]),
                    @floatCast(f32, value.v[3]),
                };
            },
            .Float4 => {
                const value = image.Float4.get2D(x, y);
                return .{ value.v[0], value.v[1], value.v[2], value.v[3] };
            },
            else => .{ 0.0, 0.0, 0.0, 1.0 },
        };
    }

    pub fn get3D_1(self: Texture, x: i32, y: i32, z: i32, scene: *const Scene) f32 {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte1_unorm => {
                const value = image.Byte1.get3D(x, y, z);
                return enc.cachedUnormToFloat(value);
            },
            .Float1 => image.Float1.get3D(x, y, z),
            .Float1Sparse => image.Float1Sparse.get3D(x, y, z),
            .Float2 => image.Float2.get3D(x, y, z)[0],
            else => 0.0,
        };
    }

    pub fn gather3D_1(self: Texture, xyz: Vec4i, xyz1: Vec4i, scene: *const Scene) [8]f32 {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte1_unorm => {
                const values = image.Byte1.gather3D(xyz, xyz1);
                return .{
                    enc.cachedUnormToFloat(values[0]),
                    enc.cachedUnormToFloat(values[1]),
                    enc.cachedUnormToFloat(values[2]),
                    enc.cachedUnormToFloat(values[3]),
                    enc.cachedUnormToFloat(values[4]),
                    enc.cachedUnormToFloat(values[5]),
                    enc.cachedUnormToFloat(values[6]),
                    enc.cachedUnormToFloat(values[7]),
                };
            },
            .Float1 => image.Float1.gather3D(xyz, xyz1),
            .Float1Sparse => image.Float1Sparse.gather3D(xyz, xyz1),
            .Float2 => {
                const values = image.Float2.gather3D(xyz, xyz1);
                return .{
                    values[0][0],
                    values[1][0],
                    values[2][0],
                    values[3][0],
                    values[4][0],
                    values[5][0],
                    values[6][0],
                    values[7][0],
                };
            },
            else => [_]f32{0.0} ** 8,
        };
    }

    pub fn get3D_2(self: Texture, x: i32, y: i32, z: i32, scene: *const Scene) Vec2f {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Float2 => image.Float2.get3D(x, y, z),
            else => @splat(2.0, @as(f32, 0.0)),
        };
    }

    pub fn gather3D_2(self: Texture, xyz: Vec4i, xyz1: Vec4i, scene: *const Scene) [8]Vec2f {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Float2 => image.Float2.gather3D(xyz, xyz1),
            else => [_]Vec2f{@splat(2, @as(f32, 0.0))} ** 8,
        };
    }

    pub fn description(self: Texture, scene: *const Scene) Description {
        return scene.image(self.image).description();
    }

    pub fn average_3(self: Texture, scene: *const Scene) Vec4f {
        var average = @splat(4, @as(f32, 0.0));

        const d = self.description(scene).dimensions;
        var y: i32 = 0;
        while (y < d[1]) : (y += 1) {
            var x: i32 = 0;
            while (x < d[0]) : (x += 1) {
                average += self.get2D_3(x, y, scene);
            }
        }

        const area = @intToFloat(f32, d[0]) * @intToFloat(f32, d[1]);
        return average / @splat(4, area);
    }
};
