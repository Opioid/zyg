const Num_elements = 127;

pub const NodeStack = struct {
    end: u32,
    stack: [Num_elements]u32,

    pub fn empty(self: NodeStack) bool {
        return 0 == self.end;
    }

    pub fn clear(self: *NodeStack) void {
        self.end = 0;
    }

    pub fn push(self: *NodeStack, value: u32) void {
        self.stack[self.end] = value;
        self.end += 1;
    }

    pub fn pop(self: *NodeStack) u32 {
        var end = self.end;
        end -= 1;
        const item = self.stack[end];
        self.end = end;
        return item;
    }
};
