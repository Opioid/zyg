const math = @import("base").math;
const Vec4f = math.Vec4f;

pub const Emittance = struct {
    const Quantity = enum {
        Flux,
        Intensity,
        Radiosity,
        Radiance,
    };

    value: Vec4f,
    quantity: Quantity,

    // unit: watt per unit solid angle per unit projected area (W / sr / m^2)
    pub fn setRadiance(self: *Emittance, rad: Vec4f) void {
        self.value = rad;
        self.quantity = Quantity.Radiance;
    }

    pub fn radiance(self: Emittance, area: f32) Vec4f {
        if (self.quantity == Quantity.Intensity) {
            return self.value.divScalar3(area);
        }

        return self.value;
    }
};
