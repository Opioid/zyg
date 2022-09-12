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

const List = std.ArrayListUnmanaged;

const Data = struct {
    gonio_type: u32,

    vertical_angles: List(f32) = .{},
    horizontal_angles: List(f32) = .{},
    intensities: List(f32) = .{},

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

        const hit = memory.lowerBound(f32, horizontal_angles, phi) - 1;
        const vit = memory.lowerBound(f32, vertical_angles, theta) - 1;

        // if (hit > 0) {
        //     hit -= 1;
        // }

        // if (vit > 0) {
        //     vit -= 1;
        // }

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

            // const ins: [4]f32 = .{
            //     intensities[vit + hit * num_vangles],
            //     intensities[(vit + 1) % num_vangles + hit * num_vangles],
            //     intensities[vit + ((hit + 1) % num_hangles) * num_vangles],
            //     intensities[(vit + 1) % num_vangles + ((hit + 1) % num_hangles) * num_vangles],
            // };

            // return math.bilinear1(ins, d_theta, d_phi);

            const ivit = @intCast(i32, vit);
            const ihit = @intCast(i32, hit);
            const inv = @intCast(i32, num_vangles);
            const inh = @intCast(i32, num_hangles);

            const vm1 = offset(ivit, -1, inv);
            const vp0 = offset(ivit, 0, inv);
            const vp1 = offset(ivit, 1, inv);
            const vp2 = offset(ivit, 2, inv);

            const hm1 = offset(ihit, -1, inh) * num_vangles;
            const hp0 = offset(ihit, 0, inh) * num_vangles;
            const hp1 = offset(ihit, 1, inh) * num_vangles;
            const hp2 = offset(ihit, 2, inh) * num_vangles;

            const ins: [16]f32 = .{
                intensities[vm1 + hm1],
                intensities[vp0 + hm1],
                intensities[vp1 + hm1],
                intensities[vp2 + hm1],

                intensities[vm1 + hp0],
                intensities[vp0 + hp0],
                intensities[vp1 + hp0],
                intensities[vp2 + hp0],

                intensities[vm1 + hp1],
                intensities[vp0 + hp1],
                intensities[vp1 + hp1],
                intensities[vp2 + hp1],

                intensities[vm1 + hp2],
                intensities[vp0 + hp2],
                intensities[vp1 + hp2],
                intensities[vp2 + hp2],
            };

            return bicatmullRom(ins, d_theta, d_phi);
        }
    }

    fn offset(x: i32, i: i32, b: i32) u32 {
        const y = x + i;

        if (y < 0) {
            return @intCast(u32, 1 - y);
        }

        return @intCast(u32, if (y >= b) (b - i) else y);
    }

    pub fn catmullRom(c: *const [4]f32, t: f32) f32 {
        const t2 = t * t;
        const a0 = -0.5 * c[0] + 1.5 * c[1] - 1.5 * c[2] + 0.5 * c[3];
        const a1 = c[0] - 2.5 * c[1] + 2.0 * c[2] - 0.5 * c[3];
        const a2 = -0.5 * c[0] + 0.5 * c[2];
        const a3 = c[1];

        return a0 * t * t2 + a1 * t2 + a2 * t + a3;
    }

    pub fn bicatmullRom(c: [16]f32, s: f32, t: f32) f32 {
        const d: [4]f32 = .{
            catmullRom(c[0..4], s),
            catmullRom(c[4..8], s),
            catmullRom(c[8..12], s),
            catmullRom(c[12..16], s),
        };

        return catmullRom(&d, t);
    }
};

const Tokenizer = struct {
    it: std.mem.TokenIterator(u8) = .{ .index = 0, .buffer = &.{}, .delimiter_bytes = &.{} },
    stream: *ReadStream,
    buf: []u8,

    pub fn next(self: *Tokenizer) ![]const u8 {
        if (self.it.next()) |token| {
            return token;
        }

        const line = try self.stream.readUntilDelimiter(self.buf, '\n');
        self.it = std.mem.tokenize(u8, line, " \r");
        return self.it.next().?;
    }

    pub fn skip(self: *Tokenizer) !void {
        _ = try self.next();
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

        var tokenizer = Tokenizer{ .stream = stream, .buf = &buf };

        // num lamps
        try tokenizer.skip();

        // lumens per lamp
        try tokenizer.skip();

        // candela multiplier
        try tokenizer.skip();

        const num_vertical_angles = try std.fmt.parseInt(u32, try tokenizer.next(), 10);
        const num_horizontal_angles = try std.fmt.parseInt(u32, try tokenizer.next(), 10);
        const gonio_type = try std.fmt.parseInt(u32, try tokenizer.next(), 10);

        // unitsType
        try tokenizer.skip();

        // lumWidth
        try tokenizer.skip();

        // lumLength
        try tokenizer.skip();

        // lumHeight
        try tokenizer.skip();

        // ballastFactor
        try tokenizer.skip();

        // balastLampPhotometricFactor
        try tokenizer.skip();

        // inputWatts
        try tokenizer.skip();

        var data = Data{ .gonio_type = gonio_type };
        defer data.deinit(alloc);

        try data.vertical_angles.resize(alloc, num_vertical_angles);
        try data.horizontal_angles.resize(alloc, num_horizontal_angles);
        try data.intensities.resize(alloc, num_vertical_angles * num_horizontal_angles);

        for (data.vertical_angles.items) |*a| {
            a.* = try std.fmt.parseFloat(f32, try tokenizer.next());
        }

        for (data.horizontal_angles.items) |*a| {
            a.* = try std.fmt.parseFloat(f32, try tokenizer.next());
        }

        var mi: f32 = 0.0;
        for (data.intensities.items) |*i| {
            const v = try std.fmt.parseFloat(f32, try tokenizer.next());
            i.* = v;
            mi = @maximum(mi, v);
        }

        const d = Vec2i{ 512, 512 };

        var image = try img.Byte1.init(alloc, img.Description.init2D(d));

        const idf = @splat(2, @as(f32, 1.0)) / math.vec2iTo2f(d);

        const imi = 1.0 / mi;

        var y: i32 = 0;
        while (y < d[1]) : (y += 1) {
            const v = idf[1] * (@intToFloat(f32, y) + 0.5);

            var x: i32 = 0;
            while (x < d[0]) : (x += 1) {
                const u = idf[0] * (@intToFloat(f32, x) + 0.5);

                const dir = math.smpl.octDecode(@splat(2, @as(f32, 2.0)) * (Vec2f{ u, v } - @splat(2, @as(f32, 0.5))));

                const ll = dirToLatlong(Vec4f{ dir[0], -dir[2], -dir[1], 0.0 });

                const value = data.sample(ll[0], ll[1]);

                image.set2D(x, y, encoding.floatToUnorm(math.saturate(value * imi)));
            }
        }

        return Image{ .Byte1 = image };
    }

    fn dirToLatlong(v: Vec4f) Vec2f {
        const phi = std.math.atan2(f32, v[0], v[2]);

        return .{
            if (phi < 0) (2.0 * std.math.pi) + phi else phi,
            std.math.acos(v[1]),
        };
    }

    fn nextToken(it: *std.mem.TokenIterator(u8), stream: *ReadStream, buf: []u8) !?[]const u8 {
        if (it.next()) |token| {
            return token;
        }

        const line = try stream.readUntilDelimiter(buf, '\n');
        it.* = std.mem.tokenize(u8, line, " \r");
        return it.next();
    }
};
