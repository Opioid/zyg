const math = @import("base").math;
const Vec2i = math.Vec2i;

pub fn gilbert_d2xy(idx: i32, dim: Vec2i) Vec2i {
    const w = dim[0];
    const h = dim[1];

    if (w >= h) {
        return gilbert_d2xy_r(idx, 0, 0, 0, w, 0, 0, h);
    }

    return gilbert_d2xy_r(idx, 0, 0, 0, 0, h, w, 0);
}

fn gilbert_d2xy_r(dst_idx: i32, cur_idx: i32, x: i32, y: i32, ax: i32, ay: i32, bx: i32, by: i32) Vec2i {
    const w = @abs(ax + ay);
    const h = @abs(bx + by);

    // unit major direction
    const dax = sgn(ax);
    const day = sgn(ay);

    // unit orthogonal direction
    const dbx = sgn(bx);
    const dby = sgn(by);

    const di = dst_idx - cur_idx;

    if (h == 1) {
        return .{ x + dax * di, y + day * di };
    }

    if (w == 1) {
        return .{ x + dbx * di, y + dby * di };
    }

    // floor function
    var ax2 = ax >> 1;
    var ay2 = ay >> 1;
    var bx2 = bx >> 1;
    var by2 = by >> 1;

    const w2 = @abs(ax2 + ay2);
    const h2 = @abs(bx2 + by2);

    if ((2 * w) > (3 * h)) {
        if ((w2 & 1) != 0 and (w > 2)) {
            // prefer even steps
            ax2 += dax;
            ay2 += day;
        }

        // long case: split in two parts only
        const nxt_idx = cur_idx + @as(i32, @intCast(@abs((ax2 + ay2) * (bx + by))));
        if ((cur_idx <= dst_idx) and (dst_idx < nxt_idx)) {
            return gilbert_d2xy_r(dst_idx, cur_idx, x, y, ax2, ay2, bx, by);
        }

        return gilbert_d2xy_r(dst_idx, nxt_idx, x + ax2, y + ay2, ax - ax2, ay - ay2, bx, by);
    }

    if ((h2 & 1) != 0 and (h > 2)) {
        // prefer even steps
        bx2 += dbx;
        by2 += dby;
    }

    // standard case: one step up, one long horizontal, one step down
    const nxt_idx = cur_idx + @as(i32, @intCast(@abs((bx2 + by2) * (ax2 + ay2))));
    if ((cur_idx <= dst_idx) and (dst_idx < nxt_idx)) {
        return gilbert_d2xy_r(dst_idx, cur_idx, x, y, bx2, by2, ax2, ay2);
    }

    const nxtnxt_idx = nxt_idx + @as(i32, @intCast(@abs((ax + ay) * ((bx - bx2) + (by - by2)))));
    if ((nxt_idx <= dst_idx) and (dst_idx < nxtnxt_idx)) {
        return gilbert_d2xy_r(dst_idx, nxt_idx, x + bx2, y + by2, ax, ay, bx - bx2, by - by2);
    }

    const xres = x + (ax - dax) + (bx2 - dbx);
    const yres = y + (ay - day) + (by2 - dby);
    return gilbert_d2xy_r(dst_idx, nxtnxt_idx, xres, yres, -bx2, -by2, -(ax - ax2), -(ay - ay2));
}

inline fn sgn(x: i32) i32 {
    return @as(i32, @intFromBool(0 < x)) - @as(i32, @intFromBool(x < 0));
}
