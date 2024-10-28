const bxdf = @import("bxdf.zig");
const fresnel = @import("fresnel.zig");
const ggx = @import("ggx.zig");
const sample = @import("sample_base.zig");
const IoR = sample.IoR;
const img = @import("../../image/image.zig");
const Image = img.Image;
const ExrWriter = @import("../../image/encoding/exr/exr_writer.zig").Writer;

const base = @import("base");
const math = base.math;
const Frame = math.Frame;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

const E_m_samples = 32;
const E_samples = 16;

const E_m_func = math.InterpolatedFunction2D_N(E_m_samples, E_m_samples);
const E_m_avg_func = math.InterpolatedFunction1D_N(E_m_samples);
const E_func = math.InterpolatedFunction3D_N(E_samples, E_samples, E_samples);

fn integrate_micro_directional_albedo(alpha: f32, n_dot_wo: f32, num_samples: u32) f32 {
    const calpha = math.max(alpha, ggx.Min_alpha);

    // Schlick with f0 == 1.0 always evaluates to 1.0
    const schlick = fresnel.Schlick.init(@splat(1.0));
    const frame = Frame{
        .x = .{ 1.0, 0.0, 0.0, 0.0 },
        .y = .{ 0.0, 1.0, 0.0, 0.0 },
        .z = .{ 0.0, 0.0, 1.0, 0.0 },
    };

    // (sin, 0, cos)
    const wo = Vec4f{ @sqrt(1.0 - n_dot_wo * n_dot_wo), 0.0, n_dot_wo, 0.0 };

    var accum: f32 = 0.0;
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const xi = math.hammersley(i, num_samples, 0);

        var result: bxdf.Sample = undefined;
        const micro = ggx.Iso.reflect(wo, n_dot_wo, calpha, xi, schlick, frame, &result);

        accum += ((micro.n_dot_wi * result.reflection[0]) / result.pdf) / @as(f32, @floatFromInt(num_samples));
    }

    return accum;
}

fn integrate_micro_average_albedo(alpha: f32, e_m: E_m_func, num_samples: u32) f32 {
    var accum: f32 = 0.0;
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const xi = math.hammersley(i, num_samples, 0);

        const wo = math.smpl.hemisphereCosine(xi);

        const n_dot_wo = wo[2];

        accum += e_m.eval(n_dot_wo, alpha) / @as(f32, @floatFromInt(num_samples));
    }

    return accum;
}

fn dspbrMicroEc(f0: f32, n_dot_wi: f32, n_dot_wo: f32, alpha: f32, e_m: E_m_func, e_m_avg: E_m_avg_func) f32 {
    const e_wo = e_m.eval(n_dot_wo, alpha);
    const e_wi = e_m.eval(n_dot_wi, alpha);
    const e_avg = e_m_avg.eval(alpha);

    const m = ((1.0 - e_wo) * (1.0 - e_wi)) / (std.math.pi * (1.0 - e_avg));

    const f_avg = (1.0 / 21.0) + (20.0 / 21.0) * f0;

    const f = (f_avg * f_avg * e_avg) / (1.0 - (f_avg * (1.0 - e_avg)));

    return m * f;
}

fn integrate_directional_albedo(alpha: f32, f0: f32, n_dot_wo: f32, e_m: E_m_func, e_m_avg: E_m_avg_func, num_samples: u32) f32 {
    const calpha = math.max(alpha, ggx.Min_alpha);

    const schlick = fresnel.Schlick.init(@splat(f0));
    const frame = Frame{
        .x = .{ 1.0, 0.0, 0.0, 0.0 },
        .y = .{ 0.0, 1.0, 0.0, 0.0 },
        .z = .{ 0.0, 0.0, 1.0, 0.0 },
    };

    // (sin, 0, cos)
    const wo = Vec4f{ @sqrt(1.0 - n_dot_wo * n_dot_wo), 0.0, n_dot_wo, 0.0 };

    var accum: f32 = 0.0;
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const xi = math.hammersley(i, num_samples, 0);

        var result: bxdf.Sample = undefined;
        const micro = ggx.Iso.reflect(wo, n_dot_wo, calpha, xi, schlick, frame, &result);

        const mms = dspbrMicroEc(f0, micro.n_dot_wi, n_dot_wo, calpha, e_m, e_m_avg);

        accum += ((micro.n_dot_wi * (result.reflection[0] + mms)) / result.pdf) / @as(f32, @floatFromInt(num_samples));
    }

    return math.min(accum, 1.0);
}

