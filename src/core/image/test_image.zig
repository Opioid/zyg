const base = @import("base");
const enc = base.encoding;
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("miniz/miniz.h");
});

pub fn write_reference_normal_map(alloc: Allocator, name: []const u8) !void {
    const dim = 1024;
    const fdim: f32 = @floatFromInt(dim);

    const num_pixels = dim * dim;
    const buffer = try alloc.alloc(u8, 3 * num_pixels);
    defer alloc.free(buffer);

    const subsamples = 4;
    const fss: f32 = @floatFromInt(subsamples);

    for (0..dim) |y| {
        const fy: f32 = @floatFromInt(y);

        for (0..dim) |x| {
            const fx: f32 = @floatFromInt(x);

            var fsy = 0.5 * (1.0 / fss);

            var n: Vec4f = @splat(0.0);

            for (0..subsamples) |_| {
                var fsx = 0.5 * (1.0 / fss);
                for (0..subsamples) |_| {
                    const p = Vec2f{ (fx + fsx) / fdim, (fy + fsy) / fdim };

                    n += referenceNormal(p);

                    fsx += 1.0 / fss;
                }

                fsy += 1.0 / fss;
            }

            n /= @splat(@floatFromInt(subsamples * subsamples));

            const i = y * dim + x;

            buffer[i * 3 + 0] = enc.floatToSnorm8(n[0]);
            buffer[i * 3 + 1] = enc.floatToSnorm8(n[1]);
            buffer[i * 3 + 2] = enc.floatToSnorm8(n[2]);
        }
    }

    var buffer_len: usize = 0;
    const png = c.tdefl_write_image_to_png_file_in_memory(
        @as(*const anyopaque, @ptrCast(buffer.ptr)),
        dim,
        dim,
        3,
        &buffer_len,
    );

    var file = try std.fs.cwd().createFile(name, .{});
    defer file.close();

    try file.writer().writeAll(@as([*]const u8, @ptrCast(png))[0..buffer_len]);
}

fn referenceNormal(uv: Vec2f) Vec4f {
    const p = @as(Vec2f, @splat(2.0)) * (uv - @as(Vec2f, @splat(0.5)));

    const r2 = p[0] * p[0] + p[1] * p[1];

    if (r2 >= 1.0) {
        return .{ 0.0, 0.0, 1.0, 0.0 };
    }

    const longitude = std.math.atan2(p[1], p[0]);

    // Equal-area projection

    const sin_col = @sqrt(r2);
    const cos_col = @sqrt(1.0 - r2);

    const sin_lon = @sin(longitude);
    const cos_lon = @cos(longitude);

    return .{ sin_col * cos_lon, sin_col * sin_lon, cos_col, 0.0 };
}
