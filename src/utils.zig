const std = @import("std");

const mpeg2 = @import("./bindings/mpeg2.zig");

pub const is_windows = @import("builtin").os.tag == .windows;

const CheckStartCodeError = error{
    not4,
    not001,
};

pub fn checkStartCode(r: anytype) !u8 {
    var buf: [4]u8 = undefined;
    var asd = try r.readAtLeast(&buf, 4);
    if (asd != 4) {
        std.debug.print("only got {}\n", .{asd});
        return CheckStartCodeError.not4;
    }

    if ((buf[0] != 0) or (buf[1] != 0) or (buf[2] != 1)) {
        std.debug.print("wanted 0 0 1 got {X} {X} {X}\n", .{ buf[0], buf[1], buf[2] });
        return CheckStartCodeError.not001;
    }

    return buf[3];
}

pub fn mpeg2decStateToString(s: c_uint) [*c]const u8 {
    var name: [*c]const u8 = undefined;
    switch (s) {
        mpeg2.STATE_BUFFER => name = "STATE_BUFFER",
        mpeg2.STATE_SEQUENCE => name = "STATE_SEQUENCE",
        mpeg2.STATE_SEQUENCE_REPEATED => name = "STATE_SEQUENCE_REPEATED",
        mpeg2.STATE_GOP => name = "STATE_GOP",
        mpeg2.STATE_PICTURE => name = "STATE_PICTURE",
        mpeg2.STATE_SLICE_1ST => name = "STATE_SLICE_1ST",
        mpeg2.STATE_PICTURE_2ND => name = "STATE_PICTURE_2ND",
        mpeg2.STATE_SLICE => name = "STATE_SLICE",
        mpeg2.STATE_END => name = "STATE_END",
        mpeg2.STATE_INVALID => name = "STATE_INVALID",
        mpeg2.STATE_INVALID_END => name = "STATE_INVALID_END",
        mpeg2.STATE_SEQUENCE_MODIFIED => name = "STATE_SEQUENCE_MODIFIED",
        else => unreachable,
    }

    return name;
}

pub fn mpeg2decPictureflagToString(flag: u32) [*c]const u8 {
    var pict: *const [1:0]u8 = undefined;
    switch (flag & mpeg2.PIC_MASK_CODING_TYPE) {
        mpeg2.PIC_FLAG_CODING_TYPE_I => pict = "I",
        mpeg2.PIC_FLAG_CODING_TYPE_B => pict = "B",
        mpeg2.PIC_FLAG_CODING_TYPE_P => pict = "P",
        mpeg2.PIC_FLAG_CODING_TYPE_D => pict = "D",
        else => unreachable,
    }
    return pict;
}

pub fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    const should = false;
    if (should) {
        std.debug.print(fmt, args);
    }
}