fn integrate_average_albedo(alpha: f32, f0: f32, e: E_func, num_samples: u32) f32 {
    var accum: f32 = 0.0;
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const xi = math.hammersley(i, num_samples, 0);

        const wo = math.smpl.hemisphereCosine(xi);

        const n_dot_wo = wo[2];

        accum += e.eval(n_dot_wo, alpha, f0) / @as(f32, @floatFromInt(num_samples));
    }

    return accum;
}

fn integrate_f_s_ss(alpha: f32, f0: f32, ior_t: f32, n_dot_wo: f32, num_samples: u32) f32 {
    if (alpha < ggx.Min_alpha or ior_t <= 1.0) {
        return 1.0;
    }

    const frame = Frame{
        .x = .{ 1.0, 0.0, 0.0, 0.0 },
        .y = .{ 0.0, 1.0, 0.0, 0.0 },
        .z = .{ 0.0, 0.0, 1.0, 0.0 },
    };

    const cn_dot_wo = math.safe.clamp(n_dot_wo);

    // (sin, 0, cos)
    const wo = Vec4f{ @sqrt(1.0 - cn_dot_wo * cn_dot_wo), 0.0, cn_dot_wo, 0.0 };

    const ior = IoR{ .eta_t = ior_t, .eta_i = 1.0 };

    var accum: f32 = 0.0;
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const xi = math.hammersley(i, num_samples, 0);

        var n_dot_h: f32 = undefined;
        const h = ggx.Aniso.sample(wo, @splat(alpha), xi, frame, &n_dot_h);

        const wo_dot_h = math.safe.clampDot(wo, h);
        const eta = ior.eta_i / ior.eta_t;
        const sint2 = (eta * eta) * (1.0 - wo_dot_h * wo_dot_h);

        const wi_dot_h = @sqrt(1.0 - sint2);
        const cos_x = if (ior.eta_i > ior.eta_t) wi_dot_h else wo_dot_h;
        const f = fresnel.schlick1(cos_x, f0);

        var result: bxdf.Sample = undefined;
        {
            const n_dot_wi = ggx.Iso.reflectNoFresnel(
                wo,
                h,
                cn_dot_wo,
                n_dot_h,
                wo_dot_h,
                alpha,
                frame,
                &result,
            );

            accum += (math.min(n_dot_wi, n_dot_wo) * f * result.reflection[0]) / result.pdf;
        }
        {
            const r_wo_dot_h = -wo_dot_h;
            const n_dot_wi = ggx.Iso.refractNoFresnel(
                wo,
                h,
                cn_dot_wo,
                n_dot_h,
                -wi_dot_h,
                r_wo_dot_h,
                alpha,
                ior,
                frame,
                &result,
            );

            const omf = 1.0 - f;

            accum += (n_dot_wi * omf * result.reflection[0]) / result.pdf;
        }
    }

    return accum / @as(f32, @floatFromInt(num_samples));
}

fn make_micro_directional_albedo_table(comptime Num_samples: comptime_int, writer: anytype, buffer: []u8, result: []f32) !void {
    var line = try std.fmt.bufPrint(buffer, "pub const E_m_size = {};\n", .{Num_samples});
    _ = try writer.write(line);

    _ = try writer.write("\n");

    line = try std.fmt.bufPrint(buffer, "pub const E_m = [{} * {}]f32{{\n", .{ Num_samples, Num_samples });
    _ = try writer.write(line);

    const step = 1.0 / @as(f32, @floatFromInt(Num_samples - 1));

    var alpha: f32 = 0.0;

    var count: u32 = 0;
    var a: u32 = 0;
    while (a < Num_samples) : (a += 1) {
        line = try std.fmt.bufPrint(buffer, "    // alpha {d:.8}\n    ", .{alpha});
        _ = try writer.write(line);

        var n_dot_wo: f32 = 0.0;

        var i: u32 = 0;
        while (i < Num_samples) : (i += 1) {
            const e = integrate_micro_directional_albedo(alpha, n_dot_wo, 1024);

            line = try std.fmt.bufPrint(buffer, "{d:.8},", .{e});
            _ = try writer.write(line);

            if (i < Num_samples - 1) {
                if (0 == ((i + 1) % 8)) {
                    _ = try writer.write("\n    ");
                } else {
                    _ = try writer.write(" ");
                }
            }

            n_dot_wo += step;

            result[count] = e;
            count += 1;
        }

        if (a < Num_samples - 1) {
            _ = try writer.write("\n");
        } else {
            _ = try writer.write("\n};");
        }

        alpha += step;
    }
}

