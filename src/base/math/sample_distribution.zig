const Vec2f = @import("vector2.zig").Vec2f;

pub fn hammersley(i: u32, num_samples: u32, r: u32) Vec2f {
    return .{ @floatFromInt(f32, i) / @floatFromInt(f32, num_samples), radicalInverseVcd(i, r) };
}

fn radicalInverseVcd(bits: u32, r: u32) f32 {
    var out: u32 = undefined;

    out = (bits << 16) | (bits >> 16);
    out = ((out & 0x55555555) << 1) | ((out & 0xAAAAAAAA) >> 1);
    out = ((out & 0x33333333) << 2) | ((out & 0xCCCCCCCC) >> 2);
    out = ((out & 0x0F0F0F0F) << 4) | ((out & 0xF0F0F0F0) >> 4);
    out = ((out & 0x00FF00FF) << 8) | ((out & 0xFF00FF00) >> 8);

    out ^= r;

    return @floatFromInt(f32, out) * 2.3283064365386963e-10; // / 0x100000000
}

pub fn goldenRatio1D(samples: []f32, r: f32) void {
    // set the initial second coordinate
    var x = r;
    // set the second coordinates
    for (samples) |*s| {
        s.* = x;

        // increment the coordinate
        x += 0.618033988749894;
        if (x >= 1.0) {
            x -= 1.0;
        }
    }
}

pub fn goldenRatio2D(samples: []Vec2f, r: Vec2f) void {
    // set the initial first coordinate
    var x = r[0];
    var min = x;
    var idx: u32 = 0;
    // set the first coordinates
    for (samples, 0..) |*s, i| {
        s.*[1] = x;
        // keep the minimum
        if (x < min) {
            min = x;
            idx = @intCast(u32, i);
        }

        // increment the coordinate
        x += 0.618033988749894;
        if (x >= 1.0) {
            x -= 1.0;
        }
    }

    // find the first Fibonacci >= N
    var f: u32 = 1;
    var fp: u32 = 1;
    var parity: u32 = 0;
    while (f + fp < samples.len) : (parity += 1) {
        const tmp = f;
        f += fp;
        fp = tmp;
    }

    // set the increment and decrement
    var inc = fp;
    var dec = f;
    if (1 == (parity & 1)) {
        inc = f;
        dec = fp;
    }

    // permute the first coordinates
    samples[0][0] = samples[idx][1];
    var i: u32 = 1;
    while (i < samples.len) : (i += 1) {
        if (idx < dec) {
            idx += inc;
            if (idx >= samples.len) {
                idx -= dec;
            }
        } else {
            idx -= dec;
        }
        samples[i][0] = samples[idx][1];
    }

    // set the initial second coordinate
    var y = r[1];
    // set the second coordinates
    for (samples) |*s| {
        s.*[1] = y;

        // increment the coordinate
        y += 0.618033988749894;
        if (y >= 1.0) {
            y -= 1.0;
        }
    }
}
