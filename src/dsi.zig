const std = @import("std");

pub const DSI = struct {
    nv_pck_lbn: u32,
    vobu_vob_idn: u16,
    vobu_c_idn: u8,
    ilvu: struct {
        raw: u16,
        preu: bool,
        ilvu: bool,
        unitstart: bool,
        unitend: bool,
        fn fillBitflags(self: *@This()) void {
            self.preu = (self.raw & (1 << 15)) != 0;
            self.ilvu = (self.raw & (1 << 14)) != 0;
            self.unitstart = (self.raw & (1 << 13)) != 0;
            self.unitend = (self.raw & (1 << 12)) != 0;
        }
    },
    sml_agl: [8]struct {
        dsta: u32,
        sz: u16,
    },
};

fn seekToReadInt(bfr: anytype, offset: u64, comptime T: type) T {
    bfr.seekTo(offset) catch unreachable;
    return bfr.reader().readIntBig(T) catch unreachable;
}

pub fn parseDSI(buffer: []u8) !DSI {
    var dsi: DSI = undefined;

    var bfr = std.io.fixedBufferStream(buffer);

    dsi.nv_pck_lbn = seekToReadInt(&bfr, 0x0, u32);
    dsi.ilvu.raw = seekToReadInt(&bfr, 0x20, u16);
    dsi.ilvu.fillBitflags();
    dsi.vobu_c_idn = seekToReadInt(&bfr, 0x1B, u8);
    dsi.vobu_vob_idn = seekToReadInt(&bfr, 0x18, u16);

    for (0..8) |angle_index| {
        dsi.sml_agl[angle_index] = .{
            .dsta = seekToReadInt(&bfr, 0xB4 + (6 * angle_index), u32),
            .sz = seekToReadInt(&bfr, 0xB4 + (6 * angle_index), u16),
        };
    }
    return dsi;
}