fn make_micro_average_albedo_table(
    comptime Num_samples: comptime_int,
    e_m: E_m_func,
    writer: anytype,
    buffer: []u8,
    result: []f32,
) !void {
    _ = try writer.write("\n");

    var line = try std.fmt.bufPrint(buffer, "pub const E_m_avg = [{}]f32{{\n    ", .{Num_samples});
    _ = try writer.write(line);

    const step = 1.0 / @as(f32, @floatFromInt(Num_samples - 1));

    var alpha: f32 = 0.0;

    var a: u32 = 0;
    while (a < Num_samples) : (a += 1) {
        const e = integrate_micro_average_albedo(alpha, e_m, 1024);

        line = try std.fmt.bufPrint(buffer, "{d:.8},", .{e});
        _ = try writer.write(line);

        if (a < Num_samples - 1) {
            if (0 == ((a + 1) % 8)) {
                _ = try writer.write("\n    ");
            } else {
                _ = try writer.write(" ");
            }
        } else {
            _ = try writer.write("\n};");
        }

        alpha += step;

        result[a] = e;
    }

    _ = try writer.write("\n");
}

fn make_directional_albedo_table(
    comptime Num_samples: comptime_int,
    e_m: E_m_func,
    e_m_avg: E_m_avg_func,
    writer: anytype,
    buffer: []u8,
    result: []f32,
) !void {
    var line = try std.fmt.bufPrint(buffer, "pub const E_size = {};\n", .{Num_samples});
    _ = try writer.write(line);

    _ = try writer.write("\n");

    line = try std.fmt.bufPrint(buffer, "pub const E = [{} * {} * {}]f32{{\n", .{ Num_samples, Num_samples, Num_samples });
    _ = try writer.write(line);

    const step = 1.0 / @as(f32, @floatFromInt(Num_samples - 1));

    var f0: f32 = 0.0;
    var count: u32 = 0;
    var z: u32 = 0;
    while (z < Num_samples) : (z += 1) {
        line = try std.fmt.bufPrint(buffer, "    // f0 {d:.8}\n", .{f0});
        _ = try writer.write(line);

        var alpha: f32 = 0.0;
        var a: u32 = 0;
        while (a < Num_samples) : (a += 1) {
            line = try std.fmt.bufPrint(buffer, "    // alpha {d:.8}\n    ", .{alpha});
            _ = try writer.write(line);

            var n_dot_wo: f32 = 0.0;
            var i: u32 = 0;
            while (i < Num_samples) : (i += 1) {
                const e = integrate_directional_albedo(alpha, f0, n_dot_wo, e_m, e_m_avg, 1024);

                line = try std.fmt.bufPrint(buffer, "{d:.8},", .{e});
                _ = try writer.write(line);

                if (i < Num_samples - 1) {
                    if (0 == ((i + 1) % 8)) {
                        _ = try writer.write("\n    ");
                    } else {
                        _ = try writer.write(" ");
                    }
                } else {
                    _ = try writer.write("\n");
                }

                n_dot_wo += step;

                result[count] = e;
                count += 1;
            }

            alpha += step;
        }

        if (z < Num_samples - 1) {
            _ = try writer.write("\n");
        } else {
            _ = try writer.write("};");
        }

        f0 += step;
    }

    _ = try writer.write("\n");
}

fn make_average_albedo_table(comptime Num_samples: comptime_int, e: E_func, writer: anytype, buffer: []u8) !void {
    var line = try std.fmt.bufPrint(buffer, "pub const E_avg_size = {};\n", .{Num_samples});
    _ = try writer.write(line);

    _ = try writer.write("\n");

    line = try std.fmt.bufPrint(buffer, "pub const E_avg = [{} * {}]f32{{\n", .{ Num_samples, Num_samples });
    _ = try writer.write(line);

    const step = 1.0 / @as(f32, @floatFromInt(Num_samples - 1));

    var f0: f32 = 0.0;

    var a: u32 = 0;
    while (a < Num_samples) : (a += 1) {
        line = try std.fmt.bufPrint(buffer, "    // f0 {d:.8}\n    ", .{f0});
        _ = try writer.write(line);

        var alpha: f32 = 0.0;

        var i: u32 = 0;
        while (i < Num_samples) : (i += 1) {
            const e_avg = math.min(integrate_average_albedo(alpha, f0, e, 1024), 0.9997);

            line = try std.fmt.bufPrint(buffer, "{d:.8},", .{e_avg});
            _ = try writer.write(line);

            if (i < Num_samples - 1) {
                if (0 == ((i + 1) % 8)) {
                    _ = try writer.write("\n    ");
                } else {
                    _ = try writer.write(" ");
                }
            } else {
                _ = try writer.write("\n");
            }

            alpha += step;
        }

        if (a < Num_samples - 1) {
            _ = try writer.write("\n");
        } else {
            _ = try writer.write("};");
        }

        f0 += step;
    }

    _ = try writer.write("\n");
}

