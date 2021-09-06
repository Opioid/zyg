const ACES = @import("aces.zig").ACES;
const Linear = @import("linear.zig").Linear;
const Float4 = @import("../../../image/image.zig").Float4;
const base = @import("base");
usingnamespace base;

pub const Tonemapper = union(enum) {
    ACES: ACES,
    Linear: Linear,

    pub fn apply(self: *Tonemapper, source: *const Float4, destination: *Float4, threads: *thread.Pool) void {
        switch (self.*) {
            .ACES => |*a| {
                a.super.source = source;
                a.super.destination = destination;
                threads.runRange(a, ACES.applyRange, 0, @intCast(u32, source.description.numPixels()));
            },
            .Linear => |*l| {
                l.super.source = source;
                l.super.destination = destination;
                threads.runRange(l, Linear.applyRange, 0, @intCast(u32, source.description.numPixels()));
            },
        }
    }
};