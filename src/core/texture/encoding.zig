const base = @import("base");
const enc = base.encoding;
const spectrum = base.spectrum;
const math = base.math;
const Vec2b = math.Vec2b;
const Vec2f = math.Vec2f;
const Pack3b = math.Pack3b;
const Pack4b = math.Pack4b;
const Vec4f = math.Vec4f;

const SRGB_FLOAT = calculateSrgbToFloat();
const UNORM_FLOAT = calculateUnormToFloat();
const SNORM_FLOAT = calculateSnormToFloat();

pub fn cachedSrgbToFloat3(byte: Pack3b) Vec4f {
    return .{ SRGB_FLOAT[byte.v[0]], SRGB_FLOAT[byte.v[1]], SRGB_FLOAT[byte.v[2]], 0.0 };
}

pub fn cachedSrgbToFloat4(byte: Pack4b) Vec4f {
    return .{ SRGB_FLOAT[byte.v[0]], SRGB_FLOAT[byte.v[1]], SRGB_FLOAT[byte.v[2]], UNORM_FLOAT[byte.v[3]] };
}

pub fn cachedUnormToFloat(byte: u8) f32 {
    return UNORM_FLOAT[byte];
}

pub fn cachedUnormToFloat2(byte: Vec2b) Vec2f {
    return .{ UNORM_FLOAT[byte[0]], UNORM_FLOAT[byte[1]] };
}

pub fn cachedSnormToFloat2(byte: Vec2b) Vec2f {
    return .{ SNORM_FLOAT[byte[0]], SNORM_FLOAT[byte[1]] };
}

pub fn cachedSnormToFloat3(byte: Pack3b) Vec4f {
    return .{ SNORM_FLOAT[byte.v[0]], SNORM_FLOAT[byte.v[1]], SNORM_FLOAT[byte.v[2]], 0.0 };
}

const Num_samples = 256;

fn calculateSrgbToFloat() [Num_samples]f32 {
    @setEvalBranchQuota(20100);

    var buf: [Num_samples]f32 = undefined;

    for (&buf, 0..) |*b, i| {
        b.* = spectrum.srgb.gammaToLinear(@as(f32, @floatFromInt(i)) / 255.0);
    }

    return buf;
}

fn calculateUnormToFloat() [Num_samples]f32 {
    var buf: [Num_samples]f32 = undefined;

    for (&buf, 0..) |*b, i| {
        b.* = enc.unorm8ToFloat(@intCast(i));
    }

    return buf;
}

fn calculateSnormToFloat() [Num_samples]f32 {
    var buf: [Num_samples]f32 = undefined;

    for (&buf, 0..) |*b, i| {
        b.* = enc.snorm8ToFloat(@intCast(i));
    }

    return buf;
}
