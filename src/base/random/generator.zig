pub const Generator = struct {
    state: u64,
    inc: u64,

    pub fn init(state: u64, sequence: u64) Generator {
        var g = Generator{ .state = 0, .inc = (sequence << 1) | 1 };

        _ = g.randomUint();
        g.state += state;
        _ = g.randomUint();

        return g;
    }

    pub fn randomUint(self: *Generator) u32 {
        return self.advancePCG32();
    }

    pub fn randomFloat(self: *Generator) f32 {
        var bits = self.advancePCG32();

        bits &= 0x007FFFFF;
        bits |= 0x3F800000;

        return @bitCast(f32, bits) - 1.0;
    }

    fn advancePCG32(self: *Generator) u32 {
        const old = self.state;

        // Advance internal state
        self.state = old *% 6364136223846793005 + (self.inc | 1);

        // Calculate output function (XSH RR), uses old state for max ILP
        const xrs = @truncate(u32, ((old >> 18) ^ old) >> 27);
        const rot = @truncate(u5, old >> 59);

        return (xrs >> rot) | (xrs << ((0 -% rot) & 31));
    }
};
