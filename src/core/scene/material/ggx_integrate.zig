const bxdf = @import("bxdf.zig");
const fresnel = @import("fresnel.zig");
const ggx = @import("ggx.zig");
const hlp = @import("sample_helper.zig");
const sample = @import("sample_base.zig");
const Layer = sample.Layer;
const IoR = sample.IoR;
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");

// pub const E = calculate_f_ss_table();
// pub const E_size = E[0].len;

fn integrate_f_ss(alpha: f32, n_dot_wo: f32, num_samples: u32) f32 {
    if (alpha < ggx.Min_alpha) {
        return 1.0;
    }

    const schlick = fresnel.Schlick.init(@splat(4, @as(f32, 1.0)));
    const layer = Layer{
        .t = .{ 1.0, 0.0, 0.0, 0.0 },
        .b = .{ 0.0, 1.0, 0.0, 0.0 },
        .n = .{ 0.0, 0.0, 1.0, 0.0 },
    };

    const cn_dot_wo = hlp.clamp(n_dot_wo);

    // (sin, 0, cos)
    const wo = Vec4f{ @sqrt(1.0 - cn_dot_wo * cn_dot_wo), 0.0, cn_dot_wo, 0.0 };

    var accum: f32 = 0.0;
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const xi = math.hammersley(i, num_samples, 0);

        var result: bxdf.Sample = undefined;
        const n_dot_wi = ggx.Iso.reflect(wo, cn_dot_wo, alpha, xi, schlick, layer, &result);

        accum += (n_dot_wi * result.reflection[0]) / result.pdf;
    }

    return accum / @intToFloat(f32, num_samples);
}

fn integrate_f_s_ss(alpha: f32, ior_t: f32, n_dot_wo: f32, num_samples: u32) f32 {
    if (alpha < ggx.Min_alpha or ior_t <= 1.0) {
        return 1.0;
    }

    const layer = Layer{
        .t = .{ 1.0, 0.0, 0.0, 0.0 },
        .b = .{ 0.0, 1.0, 0.0, 0.0 },
        .n = .{ 0.0, 0.0, 1.0, 0.0 },
    };

    const cn_dot_wo = hlp.clamp(n_dot_wo);

    // (sin, 0, cos)
    const wo = Vec4f{ @sqrt(1.0 - cn_dot_wo * cn_dot_wo), 0.0, cn_dot_wo, 0.0 };

    const same_side = math.dot3(wo, layer.n) > 0.0;

    const tior = IoR{ .eta_t = ior_t, .eta_i = 1.0 };
    const ior = tior.swapped(same_side);

    const f0 = fresnel.Schlick.F0(ior.eta_i, ior.eta_t);

    var accum: f32 = 0.0;
    var i: u32 = 0;
    while (i < num_samples) : (i += 1) {
        const xi = math.hammersley(i, num_samples, 0);

        var n_dot_h: f32 = undefined;
        const h = ggx.Aniso.sample(wo, @splat(2, alpha), xi, layer, &n_dot_h);

        const wo_dot_h = hlp.clampDot(wo, h);
        const eta = ior.eta_i / ior.eta_t;
        const sint2 = (eta * eta) * (1.0 - wo_dot_h * wo_dot_h);

        var f: f32 = undefined;
        var wi_dot_h: f32 = undefined;
        if (sint2 >= 1.0) {
            f = 1.0;
            wi_dot_h = 0.0;
        } else {
            wi_dot_h = @sqrt(1.0 - sint2);
            const cos_x = if (ior.eta_i > ior.eta_t) wi_dot_h else wo_dot_h;
            f = fresnel.schlick1(cos_x, f0);
        }

        var result: bxdf.Sample = undefined;
        {
            const n_dot_wi = ggx.Iso.reflectNoFresnel(
                wo,
                h,
                cn_dot_wo,
                n_dot_h,
                wi_dot_h,
                wo_dot_h,
                alpha,
                layer,
                &result,
            );

            const inti = (@minimum(n_dot_wi, n_dot_wo) * f * result.reflection[0]) / result.pdf;

            if (std.math.isNan(inti)) {
                std.debug.print("reflection\n", .{});
            }

            accum += (@minimum(n_dot_wi, n_dot_wo) * f * result.reflection[0]) / result.pdf;
        }
        {
            const r_wo_dot_h = if (same_side) -wo_dot_h else wo_dot_h;
            const n_dot_wi = ggx.Iso.refractNoFresnel(
                wo,
                h,
                cn_dot_wo,
                n_dot_h,
                -wi_dot_h,
                r_wo_dot_h,
                alpha,
                ior,
                layer,
                &result,
            );

            const omf = 1.0 - f;

            const inti = (n_dot_wi * omf * result.reflection[0]) / result.pdf;

            if (std.math.isNan(inti)) {
                std.debug.print("refraction {}\n", .{result.pdf});
            }

            accum += (n_dot_wi * omf * result.reflection[0]) / result.pdf;
        }
    }

    return accum / @intToFloat(f32, num_samples);
}

