pub const Signature = [4]u8{ 0x76, 0x2f, 0x31, 0x01 };

pub const Channel = struct {
    pub const Type = enum(u32) {
        Uint = 0,
        Half,
        Float,
    };

    name: []const u8,

    typef: Type,
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
};
