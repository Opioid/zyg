const std = @import("std");

pub const Min_roughness: f32 = 0.01314;
pub const Min_alpha: f32 = Min_roughness * Min_roughness;

pub fn clampRoughness(roughness: f32) f32 {
    return std.math.max(roughness, Min_roughness);
}
