pub fn lowerBound(comptime T: type, data: []const T, value: T) usize {
    var first: usize = 0;
    var count = data.len;

    while (count > 0) {
        const step = count / 2;
        const it = first + step;

        if (data[it] < value) {
            first = it + 1;
            count -= step + 1;
        } else {
            count = step;
        }
    }

    return first;
}

pub fn lowerBoundFn(
    comptime T: type,
    data: []const T,
    value: T,
    context: anytype,
    comptime lessThan: fn (context: @TypeOf(context), a: T, b: T) bool,
) usize {
    var first: usize = 0;
    var count = data.len;

    while (count > 0) {
        const step = count / 2;
        const it = first + step;

        if (lessThan(context, data[it], value)) {
            first = it + 1;
            count -= step + 1;
        } else {
            count = step;
        }
    }

    return first;
}

pub fn upperBound(comptime T: type, data: []const T, value: T) usize {
    var first: usize = 0;
    var count = data.len;

    while (count > 0) {
        const step = count / 2;
        const it = first + step;

        if (!(value < it)) {
            first = it + 1;
            count -= step + 1;
        } else {
            count = step;
        }
    }

    return first;
}

pub fn equalRange(comptime T: type, data: []const T, value: T) [2]usize {
    return .{ lowerBound(data, value), upperBound(data, value) };
}
