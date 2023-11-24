const img = @import("../../image/image.zig");
const Image = img.Image;
const PngWriter = @import("../../image/encoding/png/png_writer.zig").Writer;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;
const Spectrum = spectrum.DiscreteSpectralPowerDistribution(512, 380.0, 720.0);
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn integrate(alloc: Allocator) !void {
    Spectrum.staticInit();

    const Bins = Spectrum.Bins / 16;

    var rainbow: [Bins]Vec4f = undefined;

    var sum_rgb: Vec4f = @splat(0.0);

    for (rainbow, 0..) |*r, i| {
        var color: Vec4f = @splat(0.0);

        var sub: u32 = 0;
        while (sub < 16) : (sub += 1) {
            var temp = Spectrum.init();
            temp.values[i * 16 + sub] = 1.0 / 16.0;
            color += math.clamp(spectrum.XYZtoAP1(temp.normalizedXYZ()), 0.0, 1.0);
        }

        r.* = color;
        sum_rgb += color;
    }

    // hack-normalize
    const n = @as(Vec4f, @splat(rainbow.len)) / (@as(Vec4f, @splat(3.0)) * sum_rgb);

    for (rainbow) |*r| {
        r.* = math.clamp(n * r.*, 0.0, 1.0);
    }

    var file = try std.fs.cwd().createFile("rainbow_integral.zig", .{});
    defer file.close();

    var buffered = std.io.bufferedWriter(file.writer());
    const writer = buffered.writer();

    try write_rainbow_table(writer, &rainbow, Spectrum.wavelengthsStart(), Spectrum.wavelengthsEnd());

    try buffered.flush();

    const d = Vec2i{ 1024, 256 };

    var image = try img.Float3.init(alloc, img.Description.init2D(d));

    const wl_range = (Spectrum.wavelengthsEnd() - Spectrum.wavelengthsStart()) / @as(f32, @floatFromInt(d[0] - 1));

    var x: i32 = 0;
    while (x < d[0]) : (x += 1) {
        var y: i32 = 0;
        while (y < d[1]) : (y += 1) {
            const wl = Spectrum.wavelengthsStart() + @as(f32, @floatFromInt(x)) * wl_range;
            const color = spectrumAtWavelength(&rainbow, Spectrum.wavelengthsStart(), Spectrum.wavelengthsEnd(), wl);

            image.set2D(x, y, math.vec4fTo3f(color));
        }
    }

    try PngWriter.writeFloat3Scaled(alloc, image, 1.0);
}

fn spectrumAtWavelength(rainbow: []Vec4f, wl_start: f32, wl_end: f32, wl: f32) Vec4f {
    const nb = @as(f32, @floatFromInt(rainbow.len));

    const u = ((wl - wl_start) / (wl_end - wl_start)) * nb;
    const id = @as(u32, @intFromFloat(u));
    const frac = u - @as(f32, @floatFromInt(id));

    if (id >= rainbow.len - 1) {
        return rainbow[rainbow.len - 1];
    }

    return math.lerp4(rainbow[id], rainbow[id + 1], frac);
}

fn write_rainbow_table(writer: anytype, rainbow: []Vec4f, wl_start: f32, wl_end: f32) !void {
    var buffer: [256]u8 = undefined;

    var line = try std.fmt.bufPrint(&buffer, "const Vec4f = @import(\"base\").math.Vec4f;\n\n", .{});
    _ = try writer.write(line);

    line = try std.fmt.bufPrint(&buffer, "pub const Wavelength_start: f32 = {d:.1};\n", .{wl_start});
    _ = try writer.write(line);

    line = try std.fmt.bufPrint(&buffer, "pub const Wavelength_end: f32 = {d:.1};\n\n", .{wl_end});
    _ = try writer.write(line);

    line = try std.fmt.bufPrint(&buffer, "pub const Num_bands = {};\n", .{rainbow.len});
    _ = try writer.write(line);

    _ = try writer.write("\n");

    line = try std.fmt.bufPrint(&buffer, "pub const Rainbow = [{}]Vec4f{{\n", .{rainbow.len});
    _ = try writer.write(line);

    for (rainbow) |r| {
        line = try std.fmt.bufPrint(&buffer, "    .{{ {d:.8}, {d:.8}, {d:.8}, 1.0 }},\n", .{ r[0], r[1], r[2] });
        _ = try writer.write(line);
    }

    _ = try writer.write("};\n");
}
