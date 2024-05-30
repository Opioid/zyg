pub const NodeStack = struct {
    const Num_elements = 127;

    end: u32 = 0,
    stack: [Num_elements]u32 = undefined,

    pub const End: u32 = 0xFFFFFFFF;

    pub fn clear(self: *NodeStack) void {
        self.end = 0;
    }

    pub fn push(self: *NodeStack, value: u32) void {
        const end = self.end;
        self.stack[end] = value;
        self.end = end + 1;
    }

    pub fn pop(self: *NodeStack) u32 {
        var end = self.end;

        if (0 == end) {
            return End;
        }

        end -= 1;
        self.end = end;
        return self.stack[end];
    }
};
