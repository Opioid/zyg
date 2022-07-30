const img = @import("../../image.zig");
const Image = img.Image;
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec3b = math.Vec3b;
const Vec4f = math.Vec4f;
const encoding = base.encoding;
const memory = base.memory;

const std = @import("std");
const Allocator = std.mem.Allocator;

const AL = std.ArrayListUnmanaged;

const Data = struct {
    gonio_type: u32,

    vertical_angles: AL(f32) = .{},
    horizontal_angles: AL(f32) = .{},
    intensities: AL(f32) = .{},

    pub fn deinit(self: *Data, alloc: Allocator) void {
        self.intensities.deinit(alloc);
        self.horizontal_angles.deinit(alloc);
        self.vertical_angles.deinit(alloc);
    }

    pub fn sample(self: Data, rad_phi: f32, rad_theta: f32) f32 {
        var phi = math.radiansToDegrees(rad_phi);
        var theta = math.radiansToDegrees(rad_theta);

        var vertical_symmetric = false;
        var non_symmetric = false;

        const vertical_angles = self.vertical_angles.items;
        const horizontal_angles = self.horizontal_angles.items;

        const vf = vertical_angles[0];
        const vb = vertical_angles[vertical_angles.len - 1];
        const hf = horizontal_angles[0];
        const hb = horizontal_angles[horizontal_angles.len - 1];

        if (1 == self.gonio_type) {
            if (0.0 == hb) {
                phi = 0.0;
                vertical_symmetric = true;
            } else if (90.0 == hb) {
                if (phi > 90.0 and phi < 180.0) {
                    phi = 180.0 - phi;
                }

                if (phi > 180.0 and phi < 270.0) {
                    phi -= 180.0;
                }

                if (phi > 270.0 and phi < 360.0) {
                    phi = 360.0 - phi;
                }

                if (phi < 0.0 or phi > 90.0 or theta < 0.0 or theta > 180.0) {
                    return 0.0;
                }
            } else if (180.0 == hb) {
                if (phi > 180.0) {
                    phi = 360.0 - phi;
                }

                if (phi < 0.0 or phi > 180 or theta < 0 or theta > 180.0) {
                    return 0.0;
                }
            } else if (90.0 == hf and 270.0 == hb) {
                if (phi < 90.0 or phi > 270.0) {
                    phi = 180 - phi;
                }

                if (phi < 90.0 or phi > 270.0) {
                    return 0.0;
                }
            } else {
                non_symmetric = true;
            }
        } else {
            theta -= 90.0;
            phi -= 180.0;

            if (vf >= 0.0) {
                theta = @fabs(theta);
            }

            if (hf >= 0.0) {
                phi = @fabs(phi);
            }

            if (phi < hf or phi > hb) {
                return 0.0;
            }

            if (theta < vf or theta > vb) {
                return 0.0;
            }
        }

        if (vertical_symmetric and (phi < hf or phi > hb)) {
            return 0.0;
        }

        if (theta < vf or theta > vb) {
            return 0.0;
        }

        var hit = memory.lowerBound(f32, horizontal_angles, phi);
        var vit = memory.lowerBound(f32, vertical_angles, theta);

        if (hit > 0) {
            hit -= 1;
        }

        if (vit > 0) {
            vit -= 1;
        }

        const num_vangles = vertical_angles.len;
        const num_hangles = horizontal_angles.len;

        var next_phi: f32 = undefined;
        if (non_symmetric) {
            if (vit >= num_vangles - 1) {
                return 0.0;
            }
            // wrap phi for full range lookups with none symmetry type
            next_phi = if (hit < num_hangles - 1) horizontal_angles[hit + 1] else horizontal_angles[(hit + 1) % num_hangles];
        } else {
            if (!vertical_symmetric and (hit >= num_hangles - 1 or vit >= num_vangles - 1)) {
                return 0.0;
            }
            next_phi = if (hit < num_hangles - 1) horizontal_angles[hit + 1] else horizontal_angles[hit];
        }

        const next_theta = if (vit < num_vangles - 1) vertical_angles[vit + 1] else vertical_angles[vit];

        const d_theta = (theta - vertical_angles[vit]) / (next_theta - vertical_angles[vit]);

        const intensities = self.intensities.items;

        if (vertical_symmetric) {
            const in0 = intensities[vit];
            const in1 = intensities[(vit + 1) % num_vangles];
            return math.lerp(in0, in1, d_theta);
        } else {
            const d_phi = (phi - horizontal_angles[hit]) / (next_phi - horizontal_angles[hit]);

            const ins: [4]f32 = .{
                intensities[vit + hit * num_vangles],
                intensities[(vit + 1) % num_vangles + hit * num_vangles],
                intensities[vit + ((hit + 1) % num_hangles) * num_vangles],
                intensities[(vit + 1) % num_vangles + ((hit + 1) % num_hangles) * num_vangles],
            };

            return math.bilinear1(ins, d_theta, d_phi);
        }
    }
};

