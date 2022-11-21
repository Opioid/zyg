const spectrum = @import("xyz.zig");
const math = @import("../math/vector4.zig");
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn blackbody(temperature: f32) Vec4f {
    const wl_min = 380.0;
    const wl_max = 780.0;
    const wl_step = 5.0;

    const num_steps = @floatToInt(u32, (wl_max - wl_min) / wl_step) + 1;

    var xyz = @splat(4, @as(f32, 0.0));
    var k: u32 = 0;
    while (k < num_steps) : (k += 1) {
        // convert to nanometer
        const wl = (wl_min + @intToFloat(f32, k) * wl_step) * 1.0e-9;
        const p = planck(temperature, wl);

        xyz[0] += p * color_matching[k][0];
        xyz[1] += p * color_matching[k][1];
        xyz[2] += p * color_matching[k][2];
    }

    // normalize the result
    xyz /= @splat(4, std.math.max(xyz[0], std.math.max(xyz[1], xyz[2])));

    return math.max4(spectrum.XYZ_to_sRGB(xyz), @splat(4, @as(f32, 0.0)));
}

fn planck(temperature: f32, wavelength: f32) f32 {
    const h = 6.62606896e-34; // Plank constant
    const c = 2.99792458e+8; // Speed of light
    const k = 1.38064880e-23; // Boltzmann constant
    const a = ((2.0 * std.math.pi) * h) * (c * c);
    const b = (h * c) / k;
    return (a * std.math.pow(f32, wavelength, -5.0)) / (@exp(b / (wavelength * temperature)) - 1.0);
}

