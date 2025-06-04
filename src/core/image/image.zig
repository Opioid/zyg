const enc = @import("texture/encoding.zig");

const base = @import("base");
const math = base.math;
const Vec2b = math.Vec2b;
const Vec2f = math.Vec2f;
const Pack3b = math.Pack3b;
const Pack3h = math.Pack3h;
const Pack3f = math.Pack3f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Pack4b = math.Pack4b;
const Pack4h = math.Pack4h;
const Pack4f = math.Pack4f;
const spectrum = base.spectrum;
const baseenc = base.encoding;

const ti = @import("typed_image.zig");
pub const Description = ti.Description;
pub const Byte1 = ti.TypedImage(u8);
pub const Byte2 = ti.TypedImage(Vec2b);
pub const Byte3 = ti.TypedImage(Pack3b);
pub const Byte4 = ti.TypedImage(Pack4b);
pub const Half1 = ti.TypedImage(f16);
pub const Half3 = ti.TypedImage(Pack3h);
pub const Half4 = ti.TypedImage(Pack4h);
pub const Float1 = ti.TypedImage(f32);
pub const Float1Sparse = ti.TypedSparseImage(f32);
pub const Float2 = ti.TypedImage(Vec2f);
pub const Float3 = ti.TypedImage(Pack3f);
pub const Float4 = ti.TypedImage(Pack4f);
pub const testing = @import("test_image.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Swizzle = enum {
    X,
    Y,
    Z,
    W,
    XY,
    YX,
    YZ,
    XYZ,
    XYZW,

    pub fn numChannels(self: Swizzle) u32 {
        return switch (self) {
            .X, .Y, .Z, .W => 1,
            .XY, .YX, .YZ => 2,
            .XYZ => 3,
            .XYZW => 4,
        };
    }
};

