const base = @import("base");
usingnamespace base;
usingnamespace base.math;

pub const VertexStream = union(enum) {
    Json: VertexStreamJson,

    pub fn numVertices(self: VertexStream) u32 {
        return switch (self) {
            .Json => |js| @intCast(u32, js.positions.len),
        };
    }

    pub fn position(self: VertexStream, i: usize) Vec4f {
        switch (self) {
            .Json => |js| {
                const p = js.positions[i];
                return Vec4f.init3(p.v[0], p.v[1], p.v[2]);
            },
        }
    }

    pub fn frame(self: VertexStream, i: usize) Quaternion {
        return switch (self) {
            .Json => |js| js.frame(i),
        };
    }

    pub fn bitangentSign(self: VertexStream, i: usize) bool {
        return switch (self) {
            .Json => |js| js.bitangentSign(i),
        };
    }
};

const VertexStreamJson = struct {
    positions: []Vec3f,
    normals: []Vec3f,
    tangents: []Vec4f,

    const Self = @This();

    // pub fn position(self: Self, i: u32) Vec3f {
    //     return self.positions[i];
    // }

    pub fn frame(self: Self, i: usize) Quaternion {
        const n3 = self.normals[i];
        const n = Vec4f.init3(n3.v[0], n3.v[1], n3.v[2]);
        const t = self.tangents[i];

        return quaternion.initFromTN(t, n);
    }

    pub fn bitangentSign(self: Self, i: usize) bool {
        return self.tangents[i] > 0.0;
    }
};
