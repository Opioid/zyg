usingnamespace @import("vector2.zig");

pub fn goldenRatio1D(samples: []f32, r: f32) void {
    // set the initial second coordinate
    var x = r;
    // set the second coordinates
    for (samples) |*s| {
        s.* = x;

        // increment the coordinate
        x += 0.618033988749894;
        if (x >= 1.0) {
            --x;
        }
    }
}

pub fn goldenRatio2D(samples: []Vec2f, r: Vec2f) void {
    // set the initial first coordinate
    var x = r.v[0];
    var min = x;
    var idx: u32 = 0;
    // set the first coordinates
    for (samples) |*s, i| {
        s.*.v[1] = x;
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
    samples[0].v[0] = samples[idx].v[1];
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
        samples[i].v[0] = samples[idx].v[1];
    }

    // set the initial second coordinate
    var y = r.v[1];
    // set the second coordinates
    for (samples) |*s| {
        s.*.v[1] = y;

        // increment the coordinate
        y += 0.618033988749894;
        if (y >= 1.0) {
            y -= 1.0;
        }
    }
}
