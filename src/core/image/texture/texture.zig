const Null = @import("../../resource/cache.zig").Null;
const Description = @import("../typed_image.zig").Description;
const Scene = @import("../../scene/scene.zig").Scene;
const enc = @import("encoding.zig");

const base = @import("base");
const math = base.math;
const spectrum = base.spectrum;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const Vec4i = math.Vec4i;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Texture = struct {
    pub const TexCoordMode = enum {
        UV0,
        Triplanar,
        ObjectPos,
    };

    pub const Type = enum {
        Uniform,
        Procedural,
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

    const Image = extern struct {
        id: u32,
        scale: [2]f32,
    };

    const Procedural = extern struct {
        id: u32,
        data: u32,
    };

    const Data = extern union {
        uniform: Pack3f,
        procedural: Procedural,
        image: Image,
    };

    type: Type = .Uniform,
    uv_set: TexCoordMode = undefined,
    data: Data = undefined,

    pub fn initImage(class: Type, image_id: u32, uv_set: TexCoordMode, scale: Vec2f) Texture {
        return .{ .type = class, .uv_set = uv_set, .data = .{ .image = .{ .id = image_id, .scale = scale } } };
    }

    pub fn initUniform1(v: f32) Texture {
        return .{ .type = .Uniform, .data = .{ .uniform = Pack3f.init1(v) } };
    }

    pub fn initUniform2(v: Vec2f) Texture {
        return .{ .type = .Uniform, .data = .{ .uniform = Pack3f.init3(v[0], v[1], 0.0) } };
    }

    pub fn initUniform3(v: Vec4f) Texture {
        return .{ .type = .Uniform, .data = .{ .uniform = Pack3f.init3(v[0], v[1], v[2]) } };
    }

    pub fn initProcedural(id: u32, data: u32, uv_set: TexCoordMode) Texture {
        return .{ .type = .Procedural, .uv_set = uv_set, .data = .{ .procedural = .{ .id = id, .data = data } } };
    }

    pub fn equal(self: Texture, other: Texture) bool {
        return std.mem.eql(u8, std.mem.asBytes(&self), std.mem.asBytes(&other));
    }

    const Error = error{
        IncompatibleCast,
    };

    pub fn cast(self: Texture, target: Type) !Texture {
        if (.Uniform == self.type) {
            return Error.IncompatibleCast;
        }

        const other = Texture.initImage(target, self.data.image.id, self.uv_set, self.data.image.scale);

        if (self.numChannels() != other.numChannels() or self.bytesPerChannel() != other.bytesPerChannel()) {
            return Error.IncompatibleCast;
        }

        return other;
    }

    pub fn isUniform(self: Texture) bool {
        return .Uniform == self.type;
    }

    pub fn isProcedural(self: Texture) bool {
        return .Procedural == self.type;
    }

    pub fn isImage(self: Texture) bool {
        return switch (self.type) {
            .Uniform, .Procedural => false,
            else => true,
        };
    }

    pub fn numChannels(self: Texture) u32 {
        return switch (self.type) {
            .Uniform, .Procedural => 0,
            .Byte1_unorm, .Half1, .Float1, .Float1Sparse => 1,
            .Byte2_unorm, .Byte2_snorm, .Float2 => 2,
            .Byte3_sRGB, .Byte3_snorm, .Half3, .Float3 => 3,
            .Byte4_sRGB, .Half4, .Float4 => 4,
        };
    }

    pub fn bytesPerChannel(self: Texture) u32 {
        return switch (self.type) {
            .Uniform, .Procedural => 0,
            .Byte1_unorm, .Byte2_unorm, .Byte2_snorm, .Byte3_sRGB, .Byte3_snorm, .Byte4_sRGB => 1,
            .Half1, .Half3, .Half4 => 2,
            else => 4,
        };
    }

    pub fn uniform1(self: Texture) f32 {
        const v = self.data.uniform;
        return v.v[0];
    }

    pub fn uniform2(self: Texture) Vec2f {
        const v = self.data.uniform;
        return .{ v.v[0], v.v[1] };
    }

    pub fn uniform3(self: Texture) Vec4f {
        const v = self.data.uniform;
        return .{ v.v[0], v.v[1], v.v[2], 0.0 };
    }

    pub fn image2D_1(self: Texture, x: i32, y: i32, scene: *const Scene) f32 {
        const image = scene.image(self.data.image.id);

        return switch (self.type) {
            .Byte1_unorm => enc.cachedUnormToFloat(image.Byte1.get2D(x, y)),
            .Half1 => @floatCast(image.Half1.get2D(x, y)),
            .Float1 => image.Float1.get2D(x, y),
            else => 0.0,
        };
    }

    pub fn image2D_2(self: Texture, x: i32, y: i32, scene: *const Scene) Vec2f {
        const image = scene.image(self.data.image.id);

        return switch (self.type) {
            .Byte2_unorm => enc.cachedUnormToFloat2(image.Byte2.get2D(x, y)),
            .Byte2_snorm => enc.cachedSnormToFloat2(image.Byte2.get2D(x, y)),
            .Float2 => image.Float2.get2D(x, y),
            else => @splat(0.0),
        };
    }

    pub fn image2D_3(self: Texture, x: i32, y: i32, scene: *const Scene) Vec4f {
        const image = scene.image(self.data.image.id);

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
        const image = scene.image(self.data.image.id);

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

    pub fn image3D_1(self: Texture, x: i32, y: i32, z: i32, scene: *const Scene) f32 {
        const image = scene.image(self.data.image.id);

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

    pub fn image3D_2(self: Texture, x: i32, y: i32, z: i32, scene: *const Scene) Vec2f {
        const image = scene.image(self.data.image.id);

        return switch (self.type) {
            .Float2 => image.Float2.get3D(x, y, z),
            else => @splat(0.0),
        };
    }

    pub fn description(self: Texture, scene: *const Scene) Description {
        return scene.image(self.data.image.id).description();
    }

    pub fn average_3(self: Texture, scene: *const Scene) Vec4f {
        var average: Vec4f = @splat(0.0);

        const d = self.description(scene).dimensions;
        var y: i32 = 0;
        while (y < d[1]) : (y += 1) {
            var x: i32 = 0;
            while (x < d[0]) : (x += 1) {
                average += self.image2D_3(x, y, scene);
            }
        }

        const area = @as(f32, @floatFromInt(d[0])) * @as(f32, @floatFromInt(d[1]));
        return average / @as(Vec4f, @splat(area));
    }
};
