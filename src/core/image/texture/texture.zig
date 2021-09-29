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
    };

    type: Type = undefined,
    image: u32 = Null,

    pub fn isValid(self: Texture) bool {
        return self.image != Null;
    }

    pub fn numChannels(self: Texture) u32 {
        const nc: u32 = switch (self.type) {
            .Byte1_unorm => 1,
            .Byte2_unorm, .Byte2_snorm => 2,
            .Byte3_sRGB, .Half3 => 3,
        };

        return if (Null == self.image) 0 else nc;
    }

    pub fn get2D_1(self: Texture, x: i32, y: i32, scene: Scene) f32 {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte1_unorm => {
                const value = image.Byte1.get2D(x, y);
                return enc.cachedUnormToFloat(value);
            },
            else => 0.0,
        };
    }

    pub fn gather2D_1(self: Texture, xy_xy1: Vec4i, scene: Scene) [4]f32 {
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
            else => .{ 0.0, 0.0, 0.0, 0.0 },
        };
    }

    pub fn get2D_2(self: Texture, x: i32, y: i32, scene: Scene) Vec2f {
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
            else => @splat(2, @as(f32, 0.0)),
        };
    }

    pub fn gather2D_2(self: Texture, xy_xy1: Vec4i, scene: Scene) [4]Vec2f {
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
            else => .{
                @splat(2, @as(f32, 0.0)),
                @splat(2, @as(f32, 0.0)),
                @splat(2, @as(f32, 0.0)),
                @splat(2, @as(f32, 0.0)),
            },
        };
    }

    pub fn get2D_3(self: Texture, x: i32, y: i32, scene: Scene) Vec4f {
        const image = scene.image(self.image);

        return switch (self.type) {
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
            else => @splat(4, @as(f32, 0.0)),
        };
    }

    pub fn gather2D_3(self: Texture, xy_xy1: Vec4i, scene: Scene) [4]Vec4f {
        const image = scene.image(self.image);

        return switch (self.type) {
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
            else => .{
                @splat(4, @as(f32, 0.0)),
                @splat(4, @as(f32, 0.0)),
                @splat(4, @as(f32, 0.0)),
                @splat(4, @as(f32, 0.0)),
            },
        };
    }

    pub fn description(self: Texture, scene: Scene) Description {
        return scene.image(self.image).description();
    }

    pub fn average_3(self: Texture, scene: Scene) Vec4f {
        var average = @splat(4, @as(f32, 0.0));

        const d = self.description(scene).dimensions;
        var y: i32 = 0;
        while (y < d.v[1]) : (y += 1) {
            var x: i32 = 0;
            while (x < d.v[0]) : (x += 1) {
                average += self.get2D_3(x, y, scene);
            }
        }

        const area = @intToFloat(f32, d.v[0]) * @intToFloat(f32, d.v[1]);
        return average / @splat(4, area);
    }
};
