const cvb = @import("curve_buffer.zig");
const ReadStream = @import("../../../file/read_stream.zig").ReadStream;

const base = @import("base");
const math = base.math;
const Pack3f = math.Pack3f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

// reader for HAIR data format
// http://www.cemyuksel.com/research/hairmodels/

pub const Reader = struct {
    const Error = error{
        BadSignature,
        UnsetVerticesFlag,
    };

    const Flags = packed struct(u32) {
        has_segments: bool,
        has_vertices: bool,
        has_thickness: bool,
        has_transparency: bool,
        has_color: bool,

        padding: u27,
    };

    pub fn read(alloc: Allocator, stream: *ReadStream) !cvb.Buffer {
        var header: [4]u8 = undefined;
        _ = stream.read(&header) catch {
            return Error.BadSignature;
        };

        var num_strands: u32 = 0;
        _ = try stream.read(std.mem.asBytes(&num_strands));

        var num_vertices: u32 = 0;
        _ = try stream.read(std.mem.asBytes(&num_vertices));

        var flags: Flags = undefined;
        _ = try stream.read(std.mem.asBytes(&flags));

        if (!flags.has_vertices) {
            return Error.UnsetVerticesFlag;
        }

        var default_num_segments: u32 = 0;
        _ = try stream.read(std.mem.asBytes(&default_num_segments));

        var default_thickness: f32 = 0;
        _ = try stream.read(std.mem.asBytes(&default_thickness));

        var default_transparency: f32 = 0;
        _ = try stream.read(std.mem.asBytes(&default_transparency));

        var default_color: Pack3f = Pack3f.init1(0.0);
        _ = try stream.read(std.mem.asBytes(&default_color));

        // some file info
        // var info: [88]u8 = undefined;
        // _ = try stream.read(&info);
        try stream.seekBy(88);

        // try stream.seekTo(0);
        // try stream.seekTo(128);

        var segments: []u16 = &.{};
        defer alloc.free(segments);

        if (flags.has_segments) {
            segments = try alloc.alloc(u16, num_strands);
            _ = try stream.read(std.mem.sliceAsBytes(segments));
        }

        var vertices: []Pack3f = &.{};
        defer alloc.free(vertices);

        if (flags.has_vertices) {
            vertices = try alloc.alloc(Pack3f, num_vertices);
            _ = try stream.read(std.mem.sliceAsBytes(vertices));
        }

        if (flags.has_thickness) {
            std.debug.print("has thickness\n", .{});
        }

        var num_curves: u32 = 0;

        for (0..num_strands) |i| {
            const strand_segments = if (segments.len > 0) @as(u32, segments[i]) else default_num_segments;

            num_curves += (strand_segments / 3) + @as(u32, if ((strand_segments % 3) > 0) 1 else 0);
        }

        var positions = try alloc.alloc(Pack3f, num_curves * 4);
        var widths = try alloc.alloc(f32, num_curves * 2);

        var source_count: u32 = 0;
        var dest_count: u32 = 0;

        for (0..num_strands) |i| {
            const strand_segments = if (segments.len > 0) @as(u32, segments[i]) else default_num_segments;

            for (0..strand_segments / 3) |_| {
                positions[dest_count + 0] = fromHAIRspace(vertices[source_count + 0]);
                positions[dest_count + 1] = fromHAIRspace(vertices[source_count + 1]);
                positions[dest_count + 2] = fromHAIRspace(vertices[source_count + 2]);
                positions[dest_count + 3] = fromHAIRspace(vertices[source_count + 3]);

                dest_count += 4;
                source_count += 3;
            }

            const rem = strand_segments % 3;

            if (rem > 0) {
                positions[dest_count + 0] = fromHAIRspace(vertices[source_count + 0]);
                positions[dest_count + 1] = fromHAIRspace(vertices[source_count + 1]);
                positions[dest_count + 2] = fromHAIRspace(vertices[source_count + @min(2, rem)]);
                positions[dest_count + 3] = fromHAIRspace(vertices[source_count + @min(2, rem)]);

                dest_count += 4;
                source_count += rem;
            }

            source_count += 1;
        }

        for (widths) |*w| {
            w.* = default_thickness * 0.01;
        }

        return cvb.Buffer{ .Separate = cvb.Separate.initOwned(positions, widths) };

        //   return try genericCrap(alloc);
    }

    fn fromHAIRspace(p: Pack3f) Pack3f {
        const s = comptime 0.01;
        return Pack3f.init3(-p.v[1] * s, p.v[2] * s, p.v[0] * s);
    }

    fn genericCrap(alloc: Allocator) !cvb.Buffer {
        const w: u32 = 32;
        const h: u32 = 32;

        const fw: f32 = @floatFromInt(w);
        const fh: f32 = @floatFromInt(h);

        const num_curves = 2 * w * h;

        var positions = try alloc.alloc(Pack3f, num_curves * 4);
        var widths = try alloc.alloc(f32, num_curves * 2);

        const vertices = cvb.Buffer{ .Separate = cvb.Separate.initOwned(positions, widths) };

        var rng = RNG.init(0, 0);

        for (0..h) |y| {
            for (0..w) |x| {
                const id: u32 = @intCast(y * w + x);

                const fx: f32 = @floatFromInt(x);
                const fy: f32 = @floatFromInt(y);

                const ox = fx - 0.5 * fw;
                const oy = fy - 0.5 * fh;

                const girth = 0.025 + 0.025 * rng.randomFloat();

                const height = 1.0 + 0.5 * rng.randomFloat();

                positions[id * 8 + 0] = Pack3f.init3(ox * 0.2 + 0.2 * (rng.randomFloat() - 0.5), 0.0 * height, oy * 0.2 + 0.2 * (rng.randomFloat() - 0.5));
                positions[id * 8 + 1] = Pack3f.init3(ox * 0.2 + 0.2 * (rng.randomFloat() - 0.5), 0.33 * height, oy * 0.2 + 0.2 * (rng.randomFloat() - 0.5));
                positions[id * 8 + 2] = Pack3f.init3(ox * 0.2 + 0.2 * (rng.randomFloat() - 0.5), 0.66 * height, oy * 0.2 + 0.2 * (rng.randomFloat() - 0.5));
                positions[id * 8 + 3] = Pack3f.init3(ox * 0.2 + 0.3 * (rng.randomFloat() - 0.5), 1.0 * height, oy * 0.2 + 0.3 * (rng.randomFloat() - 0.5));

                positions[id * 8 + 4] = positions[id * 8 + 3];
                positions[id * 8 + 5] = Pack3f.init3(ox * 0.2 + 0.3 * (rng.randomFloat() - 0.5), 1.2 * height, oy * 0.2 + 0.3 * (rng.randomFloat() - 0.5));
                positions[id * 8 + 6] = Pack3f.init3(ox * 0.2 + 0.3 * (rng.randomFloat() - 0.5), 1.4 * height, oy * 0.2 + 0.3 * (rng.randomFloat() - 0.5));
                positions[id * 8 + 7] = Pack3f.init3(ox * 0.2 + 0.4 * (rng.randomFloat() - 0.5), 1.6 * height, oy * 0.2 + 0.4 * (rng.randomFloat() - 0.5));

                widths[id * 4 + 0] = girth;
                widths[id * 4 + 1] = girth - girth * 0.75 * rng.randomFloat();
                widths[id * 4 + 2] = widths[id * 4 + 1];
                widths[id * 4 + 3] = 0.0;
            }
        }

        // const num_curves: u32 = 1;

        // var positions = try alloc.alloc(Pack3f, 1 * 4);
        // var widths = try alloc.alloc(f32, 1 * 2);

        // var vertices = cvb.Buffer{ .Separate = cvb.Separate.initOwned(positions, widths) };

        // positions[0] = Pack3f.init3(0.0, 0.0, 0.0);
        // positions[1] = Pack3f.init3(0.0, 0.5, 0.0);
        // positions[2] = Pack3f.init3(0.0, 1.0, 0.0);
        // positions[3] = Pack3f.init3(0.0, 1.5, 0.0);

        // widths[0] = 0.5;
        // widths[1] = 0.25;

        return vertices;
    }
};
