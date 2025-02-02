const Blur = @import("blur.zig").Blur;
const Denoise = @import("denoise.zig").Denoise;

const core = @import("core");
const scn = core.scn;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Operator = struct {
    pub const Class = union(enum) {
        Add,
        Anaglyph,
        Average,
        Blur: Blur,
        Denoise: Denoise,
        Diff,
        MaxValue: Vec4f,
        Over,
        Tonemap: core.Tonemapper.Class,
    };

    class: Class,

    textures: std.ArrayListUnmanaged(core.tx.Texture) = .empty,
    input_ids: std.ArrayListUnmanaged(u32) = .empty,
    target: core.image.Float4 = .{},
    tonemapper: core.Tonemapper,
    scene: *const scn.Scene,
    current: u32 = 0,

    const Self = @This();

    pub fn configure(self: *Self, alloc: Allocator) !void {
        if (0 == self.textures.items.len) {
            return;
        }

        const desc = self.textures.items[0].description(self.scene);

        try self.target.resize(alloc, desc);
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.input_ids.deinit(alloc);
        self.textures.deinit(alloc);

        switch (self.class) {
            inline .Blur, .Denoise => |*op| op.deinit(alloc),
            else => {},
        }
    }

    pub fn iterations(self: Self) u32 {
        const num_textures: u32 = @intCast(self.textures.items.len);

        return switch (self.class) {
            .Anaglyph => num_textures / 2,
            .Diff => num_textures - 1,
            .Tonemap, .Blur => num_textures,
            else => 1,
        };
    }

    pub fn baseItemOfIteration(self: Self, iteration: u32) u32 {
        return switch (self.class) {
            .Anaglyph => self.input_ids.items[iteration / 2],
            else => self.input_ids.items[iteration],
        };
    }

    pub fn run(self: *Self, threads: *Threads) void {
        const texture = self.textures.items[self.current];

        const dim = texture.description(self.scene).dimensions;

        _ = threads.runRange(self, runRange, 0, @intCast(dim[1]), 0);
    }

    fn runRange(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self: *Self = @ptrCast(@alignCast(context));

        if (.Anaglyph == self.class) {
            const offset = self.current * 2;
            const texture_a = self.textures.items[offset];
            const texture_b = self.textures.items[offset + 1];

            const dim = texture_a.description(self.scene).dimensions;
            const width = dim[0];

            var y = begin;
            while (y < end) : (y += 1) {
                const iy: i32 = @intCast(y);

                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    const ix: i32 = @intCast(x);

                    const color_a = self.tonemapper.tonemap(texture_a.get2D_4(ix, iy, self.scene));
                    const color_b = self.tonemapper.tonemap(texture_b.get2D_4(ix, iy, self.scene));

                    self.target.set2D(ix, iy, Pack4f.init4(color_a[0], color_b[1], color_b[2], 0.5 * (color_a[3] + color_b[3])));
                }
            }
        } else if (.Blur == self.class) {
            self.class.Blur.process(&self.target, self.textures.items[self.current], self.scene, begin, end);
        } else if (.Denoise == self.class) {
            const offset = self.current * 2;
            const color = self.textures.items[offset];
            const source_normal = self.textures.items[offset + 1];
            const albedo = self.textures.items[offset + 2];
            const depth = self.textures.items[offset + 3];

            // TODO: Float3 textures have already been converted to AP1. So what do we do?!?
            // Either figure out a way to pass the encoding to this specific texture on loading time
            // or bite the bullet and be more consistent by just loading the floats and handle color space conversion
            // at access time, like for bytes...
            const normal = if (1 == source_normal.bytesPerChannel()) source_normal.cast(.Byte3_snorm) catch source_normal else source_normal;

            self.class.Denoise.process(&self.target, color, normal, albedo, depth, self.scene, begin, end);
        } else if (.Diff == self.class) {
            const texture_a = self.textures.items[0];
            const texture_b = self.textures.items[self.current + 1];

            const dim = texture_a.description(self.scene).dimensions;
            const width = dim[0];

            var y = begin;
            while (y < end) : (y += 1) {
                const iy: i32 = @intCast(y);

                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    const ix: i32 = @intCast(x);

                    const color_a = texture_a.get2D_4(ix, iy, self.scene);
                    const color_b = texture_b.get2D_4(ix, iy, self.scene);

                    const dif = @abs(color_a - color_b);

                    self.target.set2D(ix, iy, Pack4f.init4(dif[0], dif[1], dif[2], dif[3]));
                }
            }
        } else {
            const current = self.current;
            const texture = self.textures.items[current];

            const dim = texture.description(self.scene).dimensions;
            const width = dim[0];

            const factor: Vec4f = @splat(if (.Average == self.class) 1.0 / @as(f32, @floatFromInt(self.textures.items.len)) else 1.0);

            var y = begin;
            while (y < end) : (y += 1) {
                const iy: i32 = @intCast(y);

                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    const ix: i32 = @intCast(x);

                    const source = texture.get2D_4(ix, iy, self.scene);

                    const color = switch (self.class) {
                        .Add, .Average => blk: {
                            var color = factor * source;

                            for (self.textures.items[current + 1 ..]) |t| {
                                const other = t.get2D_4(ix, iy, self.scene);
                                color += factor * other;
                            }

                            break :blk color;
                        },
                        .MaxValue => |max_value| math.max4(source, max_value),
                        .Over => blk: {
                            var color = source;

                            for (self.textures.items[current + 1 ..]) |t| {
                                const other = t.get2D_4(ix, iy, self.scene);
                                color += other * @as(Vec4f, @splat(1.0 - color[3]));
                            }

                            break :blk color;
                        },
                        .Tonemap => source,
                        else => unreachable,
                    };

                    const tm = self.tonemapper.tonemap(color);
                    self.target.set2D(ix, iy, Pack4f.init4(tm[0], tm[1], tm[2], color[3]));
                }
            }
        }
    }
};
