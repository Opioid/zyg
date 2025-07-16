pub fn countFrames(shutter_duration: u64, animation_frame_duration: u64) u32 {
    const a: u32 = @max(@as(u32, @intCast(shutter_duration / animation_frame_duration)), 1);
    const b: u32 = if (matching(shutter_duration, animation_frame_duration)) 0 else 1;
    const c: u32 = if (matching(shutter_duration, animation_frame_duration)) 0 else 1;

    return a + b + c;
}

fn matching(a: u64, b: u64) bool {
    return 0 == (if (a > b) a % b else (if (0 == a) 0 else b % a));
}

pub const Frame = struct {
    f: u32,
    w: f32,
};

pub fn frameAt(time: u64, frame_duration: u64, start_frame: u64) Frame {
    const frame_start = start_frame * frame_duration;

    const i = (time - frame_start) / frame_duration;
    const a_time = frame_start + i * frame_duration;
    const delta = time - a_time;

    const t: f32 = @floatCast(@as(f64, @floatFromInt(delta)) / @as(f64, @floatFromInt(frame_duration)));

    return .{ .f = @intCast(i), .w = t };
}
