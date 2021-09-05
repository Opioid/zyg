const Scene = @import("../scene.zig").Scene;

pub const Light = struct {
    prop: u32,
    part: u32,

    extent: f32 = undefined,

    pub fn prepareSampling(self: Light, light_id: usize, scene: *Scene) void {
        scene.propPrepareSampling(self.prop, self.part, light_id);
    }
};
