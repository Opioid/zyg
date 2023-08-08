const cvb = @import("curve_buffer.zig");
const IndexCurve = @import("curve.zig").IndexCurve;
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
    pub const Result = struct {
        curves: []IndexCurve,
        vertices: cvb.Buffer,
    };

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

    pub fn read(alloc: Allocator, stream: *ReadStream) !Result {
        const generic = true;
        if (generic) {
            return try genericCrap(alloc);
        }

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
        var num_positions: u32 = 0;
        var num_widths: u32 = 0;

        for (0..num_strands) |i| {
            const strand_segments = if (segments.len > 0) @as(u32, segments[i]) else default_num_segments;

            const rem = strand_segments % 3;

            const strand_curves = (strand_segments / 3) + @as(u32, if (rem > 0) 1 else 0);
            num_curves += strand_curves;

            num_positions += strand_curves * 3 + 1;
            num_widths += strand_curves + 1;
        }

        var curves = try alloc.alloc(IndexCurve, num_curves);
        var positions = try alloc.alloc(Pack3f, num_positions);
        var widths = try alloc.alloc(f32, num_widths);

        var source_count: u32 = 0;
        var dest_p_count: u32 = 0;
        var dest_w_count: u32 = 0;

        var cc: u32 = 0;

        for (0..num_strands) |i| {
            const strand_segments = if (segments.len > 0) @as(u32, segments[i]) else default_num_segments;

            for (0..strand_segments / 3) |_| {
                curves[cc].pos = dest_p_count;
                curves[cc].width = dest_w_count;

                cc += 1;

                positions[dest_p_count + 0] = fromHAIRspace(vertices[source_count + 0]);
                positions[dest_p_count + 1] = fromHAIRspace(vertices[source_count + 1]);
                positions[dest_p_count + 2] = fromHAIRspace(vertices[source_count + 2]);

                dest_p_count += 3;
                dest_w_count += 1;
                source_count += 3;
            }

            {
                positions[dest_p_count] = fromHAIRspace(vertices[source_count]);
                dest_p_count += 1;
                dest_w_count += 1;
                source_count += 1;
            }

            const rem = strand_segments % 3;

            if (rem > 0) {
                curves[cc].pos = dest_p_count - 1;
                curves[cc].width = dest_w_count - 1;

                cc += 1;

                const end = @min(1, rem - 1);
                positions[dest_p_count + 0] = fromHAIRspace(vertices[source_count]);
                positions[dest_p_count + 1] = fromHAIRspace(vertices[source_count + end]);
                positions[dest_p_count + 2] = fromHAIRspace(vertices[source_count + end]);

                dest_p_count += 3;
                dest_w_count += 1;
                source_count += rem;
            }
        }

        for (widths) |*w| {
            w.* = default_thickness * 0.01;
        }

        return .{
            .curves = curves,
            .vertices = cvb.Buffer{ .Separate = cvb.Separate.initOwned(positions, widths) },
        };
    }

    fn fromHAIRspace(p: Pack3f) Pack3f {
        const s = comptime 0.01;
        return Pack3f.init3(-p.v[1] * s, p.v[2] * s, p.v[0] * s);
    }

    fn genericCrap(alloc: Allocator) !Result {
        const num_curves: u32 = 2;
        const num_positions: u32 = 7;
        const num_widths: u32 = 3;

        var curves = try alloc.alloc(IndexCurve, num_curves);
        var positions = try alloc.alloc(Pack3f, num_positions);
        var widths = try alloc.alloc(f32, num_widths);

        curves[0].pos = 0;
        curves[0].width = 0;
        curves[1].pos = 3;
        curves[1].width = 1;

        positions[0] = Pack3f.init3(-0.1, -0.5, 0.0);
        positions[1] = Pack3f.init3(-0.05, -0.25, 0.1);
        positions[2] = Pack3f.init3(0.0, 0.0, 0.2);
        positions[3] = Pack3f.init3(0.2, 0.25, 0.3);
        positions[4] = Pack3f.init3(0.325, 0.4, 0.4);
        positions[5] = Pack3f.init3(0.1, 0.5, -0.1);
        positions[6] = Pack3f.init3(0.0, 0.6, -0.3);

        widths[0] = 0.2;
        widths[1] = 0.05;
        widths[2] = 0.001;

        return .{
            .curves = curves,
            .vertices = cvb.Buffer{ .Separate = cvb.Separate.initOwned(positions, widths) },
        };
    }
};
