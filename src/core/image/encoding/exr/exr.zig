pub const Signature = [4]u8{ 0x76, 0x2f, 0x31, 0x01 };

pub const Channel = struct {
    pub const Format = enum(u32) {
        Uint,
        Half,
        Float,
    };

    name: []const u8,

    format: Format,

    pub fn byteSize(self: Channel) u32 {
        return switch (self.format) {
            .Half => 2,
            else => 4,
        };
    }
};

pub const Compression = enum(u8) {
    No,
    RLE,
    ZIPS,
    ZIP,
    PIZ,
    PXR24,
    B44,
    B44A,
    Undefined,

    pub fn numScanlinesPerBlock(self: Compression) u32 {
        return switch (self) {
            .No, .RLE, .ZIPS => 1,
            .ZIP, .PXR24 => 16,
            .PIZ, .B44, .B44A => 16,
            else => 0,
        };
    }

    pub fn numScanlineBlocks(self: Compression, num_scanlines: u32) u32 {
        const pb = self.numScanlinesPerBlock();

        if (0 == pb) {
            return 0;
        }

        const x = num_scanlines / pb;
        return if (0 != num_scanlines % pb) x + 1 else x;
    }
};
