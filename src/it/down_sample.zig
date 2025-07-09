const core = @import("core");
const Texture = core.tx.Texture;
const image = core.image;
const scn = core.scene;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;
const spectrum = base.spectrum;

pub const DownSample = struct {
    pub fn process(
        target: *image.Float4,
        source: Texture,
        scene: *const scn.Scene,
        begin: u32,
        end: u32,
    ) void {
        const dim = target.dimensions;
        const width = dim[0];

        var y = begin;
        while (y < end) : (y += 1) {
            const iy: i32 = @intCast(y);

            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const ix: i32 = @intCast(x);

                const a = source.get2D_4(ix * 2 + 0, iy * 2 + 0, scene);
                const b = source.get2D_4(ix * 2 + 1, iy * 2 + 0, scene);
                const c = source.get2D_4(ix * 2 + 0, iy * 2 + 1, scene);
                const d = source.get2D_4(ix * 2 + 1, iy * 2 + 1, scene);

                const average = @as(Vec4f, @splat(0.25)) * (a + b + c + d);

                const srgb = spectrum.aces.AP1tosRGB(average);

                target.set2D(ix, iy, Pack4f.init4(srgb[0], srgb[1], srgb[2], 1.0));
            }
        }
    }
};
