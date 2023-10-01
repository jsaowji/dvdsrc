const std = @import("std");

pub const PCI = struct { nv_pck_lbn: u32, vobu_s_ptm: u32, nsml_agl: [8]struct {
    dsta: u32,
} };

fn seekToReadInt(bfr: anytype, offset: u64, comptime T: type) T {
    bfr.seekTo(offset) catch unreachable;
    return bfr.reader().readIntBig(T) catch unreachable;
}

pub fn parsePCI(buffer: []u8) !PCI {
    var pci: PCI = undefined;

    var bfr = std.io.fixedBufferStream(buffer);
    pci.nv_pck_lbn = seekToReadInt(&bfr, 0x0, u32);
    pci.vobu_s_ptm = seekToReadInt(&bfr, 0x00C, u32);
    for (0..8) |angle_index| {
        pci.nsml_agl[angle_index] = .{
            .dsta = seekToReadInt(&bfr, 0x03c + (4 * angle_index), u32),
        };
    }

    return pci;
}
