const std = @import("std");

pub fn partition(
    comptime T: type,
    data: []T,
    context: anytype,
    comptime lessThan: fn (context: @TypeOf(context), x: T) bool,
) usize {
    var first: usize = data.len;
    for (data) |d, i| {
        if (!lessThan(context, d)) {
            first = i;
            break;
        }
    }

    if (first == data.len) {
        return first;
    }

    var i = first + 1;
    while (i < data.len) : (i += 1) {
        if (lessThan(context, data[i])) {
            std.mem.swap(T, &data[i], &data[first]);
            first += 1;
        }
    }

    return first;
}