fn make_f_s_ss_table(writer: anytype, buffer: []u8) !void {
    const Num_samples = 16;

    const Max_f0 = 0.25;

    var line = try std.fmt.bufPrint(buffer, "pub const E_s_inverse_max_f0 = {};\n", .{1.0 / Max_f0});
    _ = try writer.write(line);

    line = try std.fmt.bufPrint(buffer, "pub const E_s_size = {};\n", .{Num_samples});
    _ = try writer.write(line);

    _ = try writer.write("\n");

    line = try std.fmt.bufPrint(buffer, "pub const E_s = [{} * {} * {}]f32{{\n", .{ Num_samples, Num_samples, Num_samples });
    _ = try writer.write(line);

    const step = 1.0 / @as(f32, @floatFromInt(Num_samples - 1));

    var f0: f32 = 0.0;
    var z: u32 = 0;
    while (z < Num_samples) : (z += 1) {
        const ior = fresnel.Schlick.F0ToIor(f0);
        line = try std.fmt.bufPrint(buffer, "    // f0/ior {d:.8} {d:.8}\n", .{ f0, ior });
        _ = try writer.write(line);

        var alpha: f32 = 0.0;
        var a: u32 = 0;
        while (a < Num_samples) : (a += 1) {
            line = try std.fmt.bufPrint(buffer, "    // alpha {d:.8}\n    ", .{alpha});
            _ = try writer.write(line);

            var n_dot_wo: f32 = 0.0;
            var i: u32 = 0;
            while (i < Num_samples) : (i += 1) {
                const e_s = integrate_f_s_ss(alpha, f0, ior, n_dot_wo, 1024);

                line = try std.fmt.bufPrint(buffer, "{d:.8},", .{e_s});
                _ = try writer.write(line);

                if (i < Num_samples - 1) {
                    if (0 == ((i + 1) % 8)) {
                        _ = try writer.write("\n    ");
                    } else {
                        _ = try writer.write(" ");
                    }
                } else {
                    _ = try writer.write("\n");
                }

                n_dot_wo += step;
            }

            alpha += step;
        }

        if (z < Num_samples - 1) {
            _ = try writer.write("\n");
        } else {
            _ = try writer.write("};");
        }

        f0 += Max_f0 * step;
    }

    _ = try writer.write("\n");
}

pub fn integrate(alloc: Allocator, threads: *Threads) !void {
    var file = try std.fs.cwd().createFile("ggx_integral.zig", .{});
    defer file.close();

    var buffered = std.io.bufferedWriter(file.writer());
    var writer = buffered.writer();

    var buffer: [256]u8 = undefined;

    const e_m_buffer = try alloc.alloc(f32, E_m_samples * E_m_samples);
    defer alloc.free(e_m_buffer);

    try make_micro_directional_albedo_table(E_m_samples, writer, &buffer, e_m_buffer);

    try writeImage(alloc, E_m_samples, e_m_buffer, threads);

    _ = try writer.write("\n");

    const e_m = E_m_func.fromArray(e_m_buffer.ptr);

    const e_m_avg_buffer = try alloc.alloc(f32, E_m_samples);
    defer alloc.free(e_m_avg_buffer);

    try make_micro_average_albedo_table(E_m_samples, e_m, writer, &buffer, e_m_avg_buffer);

    _ = try writer.write("\n");

    const e_m_avg = E_m_avg_func.fromArray(e_m_avg_buffer.ptr);

    const e_buffer = try alloc.alloc(f32, E_samples * E_samples * E_samples);
    defer alloc.free(e_buffer);

    try make_directional_albedo_table(E_samples, e_m, e_m_avg, writer, &buffer, e_buffer);

    _ = try writer.write("\n");

    const e = E_func.fromArray(e_buffer.ptr);

    try make_average_albedo_table(E_samples, e, writer, &buffer);

    _ = try writer.write("\n");

    try make_f_s_ss_table(writer, &buffer);

    try buffered.flush();
}

fn writeImage(alloc: Allocator, dimensions: u32, data: []f32, threads: *Threads) !void {
    const d: i32 = @intCast(dimensions);

    const buffer = try img.Float4.init(alloc, img.Description.init2D(.{ d, d }));

    var image = Image{ .Float4 = buffer };

    defer image.deinit(alloc);

    for (buffer.pixels, 0..) |*p, i| {
        p.* = Pack4f.init1(data[i]);
    }

    var file = try std.fs.cwd().createFile("integral.exr", .{});
    defer file.close();

    var buffered = std.io.bufferedWriter(file.writer());

    var exr = ExrWriter{ .half = false };
    try exr.write(alloc, buffered.writer(), image, .{ 0, 0, d, d }, .Depth, threads);
    try buffered.flush();
}
