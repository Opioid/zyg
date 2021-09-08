const Null = @import("../../resource/cache.zig").Null;
const Description = @import("../typed_image.zig").Description;
const Scene = @import("../../scene/scene.zig").Scene;

const base = @import("base");
usingnamespace base;
usingnamespace base.math;

pub const Texture = struct {
    pub const Type = enum {
        Byte3_sRGB,
    };

    type: Type = undefined,
    image: u32 = Null,

    pub fn isValid(self: Texture) bool {
        return self.image != Null;
    }

    pub fn get2D_3(self: Texture, x: i32, y: i32, scene: *const Scene) Vec4f {
        const image = scene.image(self.image);

        switch (self.type) {
            .Byte3_sRGB => {
                const value = image.Byte3.getXY(x, y);
                _ = value;
                return Vec4f.init3(0.9, 0.2, 0.1);
            },
        }
    }

    pub fn description(self: Texture, scene: *const Scene) Description {
        return scene.image(self.image).description();
    }
};