pub const Reader = struct {
    const Error = error{
        BadInitialToken,
        NotImplemented,
    };

    pub fn read(alloc: Allocator, stream: *ReadStream) !Image {
        var buf: [256]u8 = undefined;

        {
            const line = try stream.readUntilDelimiter(&buf, '\n');

            if (!std.mem.startsWith(u8, line, "IES")) {
                return Error.BadInitialToken;
            }
        }

        while (true) {
            const line = try stream.readUntilDelimiter(&buf, '\n');

            if (std.mem.startsWith(u8, line, "TILT=NONE")) {
                break;
            }
        }

        // const line = try stream.readUntilDelimiter(&buf, '\n');

        var it = std.mem.TokenIterator(u8){ .index = 0, .buffer = &.{}, .delimiter_bytes = &.{} };
        // std.mem.tokenize(u8, line, " ");

        // while (try nextToken(&it, stream, &buf)) |token| {
        //     std.debug.print("{s}\n", .{token});
        // }

        // num lamps
        _ = try nextToken(&it, stream, &buf);

        // lumens per lamp
        _ = try nextToken(&it, stream, &buf);

        // candela multiplier
        _ = try nextToken(&it, stream, &buf);

        const num_vertical_angles = try std.fmt.parseInt(u32, (try nextToken(&it, stream, &buf)).?, 10);
        const num_horizontal_angles = try std.fmt.parseInt(u32, (try nextToken(&it, stream, &buf)).?, 10);
        std.debug.print("num_vertical_angles {} num_horizontal_angles {}\n", .{ num_vertical_angles, num_horizontal_angles });

        const gonio_type = try std.fmt.parseInt(u32, (try nextToken(&it, stream, &buf)).?, 10);
        std.debug.print("gonio_type {}\n", .{gonio_type});

        // unitsType
        _ = try nextToken(&it, stream, &buf);

        // lumWidth
        _ = try nextToken(&it, stream, &buf);

        // lumLength
        _ = try nextToken(&it, stream, &buf);

        // lumHeight
        _ = try nextToken(&it, stream, &buf);

        const ballast_factor = try std.fmt.parseFloat(f32, (try nextToken(&it, stream, &buf)).?);
        std.debug.print("ballast_factor {}\n", .{ballast_factor});

        // balastLampPhotometricFactor
        _ = try nextToken(&it, stream, &buf);

        //  std.debug.print("token \n\n{any}\n\n", .{(try nextToken(&it, stream, &buf)).?});

        const input_watts = try std.fmt.parseFloat(f32, (try nextToken(&it, stream, &buf)).?);
        std.debug.print("input_watts {}\n", .{input_watts});

        _ = alloc;

        var data = Data{ .gonio_type = gonio_type };
        defer data.deinit(alloc);

        try data.vertical_angles.resize(alloc, num_vertical_angles);
        try data.horizontal_angles.resize(alloc, num_horizontal_angles);
        try data.intensities.resize(alloc, num_vertical_angles * num_horizontal_angles);

        for (data.vertical_angles.items) |*a| {
            a.* = try std.fmt.parseFloat(f32, (try nextToken(&it, stream, &buf)).?);
        }

        for (data.horizontal_angles.items) |*a| {
            a.* = try std.fmt.parseFloat(f32, (try nextToken(&it, stream, &buf)).?);
        }

        var mi: f32 = 0.0;
        for (data.intensities.items) |*i| {
            const v = try std.fmt.parseFloat(f32, (try nextToken(&it, stream, &buf)).?);
            i.* = v;
            mi = @maximum(mi, v);
        }

        const d = Vec2i{ 512, 256 };

        var image = try img.Byte1.init(alloc, img.Description.init2D(d));

        const idf = @splat(2, @as(f32, 1.0)) / math.vec2iTo2f(d);

        const imi = 1.0 / mi;

        var y: i32 = 0;
        while (y < d[1]) : (y += 1) {
            const v = idf[1] * (@intToFloat(f32, y) + 0.5);
            const theta = v * std.math.pi;

            var x: i32 = 0;
            while (x < d[0]) : (x += 1) {
                const u = idf[0] * (@intToFloat(f32, x) + 0.5);
                const phi = u * (2.0 * std.math.pi);

                const dir = latlongToDir(phi, theta);
                const rotdir = Vec4f{ dir[0], -dir[2], dir[1], 0.0 };
                const latlong = dirToLatlong(rotdir);

                const value = data.sample(latlong[0], latlong[1]);

                image.set2D(x, y, encoding.floatToUnorm(@minimum(value * imi, 1.0)));
            }
        }

        return Image{ .Byte1 = image };
    }

    fn latlongToDir(phi: f32, theta: f32) Vec4f {
        const sin_phi = @sin(phi);
        const cos_phi = @cos(phi);
        const sin_theta = @sin(theta);
        const cos_theta = @cos(theta);

        return .{ sin_phi * sin_theta, cos_theta, cos_phi * sin_theta, 0.0 };
    }

    fn dirToLatlong(v: Vec4f) Vec2f {
        const lat = std.math.atan2(f32, v[0], v[2]);

        return .{
            if (lat < 0) lat + 2.0 * std.math.pi else lat,
            std.math.acos(v[1]),
        };
    }

    fn nextToken(it: *std.mem.TokenIterator(u8), stream: *ReadStream, buf: []u8) !?[]const u8 {
        if (it.next()) |token| {
            return token;
        }

        var line = try stream.readUntilDelimiter(buf, '\n');

        // remove trailing carriage return
        if (13 == line[line.len - 1]) {
            line = line[0 .. line.len - 1];
        }

        it.* = std.mem.tokenize(u8, line, " ");
        return it.next();
    }
};
