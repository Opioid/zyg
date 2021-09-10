const base = @import("base");
const enc = base.encoding;
const spectrum = base.spectrum;
const math = base.math;
const Vec2b = math.Vec2b;
const Vec2f = math.Vec2f;
const Vec3b = math.Vec3b;
const Vec4f = math.Vec4f;

const SRGB_FLOAT = calculateSnormToFloat();
const SNORM_FLOAT = calculateSnormToFloat();

pub fn cachedSrgbToFloat3(byte: Vec3b) Vec4f {
    return Vec4f.init3(SRGB_FLOAT[byte.v[0]], SRGB_FLOAT[byte.v[1]], SRGB_FLOAT[byte.v[2]]);
}

pub fn cachedSnormToFloat2(byte: Vec2b) Vec2f {
    return Vec2f.init2(SNORM_FLOAT[byte.v[0]], SNORM_FLOAT[byte.v[1]]);
}

const Num_samples: u32 = 256;

fn calculateSrgbToFloat() [Num_samples]f32 {
    var buf: [Num_samples]f32 = undefined;

    var i: u32 = 0;
    while (i < Num_samples) : (i += 1) {
        buf[i] = spectrum.gammaToLinear_sRGB(@floatCast(f32, i) * (1.0 / 255.0));
    }

    return buf;
}

fn calculateSnormToFloat() [Num_samples]f32 {
    var buf: [Num_samples]f32 = undefined;

    var i: u32 = 0;
    while (i < Num_samples) : (i += 1) {
        buf[i] = enc.snormToFloat(@intCast(u8, i));
    }

    return buf;
}
