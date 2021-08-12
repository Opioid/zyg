const Tree = @import("tree.zig").Tree;
const IndexTriangle = @import("../triangle.zig").IndexTriangle;
const VertexStream = @import("../vertex_stream.zig").VertexStream;

pub const BuilderSAH = struct {
    pub fn init() BuilderSAH {
        return .{};
    }

    pub fn build(
        self: *BuilderSAH,
        tree: *Tree,
        triangles: []const IndexTriangle,
        vertices: VertexStream,
    ) void {
        _ = self;
    }
};
