const core = @import("core");
const scn = core.scn;

const base = @import("base");
const math = base.math;
const Pack4f = math.Pack4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Operator = struct {
    pub const Class = enum {
        Add,
        Diff,
        Over,
        Tonemap,
    };

    class: Class,

    textures: std.ArrayListUnmanaged(core.tx.Texture) = .{},
    input_ids: std.ArrayListUnmanaged(u32) = .{},
    target: core.image.Float4 = .{},
    tonemapper: core.Tonemapper,
    scene: *const scn.Scene,
    current: u32 = 0,

    const Self = @This();

    pub fn configure(self: *Self, alloc: Allocator) !void {
        if (0 == self.textures.items.len) {
            return;
        }

        const desc = self.textures.items[0].description(self.scene.*);

        try self.target.resize(alloc, desc);
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.input_ids.deinit(alloc);
        self.textures.deinit(alloc);
    }

    pub fn iterations(self: Self) u32 {
        return switch (self.class) {
            .Add, .Over => 1,
            .Diff => @intCast(u32, self.textures.items.len - 1),
            .Tonemap => @intCast(u32, self.textures.items.len),
        };
    }

    pub fn run(self: Self, threads: *Threads) void {
        const texture = self.textures.items[self.current];

        const dim = texture.description(self.scene.*).dimensions;

        _ = threads.runRange(&self, runRange, 0, @intCast(u32, dim.v[1]), 0);
    }

    fn runRange(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;

        var self = @intToPtr(*Self, context);

        if (.Diff == self.class) {
            const texture_a = self.textures.items[0];
            const texture_b = self.textures.items[self.current + 1];

            const dim = texture_a.description(self.scene.*).dimensions;
            const width = dim.v[0];

            var y = begin;
            while (y < end) : (y += 1) {
                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    const ux = @intCast(i32, x);
                    const uy = @intCast(i32, y);

                    switch (self.class) {
                        .Diff => {
                            const color_a = texture_a.get2D_4(ux, uy, self.scene.*);
                            const color_b = texture_b.get2D_4(ux, uy, self.scene.*);

                            const dif = @fabs(color_a - color_b);

                            self.target.set2D(ux, uy, Pack4f.init4(dif[0], dif[1], dif[2], dif[3]));
                        },
                        else => unreachable,
                    }
                }
            }
        } else {
            const current = self.current;
            const texture = self.textures.items[current];

            const dim = texture.description(self.scene.*).dimensions;
            const width = dim.v[0];

            var y = begin;
            while (y < end) : (y += 1) {
                var x: u32 = 0;
                while (x < width) : (x += 1) {
                    const ux = @intCast(i32, x);
                    const uy = @intCast(i32, y);

                    switch (self.class) {
                        .Add => {
                            var color = texture.get2D_4(ux, uy, self.scene.*);

                            for (self.textures.items[current + 1 ..]) |t| {
                                const other = t.get2D_4(ux, uy, self.scene.*);
                                color += other;
                            }

                            const tm = self.tonemapper.tonemap(color);
                            self.target.set2D(ux, uy, Pack4f.init4(tm[0], tm[1], tm[2], color[3]));
                        },
                        .Over => {
                            var color = texture.get2D_4(ux, uy, self.scene.*);

                            for (self.textures.items[current + 1 ..]) |t| {
                                const other = t.get2D_4(ux, uy, self.scene.*);
                                color += other * @splat(4, 1.0 - color[3]);
                            }

                            const tm = self.tonemapper.tonemap(color);
                            self.target.set2D(ux, uy, Pack4f.init4(tm[0], tm[1], tm[2], color[3]));
                        },
                        .Tonemap => {
                            const color = texture.get2D_4(ux, uy, self.scene.*);
                            const tm = self.tonemapper.tonemap(color);
                            self.target.set2D(ux, uy, Pack4f.init4(tm[0], tm[1], tm[2], color[3]));
                        },
                        else => unreachable,
                    }
                }
            }
        }
    }
};