// CIE color matching functions
const color_matching = [_][3]f32{
    [3]f32{ 0.0014, 0.0000, 0.0065 }, [3]f32{ 0.0022, 0.0001, 0.0105 }, [3]f32{ 0.0042, 0.0001, 0.0201 },
    [3]f32{ 0.0076, 0.0002, 0.0362 }, [3]f32{ 0.0143, 0.0004, 0.0679 }, [3]f32{ 0.0232, 0.0006, 0.1102 },
    [3]f32{ 0.0435, 0.0012, 0.2074 }, [3]f32{ 0.0776, 0.0022, 0.3713 }, [3]f32{ 0.1344, 0.0040, 0.6456 },
    [3]f32{ 0.2148, 0.0073, 1.0391 }, [3]f32{ 0.2839, 0.0116, 1.3856 }, [3]f32{ 0.3285, 0.0168, 1.6230 },
    [3]f32{ 0.3483, 0.0230, 1.7471 }, [3]f32{ 0.3481, 0.0298, 1.7826 }, [3]f32{ 0.3362, 0.0380, 1.7721 },
    [3]f32{ 0.3187, 0.0480, 1.7441 }, [3]f32{ 0.2908, 0.0600, 1.6692 }, [3]f32{ 0.2511, 0.0739, 1.5281 },
    [3]f32{ 0.1954, 0.0910, 1.2876 }, [3]f32{ 0.1421, 0.1126, 1.0419 }, [3]f32{ 0.0956, 0.1390, 0.8130 },
    [3]f32{ 0.0580, 0.1693, 0.6162 }, [3]f32{ 0.0320, 0.2080, 0.4652 }, [3]f32{ 0.0147, 0.2586, 0.3533 },
    [3]f32{ 0.0049, 0.3230, 0.2720 }, [3]f32{ 0.0024, 0.4073, 0.2123 }, [3]f32{ 0.0093, 0.5030, 0.1582 },
    [3]f32{ 0.0291, 0.6082, 0.1117 }, [3]f32{ 0.0633, 0.7100, 0.0782 }, [3]f32{ 0.1096, 0.7932, 0.0573 },
    [3]f32{ 0.1655, 0.8620, 0.0422 }, [3]f32{ 0.2257, 0.9149, 0.0298 }, [3]f32{ 0.2904, 0.9540, 0.0203 },
    [3]f32{ 0.3597, 0.9803, 0.0134 }, [3]f32{ 0.4334, 0.9950, 0.0087 }, [3]f32{ 0.5121, 1.0000, 0.0057 },
    [3]f32{ 0.5945, 0.9950, 0.0039 }, [3]f32{ 0.6784, 0.9786, 0.0027 }, [3]f32{ 0.7621, 0.9520, 0.0021 },
    [3]f32{ 0.8425, 0.9154, 0.0018 }, [3]f32{ 0.9163, 0.8700, 0.0017 }, [3]f32{ 0.9786, 0.8163, 0.0014 },
    [3]f32{ 1.0263, 0.7570, 0.0011 }, [3]f32{ 1.0567, 0.6949, 0.0010 }, [3]f32{ 1.0622, 0.6310, 0.0008 },
    [3]f32{ 1.0456, 0.5668, 0.0006 }, [3]f32{ 1.0026, 0.5030, 0.0003 }, [3]f32{ 0.9384, 0.4412, 0.0002 },
    [3]f32{ 0.8544, 0.3810, 0.0002 }, [3]f32{ 0.7514, 0.3210, 0.0001 }, [3]f32{ 0.6424, 0.2650, 0.0000 },
    [3]f32{ 0.5419, 0.2170, 0.0000 }, [3]f32{ 0.4479, 0.1750, 0.0000 }, [3]f32{ 0.3608, 0.1382, 0.0000 },
    [3]f32{ 0.2835, 0.1070, 0.0000 }, [3]f32{ 0.2187, 0.0816, 0.0000 }, [3]f32{ 0.1649, 0.0610, 0.0000 },
    [3]f32{ 0.1212, 0.0446, 0.0000 }, [3]f32{ 0.0874, 0.0320, 0.0000 }, [3]f32{ 0.0636, 0.0232, 0.0000 },
    [3]f32{ 0.0468, 0.0170, 0.0000 }, [3]f32{ 0.0329, 0.0119, 0.0000 }, [3]f32{ 0.0227, 0.0082, 0.0000 },
    [3]f32{ 0.0158, 0.0057, 0.0000 }, [3]f32{ 0.0114, 0.0041, 0.0000 }, [3]f32{ 0.0081, 0.0029, 0.0000 },
    [3]f32{ 0.0058, 0.0021, 0.0000 }, [3]f32{ 0.0041, 0.0015, 0.0000 }, [3]f32{ 0.0029, 0.0010, 0.0000 },
    [3]f32{ 0.0020, 0.0007, 0.0000 }, [3]f32{ 0.0014, 0.0005, 0.0000 }, [3]f32{ 0.0010, 0.0004, 0.0000 },
    [3]f32{ 0.0007, 0.0002, 0.0000 }, [3]f32{ 0.0005, 0.0002, 0.0000 }, [3]f32{ 0.0003, 0.0001, 0.0000 },
    [3]f32{ 0.0002, 0.0001, 0.0000 }, [3]f32{ 0.0002, 0.0001, 0.0000 }, [3]f32{ 0.0001, 0.0000, 0.0000 },
    [3]f32{ 0.0001, 0.0000, 0.0000 }, [3]f32{ 0.0001, 0.0000, 0.0000 }, [3]f32{ 0.0000, 0.0000, 0.0000 },
};

pub fn turbo(x: f32) [3]u8 {
    if (x < 0.0) {
        return .{ 0, 0, 0 };
    }

    const i = @floatToInt(u8, x * 255.0 + 0.5);
    return turbo_srgb_bytes[i];
}