fn make_f_ss_table(writer: anytype, buffer: []u8) !void {
    const Num_samples = 32;

    //  var table: [Num_samples_f_ss][Num_samples_f_ss]f32 = undefined;

    var line = try std.fmt.bufPrint(buffer, "pub const E_size = {};\n", .{Num_samples});
    _ = try writer.write(line);

    _ = try writer.write("\n");

    line = try std.fmt.bufPrint(buffer, "pub const E = [{} * {}]f32{{\n", .{ Num_samples, Num_samples });
    _ = try writer.write(line);

    const step = 1.0 / @intToFloat(f32, Num_samples - 1);

    var alpha: f32 = 0.0;

    var a: u32 = 0;
    while (a < Num_samples) : (a += 1) {
        line = try std.fmt.bufPrint(buffer, "    // alpha {d:.8}\n    ", .{alpha});
        _ = try writer.write(line);

        var n_dot_wo: f32 = 0.0;

        var i: u32 = 0;
        while (i < Num_samples) : (i += 1) {
            const e = integrate_f_ss(alpha, n_dot_wo, 1024);

            line = try std.fmt.bufPrint(buffer, "{d:.8},", .{e});
            _ = try writer.write(line);

            if (i < Num_samples - 1) {
                if (i > 0 and 0 == ((i + 1) % 8)) {
                    _ = try writer.write("\n    ");
                } else {
                    _ = try writer.write(" ");
                }
            } else {
                _ = try writer.write("\n");
            }

            n_dot_wo += step;
        }

        if (a < Num_samples - 1) {
            _ = try writer.write("\n");
        } else {
            _ = try writer.write("};");
        }

        alpha += step;
    }
}

fn make_f_s_ss_table(writer: anytype, buffer: []u8) !void {
    const Num_samples = 32;

    //  var table: [Num_samples_f_ss][Num_samples_f_ss]f32 = undefined;

    var line = try std.fmt.bufPrint(buffer, "pub const E_s_size = {};\n", .{Num_samples});
    _ = try writer.write(line);

    _ = try writer.write("\n");

    line = try std.fmt.bufPrint(buffer, "pub const E_s = [{} * {} * {}]f32{{\n", .{ Num_samples, Num_samples, Num_samples });
    _ = try writer.write(line);

    const step = 1.0 / @intToFloat(f32, Num_samples - 1);

    var ior: f32 = 1.0;
    var z: u32 = 0;
    while (z < Num_samples) : (z += 1) {
        line = try std.fmt.bufPrint(buffer, "    // ior {d:.8}\n", .{ior});
        _ = try writer.write(line);

        var alpha: f32 = 0.0;
        var a: u32 = 0;
        while (a < Num_samples) : (a += 1) {
            line = try std.fmt.bufPrint(buffer, "    // alpha {d:.8}\n    ", .{alpha});
            _ = try writer.write(line);

            var n_dot_wo: f32 = 0.0;
            var i: u32 = 0;
            while (i < Num_samples) : (i += 1) {
                const e_s = integrate_f_s_ss(alpha, ior, n_dot_wo, 1024);

                line = try std.fmt.bufPrint(buffer, "{d:.8},", .{e_s});
                _ = try writer.write(line);

                if (i < Num_samples - 1) {
                    if (i > 0 and 0 == ((i + 1) % 8)) {
                        _ = try writer.write("\n    ");
                    } else {
                        _ = try writer.write(" ");
                    }
                } else {
                    _ = try writer.write("\n\n");
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

        ior += step;
    }
}

pub fn integrate() !void {
    var file = try std.fs.cwd().createFile("ggx_integral.zig", .{});
    defer file.close();

    const writer = file.writer();

    var buffer: [256]u8 = undefined;

    try make_f_ss_table(writer, &buffer);

    _ = try writer.write("\n\n");

    try make_f_s_ss_table(writer, &buffer);
}
