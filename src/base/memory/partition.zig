const std = @import("std");

pub fn partition(comptime T: type, data: []T, p: anytype) usize {
    var first: usize = data.len;
    for (data) |d, i| {
        if (!p.f(d)) {
            first = i;
            break;
        }
    }

    if (first == data.len) {
        return first;
    }

    var i = first + 1;
    while (i < data.len) : (i += 1) {
        if (p.f(data[i])) {
            std.mem.swap(T, &data[i], &data[first]);
            first += 1;
        }
    }

    return first;
}
