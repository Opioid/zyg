const Null = @import("../../resource/cache.zig").Null;
const Description = @import("../typed_image.zig").Description;
const Scene = @import("../../scene/scene.zig").Scene;
const enc = @import("encoding.zig");
const base = @import("base");
const math = base.math;
const spectrum = base.spectrum;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Texture = struct {
    pub const Type = enum {
        Byte1_unorm,
        Byte2_snorm,
        Byte3_sRGB,
    };

    type: Type = undefined,
    image: u32 = Null,

    pub fn isValid(self: Texture) bool {
        return self.image != Null;
    }

    pub fn get2D_1(self: Texture, x: i32, y: i32, scene: *const Scene) f32 {
        const image = scene.image(self.image);

        switch (self.type) {
            .Byte1_unorm => {
                const value = image.Byte1.getXY(x, y);
                return enc.cachedUnormToFloat(value);
            },
            else => unreachable,
        }
    }

    pub fn get2D_2(self: Texture, x: i32, y: i32, scene: *const Scene) Vec2f {
        const image = scene.image(self.image);

        switch (self.type) {
            .Byte2_snorm => {
                const value = image.Byte2.getXY(x, y);
                return enc.cachedSnormToFloat2(value);
            },
            else => unreachable,
        }
    }

    pub fn get2D_3(self: Texture, x: i32, y: i32, scene: *const Scene) Vec4f {
        const image = scene.image(self.image);

        switch (self.type) {
            .Byte3_sRGB => {
                const value = image.Byte3.getXY(x, y);
                return spectrum.sRGBtoAP1(enc.cachedSrgbToFloat3(value));
            },
            else => unreachable,
        }
    }

    pub fn description(self: Texture, scene: *const Scene) Description {
        return scene.image(self.image).description();
    }
};
