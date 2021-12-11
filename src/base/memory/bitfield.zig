const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Bitfield = struct {
    num_bytes: u64,
    buffer: [*]u32,

    const Mask: u32 = 0x80000000;
    const Log2Bits: u32 = 5;
    const Bits: u32 = 1 << Log2Bits;

    pub fn init(alloc: Allocator, num_bits: u64) !Bitfield {
        const num_bytes = countNumBytes(num_bits);

        return Bitfield{
            .num_bytes = num_bytes,
            .buffer = (try alloc.alloc(u32, num_bytes / @sizeOf(u32))).ptr,
        };
    }

    pub fn deinit(self: *Bitfield, alloc: Allocator) void {
        alloc.free(self.buffer[0 .. self.num_bytes / @sizeOf(u32)]);
    }

    pub fn slice(self: Bitfield) []u32 {
        return self.buffer[0 .. self.num_bytes / @sizeOf(u32)];
    }

    pub fn get(self: Bitfield, index: u64) bool {
        const mask = @intCast(u32, Mask >> @intCast(u5, index % Bits));

        return (self.buffer[index >> Log2Bits] & mask) != 0;
    }

    pub fn countNumBytes(num_bits: u64) u64 {
        const chunks = num_bits / Bits;
        return (if (0 == num_bits % Bits) chunks else chunks + 1) * @sizeOf(u32);
    }
};
