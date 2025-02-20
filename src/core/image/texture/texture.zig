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

const std = @import("std");

pub const Texture = struct {
    pub const Type = enum {
        Byte1_unorm,
        Byte2_unorm,
        Byte2_snorm,
        Byte3_sRGB,
        Byte3_snorm,
        Byte4_sRGB,
        Half1,
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
        return std.mem.eql(u8, std.mem.asBytes(&self), std.mem.asBytes(&other));
    }

    const Error = error{
        IncompatibleCast,
    };

    pub fn cast(self: Texture, target: Type) !Texture {
        const other = Texture{ .type = target, .image = self.image, .scale = self.scale };

        if (self.numChannels() != other.numChannels() or self.bytesPerChannel() != other.bytesPerChannel()) {
            return Error.IncompatibleCast;
        }

        return other;
    }

    pub fn valid(self: Texture) bool {
        return self.image != Null;
    }

    pub fn numChannels(self: Texture) u32 {
        if (Null == self.image) {
            return 0;
        }

        return switch (self.type) {
            .Byte1_unorm, .Half1, .Float1, .Float1Sparse => 1,
            .Byte2_unorm, .Byte2_snorm, .Float2 => 2,
            .Byte3_sRGB, .Byte3_snorm, .Half3, .Float3 => 3,
            .Byte4_sRGB, .Half4, .Float4 => 4,
        };
    }

    pub fn bytesPerChannel(self: Texture) u32 {
        if (Null == self.image) {
            return 0;
        }

        return switch (self.type) {
            .Byte1_unorm, .Byte2_unorm, .Byte2_snorm, .Byte3_sRGB, .Byte3_snorm, .Byte4_sRGB => 1,
            .Half1, .Half3, .Half4 => 2,
            else => 4,
        };
    }

    pub fn get2D_1(self: Texture, x: i32, y: i32, scene: *const Scene) f32 {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte1_unorm => enc.cachedUnormToFloat(image.Byte1.get2D(x, y)),
            .Half1 => @floatCast(image.Half1.get2D(x, y)),
            .Float1 => image.Float1.get2D(x, y),
            else => 0.0,
        };
    }

    pub fn get2D_2(self: Texture, x: i32, y: i32, scene: *const Scene) Vec2f {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Byte2_unorm => enc.cachedUnormToFloat2(image.Byte2.get2D(x, y)),
            .Byte2_snorm => enc.cachedSnormToFloat2(image.Byte2.get2D(x, y)),
            .Float2 => image.Float2.get2D(x, y),
            else => @splat(0.0),
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
            .Byte3_snorm => {
                const value = image.Byte3.get2D(x, y);
                return enc.cachedSnormToFloat3(value);
            },
            .Half3 => {
                const value = image.Half3.get2D(x, y);
                return .{
                    @floatCast(value.v[0]),
                    @floatCast(value.v[1]),
                    @floatCast(value.v[2]),
                    0.0,
                };
            },
            .Float3 => {
                const value = image.Float3.get2D(x, y);
                return .{ value.v[0], value.v[1], value.v[2], 0.0 };
            },
            else => @splat(0.0),
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
                    @floatCast(value.v[0]),
                    @floatCast(value.v[1]),
                    @floatCast(value.v[2]),
                    1.0,
                };
            },
            .Float3 => {
                const value = image.Float3.get2D(x, y);
                return .{ value.v[0], value.v[1], value.v[2], 1.0 };
            },
            .Byte4_sRGB => {
                const value = image.Byte4.get2D(x, y);
                const srgb = enc.cachedSrgbToFloat4(value);
                const ap = spectrum.sRGBtoAP1(.{ srgb[0], srgb[1], srgb[2], 0.0 });
                return .{ ap[0], ap[1], ap[2], srgb[3] };
            },
            .Half4 => {
                const value = image.Half4.get2D(x, y);
                return .{
                    @floatCast(value.v[0]),
                    @floatCast(value.v[1]),
                    @floatCast(value.v[2]),
                    @floatCast(value.v[3]),
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

    pub fn get3D_2(self: Texture, x: i32, y: i32, z: i32, scene: *const Scene) Vec2f {
        const image = scene.image(self.image);

        return switch (self.type) {
            .Float2 => image.Float2.get3D(x, y, z),
            else => @splat(0.0),
        };
    }

    pub fn description(self: Texture, scene: *const Scene) Description {
        return scene.image(self.image).description();
    }

    pub fn average_3(self: Texture, scene: *const Scene) Vec4f {
        var average: Vec4f = @splat(0.0);

        const d = self.description(scene).dimensions;
        var y: i32 = 0;
        while (y < d[1]) : (y += 1) {
            var x: i32 = 0;
            while (x < d[0]) : (x += 1) {
                average += self.get2D_3(x, y, scene);
            }
        }

        const area = @as(f32, @floatFromInt(d[0])) * @as(f32, @floatFromInt(d[1]));
        return average / @as(Vec4f, @splat(area));
    }
};