// https://gist.github.com/mikhailov-work/6a308c20e494d9e0ccc29036b28faa7a
const turbo_srgb_bytes = [_][3]u8{
    [3]u8{ 48, 18, 59 },   [3]u8{ 50, 21, 67 },   [3]u8{ 51, 24, 74 },    [3]u8{ 52, 27, 81 },
    [3]u8{ 53, 30, 88 },   [3]u8{ 54, 33, 95 },   [3]u8{ 55, 36, 102 },   [3]u8{ 56, 39, 109 },
    [3]u8{ 57, 42, 115 },  [3]u8{ 58, 45, 121 },  [3]u8{ 59, 47, 128 },   [3]u8{ 60, 50, 134 },
    [3]u8{ 61, 53, 139 },  [3]u8{ 62, 56, 145 },  [3]u8{ 63, 59, 151 },   [3]u8{ 63, 62, 156 },
    [3]u8{ 64, 64, 162 },  [3]u8{ 65, 67, 167 },  [3]u8{ 65, 70, 172 },   [3]u8{ 66, 73, 177 },
    [3]u8{ 66, 75, 181 },  [3]u8{ 67, 78, 186 },  [3]u8{ 68, 81, 191 },   [3]u8{ 68, 84, 195 },
    [3]u8{ 68, 86, 199 },  [3]u8{ 69, 89, 203 },  [3]u8{ 69, 92, 207 },   [3]u8{ 69, 94, 211 },
    [3]u8{ 70, 97, 214 },  [3]u8{ 70, 100, 218 }, [3]u8{ 70, 102, 221 },  [3]u8{ 70, 105, 224 },
    [3]u8{ 70, 107, 227 }, [3]u8{ 71, 110, 230 }, [3]u8{ 71, 113, 233 },  [3]u8{ 71, 115, 235 },
    [3]u8{ 71, 118, 238 }, [3]u8{ 71, 120, 240 }, [3]u8{ 71, 123, 242 },  [3]u8{ 70, 125, 244 },
    [3]u8{ 70, 128, 246 }, [3]u8{ 70, 130, 248 }, [3]u8{ 70, 133, 250 },  [3]u8{ 70, 135, 251 },
    [3]u8{ 69, 138, 252 }, [3]u8{ 69, 140, 253 }, [3]u8{ 68, 143, 254 },  [3]u8{ 67, 145, 254 },
    [3]u8{ 66, 148, 255 }, [3]u8{ 65, 150, 255 }, [3]u8{ 64, 153, 255 },  [3]u8{ 62, 155, 254 },
    [3]u8{ 61, 158, 254 }, [3]u8{ 59, 160, 253 }, [3]u8{ 58, 163, 252 },  [3]u8{ 56, 165, 251 },
    [3]u8{ 55, 168, 250 }, [3]u8{ 53, 171, 248 }, [3]u8{ 51, 173, 247 },  [3]u8{ 49, 175, 245 },
    [3]u8{ 47, 178, 244 }, [3]u8{ 46, 180, 242 }, [3]u8{ 44, 183, 240 },  [3]u8{ 42, 185, 238 },
    [3]u8{ 40, 188, 235 }, [3]u8{ 39, 190, 233 }, [3]u8{ 37, 192, 231 },  [3]u8{ 35, 195, 228 },
    [3]u8{ 34, 197, 226 }, [3]u8{ 32, 199, 223 }, [3]u8{ 31, 201, 221 },  [3]u8{ 30, 203, 218 },
    [3]u8{ 28, 205, 216 }, [3]u8{ 27, 208, 213 }, [3]u8{ 26, 210, 210 },  [3]u8{ 26, 212, 208 },
    [3]u8{ 25, 213, 205 }, [3]u8{ 24, 215, 202 }, [3]u8{ 24, 217, 200 },  [3]u8{ 24, 219, 197 },
    [3]u8{ 24, 221, 194 }, [3]u8{ 24, 222, 192 }, [3]u8{ 24, 224, 189 },  [3]u8{ 25, 226, 187 },
    [3]u8{ 25, 227, 185 }, [3]u8{ 26, 228, 182 }, [3]u8{ 28, 230, 180 },  [3]u8{ 29, 231, 178 },
    [3]u8{ 31, 233, 175 }, [3]u8{ 32, 234, 172 }, [3]u8{ 34, 235, 170 },  [3]u8{ 37, 236, 167 },
    [3]u8{ 39, 238, 164 }, [3]u8{ 42, 239, 161 }, [3]u8{ 44, 240, 158 },  [3]u8{ 47, 241, 155 },
    [3]u8{ 50, 242, 152 }, [3]u8{ 53, 243, 148 }, [3]u8{ 56, 244, 145 },  [3]u8{ 60, 245, 142 },
    [3]u8{ 63, 246, 138 }, [3]u8{ 67, 247, 135 }, [3]u8{ 70, 248, 132 },  [3]u8{ 74, 248, 128 },
    [3]u8{ 78, 249, 125 }, [3]u8{ 82, 250, 122 }, [3]u8{ 85, 250, 118 },  [3]u8{ 89, 251, 115 },
    [3]u8{ 93, 252, 111 }, [3]u8{ 97, 252, 108 }, [3]u8{ 101, 253, 105 }, [3]u8{ 105, 253, 102 },
    [3]u8{ 109, 254, 98 }, [3]u8{ 113, 254, 95 }, [3]u8{ 117, 254, 92 },  [3]u8{ 121, 254, 89 },
    [3]u8{ 125, 255, 86 }, [3]u8{ 128, 255, 83 }, [3]u8{ 132, 255, 81 },  [3]u8{ 136, 255, 78 },
    [3]u8{ 139, 255, 75 }, [3]u8{ 143, 255, 73 }, [3]u8{ 146, 255, 71 },  [3]u8{ 150, 254, 68 },
    [3]u8{ 153, 254, 66 }, [3]u8{ 156, 254, 64 }, [3]u8{ 159, 253, 63 },  [3]u8{ 161, 253, 61 },
    [3]u8{ 164, 252, 60 }, [3]u8{ 167, 252, 58 }, [3]u8{ 169, 251, 57 },  [3]u8{ 172, 251, 56 },
    [3]u8{ 175, 250, 55 }, [3]u8{ 177, 249, 54 }, [3]u8{ 180, 248, 54 },  [3]u8{ 183, 247, 53 },
    [3]u8{ 185, 246, 53 }, [3]u8{ 188, 245, 52 }, [3]u8{ 190, 244, 52 },  [3]u8{ 193, 243, 52 },
    [3]u8{ 195, 241, 52 }, [3]u8{ 198, 240, 52 }, [3]u8{ 200, 239, 52 },  [3]u8{ 203, 237, 52 },
    [3]u8{ 205, 236, 52 }, [3]u8{ 208, 234, 52 }, [3]u8{ 210, 233, 53 },  [3]u8{ 212, 231, 53 },
    [3]u8{ 215, 229, 53 }, [3]u8{ 217, 228, 54 }, [3]u8{ 219, 226, 54 },  [3]u8{ 221, 224, 55 },
    [3]u8{ 223, 223, 55 }, [3]u8{ 225, 221, 55 }, [3]u8{ 227, 219, 56 },  [3]u8{ 229, 217, 56 },
    [3]u8{ 231, 215, 57 }, [3]u8{ 233, 213, 57 }, [3]u8{ 235, 211, 57 },  [3]u8{ 236, 209, 58 },
    [3]u8{ 238, 207, 58 }, [3]u8{ 239, 205, 58 }, [3]u8{ 241, 203, 58 },  [3]u8{ 242, 201, 58 },
    [3]u8{ 244, 199, 58 }, [3]u8{ 245, 197, 58 }, [3]u8{ 246, 195, 58 },  [3]u8{ 247, 193, 58 },
    [3]u8{ 248, 190, 57 }, [3]u8{ 249, 188, 57 }, [3]u8{ 250, 186, 57 },  [3]u8{ 251, 184, 56 },
    [3]u8{ 251, 182, 55 }, [3]u8{ 252, 179, 54 }, [3]u8{ 252, 177, 54 },  [3]u8{ 253, 174, 53 },
    [3]u8{ 253, 172, 52 }, [3]u8{ 254, 169, 51 }, [3]u8{ 254, 167, 50 },  [3]u8{ 254, 164, 49 },
    [3]u8{ 254, 161, 48 }, [3]u8{ 254, 158, 47 }, [3]u8{ 254, 155, 45 },  [3]u8{ 254, 153, 44 },
    [3]u8{ 254, 150, 43 }, [3]u8{ 254, 147, 42 }, [3]u8{ 254, 144, 41 },  [3]u8{ 253, 141, 39 },
    [3]u8{ 253, 138, 38 }, [3]u8{ 252, 135, 37 }, [3]u8{ 252, 132, 35 },  [3]u8{ 251, 129, 34 },
    [3]u8{ 251, 126, 33 }, [3]u8{ 250, 123, 31 }, [3]u8{ 249, 120, 30 },  [3]u8{ 249, 117, 29 },
    [3]u8{ 248, 114, 28 }, [3]u8{ 247, 111, 26 }, [3]u8{ 246, 108, 25 },  [3]u8{ 245, 105, 24 },
    [3]u8{ 244, 102, 23 }, [3]u8{ 243, 99, 21 },  [3]u8{ 242, 96, 20 },   [3]u8{ 241, 93, 19 },
    [3]u8{ 240, 91, 18 },  [3]u8{ 239, 88, 17 },  [3]u8{ 237, 85, 16 },   [3]u8{ 236, 83, 15 },
    [3]u8{ 235, 80, 14 },  [3]u8{ 234, 78, 13 },  [3]u8{ 232, 75, 12 },   [3]u8{ 231, 73, 12 },
    [3]u8{ 229, 71, 11 },  [3]u8{ 228, 69, 10 },  [3]u8{ 226, 67, 10 },   [3]u8{ 225, 65, 9 },
    [3]u8{ 223, 63, 8 },   [3]u8{ 221, 61, 8 },   [3]u8{ 220, 59, 7 },    [3]u8{ 218, 57, 7 },
    [3]u8{ 216, 55, 6 },   [3]u8{ 214, 53, 6 },   [3]u8{ 212, 51, 5 },    [3]u8{ 210, 49, 5 },
    [3]u8{ 208, 47, 5 },   [3]u8{ 206, 45, 4 },   [3]u8{ 204, 43, 4 },    [3]u8{ 202, 42, 4 },
    [3]u8{ 200, 40, 3 },   [3]u8{ 197, 38, 3 },   [3]u8{ 195, 37, 3 },    [3]u8{ 193, 35, 2 },
    [3]u8{ 190, 33, 2 },   [3]u8{ 188, 32, 2 },   [3]u8{ 185, 30, 2 },    [3]u8{ 183, 29, 2 },
    [3]u8{ 180, 27, 1 },   [3]u8{ 178, 26, 1 },   [3]u8{ 175, 24, 1 },    [3]u8{ 172, 23, 1 },
    [3]u8{ 169, 22, 1 },   [3]u8{ 167, 20, 1 },   [3]u8{ 164, 19, 1 },    [3]u8{ 161, 18, 1 },
    [3]u8{ 158, 16, 1 },   [3]u8{ 155, 15, 1 },   [3]u8{ 152, 14, 1 },    [3]u8{ 149, 13, 1 },
    [3]u8{ 146, 11, 1 },   [3]u8{ 142, 10, 1 },   [3]u8{ 139, 9, 2 },     [3]u8{ 136, 8, 2 },
    [3]u8{ 133, 7, 2 },    [3]u8{ 129, 6, 2 },    [3]u8{ 126, 5, 2 },     [3]u8{ 122, 4, 3 },
};
