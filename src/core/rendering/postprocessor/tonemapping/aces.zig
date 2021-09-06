const Base = @import("tonemapper_base.zig").Base;

usingnamespace @import("base");
const ThreadContext = thread.Pool.Context;

pub const ACES = struct {
    super: Base = .{},

    pub fn applyRange(context: ThreadContext, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self = @intToPtr(*ACES, context);

        for (self.super.source.pixels[begin..end]) |p, i| {
            const j = begin + i;
            self.super.destination.pixels[j] = p;
        }
    }
};
