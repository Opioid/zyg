pub const Generator = struct {
    state: u64,
    inc: u64,

    pub inline fn init(state: u64, sequence: u64) Generator {
        var g: Generator = undefined;

        g.start(state, sequence);

        return g;
    }

    pub inline fn start(self: *Generator, state: u64, sequence: u64) void {
        self.state = 0;
        self.inc = (sequence << 1) | 1;

        _ = self.randomUint();
        self.state +%= state;
        _ = self.randomUint();
    }

    pub inline fn randomUint(self: *Generator) u32 {
        return self.advancePCG32();
    }

    pub inline fn randomFloat(self: *Generator) f32 {
        var bits = self.advancePCG32();

        bits &= 0x007FFFFF;
        bits |= 0x3F800000;

        return @as(f32, @bitCast(bits)) - 1.0;
    }

    inline fn advancePCG32(self: *Generator) u32 {
        const old = self.state;

        // Advance internal state
        self.state = old *% 6364136223846793005 +% self.inc;

        // Calculate output function (XSH RR), uses old state for max ILP
        const xrs: u32 = @truncate(((old >> 18) ^ old) >> 27);
        const rot: u5 = @truncate(old >> 59);

        return (xrs >> rot) | (xrs << ((0 -% rot) & 31));
    }
};

pub const SingleGenerator = struct {
    state: u64 = undefined,

    pub inline fn init(state: u64) SingleGenerator {
        var g = SingleGenerator{};

        g.start(state);

        return g;
    }

    pub inline fn start(self: *SingleGenerator, state: u64) void {
        self.state = 0;

        _ = self.randomUint();
        self.state +%= state;
        _ = self.randomUint();
    }

    pub inline fn randomUint(self: *SingleGenerator) u32 {
        return self.advancePCG32();
    }

    pub inline fn randomFloat(self: *SingleGenerator) f32 {
        var bits = self.advancePCG32();

        bits &= 0x007FFFFF;
        bits |= 0x3F800000;

        return @as(f32, @bitCast(bits)) - 1.0;
    }

    inline fn advancePCG32(self: *SingleGenerator) u32 {
        const old = self.state;

        // Advance internal state
        self.state = old *% 6364136223846793005 +% 1;

        // Calculate output function (XSH RR), uses old state for max ILP
        const xrs = @as(u32, @truncate(((old >> 18) ^ old) >> 27));
        const rot = @as(u5, @truncate(old >> 59));

        return (xrs >> rot) | (xrs << ((0 -% rot) & 31));
    }
};