pub const Image = union(enum) {
    Byte1: Byte1,
    Byte2: Byte2,
    Byte3: Byte3,
    Byte4: Byte4,
    Half1: Half1,
    Half3: Half3,
    Half4: Half4,
    Float1: Float1,
    Float1Sparse: Float1Sparse,
    Float2: Float2,
    Float3: Float3,
    Float4: Float4,

    pub fn deinit(self: *Image, alloc: Allocator) void {
        switch (self.*) {
            inline else => |*i| i.deinit(alloc),
        }
    }

    pub fn levels(self: Image) u32 {
        return switch (self) {
            .Float1Sparse => 1,
            inline else => |i| @truncate(i.dimensions.len),
        };
    }

    pub fn dimensions(self: Image) Vec4i {
        return switch (self) {
            .Float1Sparse => |i| i.dimensions,
            inline else => |i| i.dimensions[0],
        };
    }

    pub fn dimensionsLevel(self: Image, level: u32) Vec4i {
        return switch (self) {
            .Float1Sparse => |i| i.dimensions,
            inline else => |i| i.dimensions[level],
        };
    }

    pub fn calculalateMipChain(self: *Image) void {
        switch (self.*) {
            .Byte1 => |*image| {
                for (1..image.dimensions.len) |l| {
                    const dim = image.dimensions[l];

                    const il: u32 = @truncate(l);

                    var y: i32 = 0;
                    while (y < dim[1]) : (y += 1) {
                        var x: i32 = 0;
                        while (x < dim[0]) : (x += 1) {
                            const a = image.get2DLevel(il - 1, x * 2 + 0, y * 2 + 0);
                            const b = image.get2DLevel(il - 1, x * 2 + 1, y * 2 + 0);
                            const c = image.get2DLevel(il - 1, x * 2 + 0, y * 2 + 1);
                            const d = image.get2DLevel(il - 1, x * 2 + 1, y * 2 + 1);

                            const al = enc.cachedUnormToFloat(a);
                            const bl = enc.cachedUnormToFloat(b);
                            const cl = enc.cachedUnormToFloat(c);
                            const dl = enc.cachedUnormToFloat(d);

                            const average = 0.25 * (al + bl + cl + dl);

                            const byte: u8 = baseenc.floatToUnorm8(average);

                            image.set2D(il, x, y, byte);
                        }
                    }
                }
            },
            .Byte2 => |*image| {
                for (1..image.dimensions.len) |l| {
                    const dim = image.dimensions[l];

                    const il: u32 = @truncate(l);

                    var y: i32 = 0;
                    while (y < dim[1]) : (y += 1) {
                        var x: i32 = 0;
                        while (x < dim[0]) : (x += 1) {
                            const a = image.get2DLevel(il - 1, x * 2 + 0, y * 2 + 0);
                            const b = image.get2DLevel(il - 1, x * 2 + 1, y * 2 + 0);
                            const c = image.get2DLevel(il - 1, x * 2 + 0, y * 2 + 1);
                            const d = image.get2DLevel(il - 1, x * 2 + 1, y * 2 + 1);

                            // const al = enc.cachedUnormToFloat2(a);
                            // const bl = enc.cachedUnormToFloat2(b);
                            // const cl = enc.cachedUnormToFloat2(c);
                            // const dl = enc.cachedUnormToFloat2(d);

                            // const average = @as(Vec2f, @splat(0.25)) * (al + bl + cl + dl);

                            // const bytes = Vec2b{
                            //     baseenc.floatToUnorm8(average[0]),
                            //     baseenc.floatToUnorm8(average[1]),
                            // };

                            const anm = normalFromByte2(a);
                            const bnm = normalFromByte2(b);
                            const cnm = normalFromByte2(c);
                            const dnm = normalFromByte2(d);

                            const average = math.normalize3(@as(Vec4f, @splat(0.25)) * (anm + bnm + cnm + dnm));

                            const bytes = Vec2b{
                                baseenc.floatToSnorm8(average[0]),
                                baseenc.floatToSnorm8(average[1]),
                            };

                            image.set2D(il, x, y, bytes);
                        }
                    }
                }
            },
            .Byte3 => |*image| {
                for (1..image.dimensions.len) |l| {
                    const dim = image.dimensions[l];

                    const il: u32 = @truncate(l);

                    var y: i32 = 0;
                    while (y < dim[1]) : (y += 1) {
                        var x: i32 = 0;
                        while (x < dim[0]) : (x += 1) {
                            const a = image.get2DLevel(il - 1, x * 2 + 0, y * 2 + 0);
                            const b = image.get2DLevel(il - 1, x * 2 + 1, y * 2 + 0);
                            const c = image.get2DLevel(il - 1, x * 2 + 0, y * 2 + 1);
                            const d = image.get2DLevel(il - 1, x * 2 + 1, y * 2 + 1);

                            const al = enc.cachedSrgbToFloat3(a);
                            const bl = enc.cachedSrgbToFloat3(b);
                            const cl = enc.cachedSrgbToFloat3(c);
                            const dl = enc.cachedSrgbToFloat3(d);

                            const average = @as(Vec4f, @splat(0.25)) * (al + bl + cl + dl);

                            const bytes = Pack3b.init3(
                                baseenc.floatToUnorm8(spectrum.linearToGamma_sRGB(average[0])),
                                baseenc.floatToUnorm8(spectrum.linearToGamma_sRGB(average[1])),
                                baseenc.floatToUnorm8(spectrum.linearToGamma_sRGB(average[2])),
                            );

                            image.set2D(il, x, y, bytes);
                        }
                    }
                }
            },

            else => {},
        }
    }

    fn normalFromByte2(v: Vec2b) Vec4f {
        const nmxy = enc.cachedSnormToFloat2(v);
        const nmz = @sqrt(math.max(1.0 - math.dot2(nmxy, nmxy), 0.01));
        const nm = Vec4f{ nmxy[0], nmxy[1], nmz, 0.0 };
        return nm;
    }
};
