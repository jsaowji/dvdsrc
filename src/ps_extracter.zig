const std = @import("std");
const utils = @import("utils.zig");
const dsi = @import("dsi.zig");
const pci = @import("pci.zig");

const PTS_FLAG: u8 = 0b0010;
const PTSDTS_PTS_FLAG: u8 = 0b0011;
const PTSDTS_DTS_FLAG: u8 = 0b0001;

fn parse_pts(flag: u8, pts_bytesx: [5]u8) u32 {
    const pts_bytes = [_]u32{
        @as(u32, pts_bytesx[0]),
        @as(u32, pts_bytesx[1]),
        @as(u32, pts_bytesx[2]),
        @as(u32, pts_bytesx[3]),
        @as(u32, pts_bytesx[4]),
    };
    // 0010XXX1 XXXXXXXX XXXXXXX1 XXXXXXXX XXXXXXX1

    std.debug.assert(((pts_bytes[0] & 0b11110000) >> 4) == flag);

    std.debug.assert(((pts_bytes[0] & 0b00000001)) == 1);
    std.debug.assert(((pts_bytes[2] & 0b00000001)) == 1);
    std.debug.assert(((pts_bytes[4] & 0b00000001)) == 1);

    const p0 = (pts_bytes[0] & 0b1110) >> 1;
    const p1 = (pts_bytes[1] << 8) + (pts_bytes[2] & 0b11111110) >> 1;
    const p2 = (pts_bytes[3] << 8) + (pts_bytes[4] & 0b11111110) >> 1;

    const pts = p2 + (p1 << 15) + (p0 << 30);

    return pts;
}

pub const DummyWriteout = struct {
    const Self = @This();

    pub fn audioIndex(self: *const Self, idx: usize) bool {
        _ = self;
        _ = idx;
        return false;
    }

    pub fn writeAll(self: *const Self, buf: []u8) !void {
        _ = buf;
        _ = self;
    }
};

fn AudioFilterId(comptime WriterType: type) type {
    return struct {
        const Self = @This();

        inner: WriterType,
        id: usize,

        pub fn init(inner: WriterType, id: usize) Self {
            return .{
                .inner = inner,
                .id = id,
            };
        }

        pub fn audioIndex(self: *const Self, idx: usize) bool {
            if (self.id == idx) {
                return true;
            }
            return false;
        }

        pub fn writeAll(self: *const Self, buf: []u8) !void {
            try self.inner.writeAll(buf);
        }
    };
}

pub fn audioIdFilter(asd: anytype, id: usize) AudioFilterId(@TypeOf(asd)) {
    return AudioFilterId(@TypeOf(asd)).init(asd, id);
}

pub fn psExtracter(comptime allocator: anytype) !PsExtracter(@TypeOf(allocator)) {
    return PsExtracter(@TypeOf(allocator)).init(allocator);
}

pub fn PsExtracter(comptime AllocatorType: anytype) type {
    return struct {
        const Self = @This();
        buf: []u8,
        allocator: AllocatorType,
        got_pack: bool = false,
        got_dsi: bool = false,
        got_pci: bool = false,
        pci: pci.PCI = undefined,
        dsi: dsi.DSI = undefined,

        //inverse
        current_angles: u8 = 0,
        current_vobidcellid: u32 = 0,

        pub fn init(allocat: AllocatorType) !Self {
            return Self{
                .buf = try allocat.alloc(u8, 1024),
                .allocator = allocat,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buf);
        }

        pub fn demuxOne(self: *Self, read_in: anytype, m2v_write_out: anytype, ac3_write_out: anytype, lpcm_write_out: anytype) !void {
            const st = try utils.checkStartCode(read_in);

            switch (st) {
                //pack header
                0xBA => {
                    //https://dvd.sourceforge.net/dvdinfo/packhdr.html
                    try read_in.skipBytes(10, .{});
                    self.got_pack = true;
                },
                //private stream 2
                0xBF => {
                    var len = try read_in.readIntBig(u16);

                    if (len > self.buf.len) {
                        self.allocator.free(self.buf);
                        self.buf = try self.allocator.alloc(u8, len);
                    }
                    const data_read = try read_in.readAtLeast(self.buf[0..len], len);

                    if (0 == self.buf[0]) {
                        self.pci = try pci.parsePCI(self.buf[1 .. data_read - 1]);
                        std.debug.assert(self.got_pci == false);
                        self.got_pci = true;
                    } else if (1 == self.buf[0]) {
                        self.dsi = try dsi.parseDSI(self.buf[1 .. data_read - 1]);
                        std.debug.assert(self.got_dsi == false);
                        self.got_dsi = true;
                        //   std.debug.print("debug VOBID CELID {} {}\n", .{ self.dsi.vobu_vob_idn, self.dsi.vobu_c_idn });
                    } else {
                        std.debug.print("GOT AD {}\n", .{self.buf[0]});
                        std.debug.assert(false);
                    }

                    if (self.got_pack and self.got_dsi and self.got_pci) {
                        self.current_vobidcellid = (@as(u32, @intCast(self.dsi.vobu_vob_idn)) << 8) + @as(u32, @intCast(self.dsi.vobu_c_idn));

                        var a: u8 = 0;
                        for (0..8) |i| {
                            var l: u8 = 0;
                            if (self.pci.nsml_agl[i].dsta != 0) {
                                l = 1;
                            }
                            a |= l << @as(u3, @intCast(i));
                        }
                        var b: u8 = 0;
                        for (0..8) |i| {
                            var l: u8 = 0;
                            if (self.dsi.sml_agl[i].dsta != 0) {
                                l = 1;
                            }

                            a |= l << @as(u3, @intCast(i));
                        }

                        const has_pci_angels =
                            a != 0;

                        const has_dsi_angels =
                            b != 0;
                        if (has_pci_angels) {
                            std.debug.assert(has_dsi_angels == false);
                        }
                        if (has_dsi_angels) {
                            std.debug.assert(has_pci_angels == false);
                        }
                        self.current_angles = @max(a, b);

                        self.got_pack = false;
                        self.got_dsi = false;
                        self.got_pci = false;
                    }
                },
                //another private stream
                0xBD => {
                    var len = try read_in.readIntBig(u16);

                    if (len > self.buf.len) {
                        self.allocator.free(self.buf);
                        self.buf = try self.allocator.alloc(u8, len);
                    }
                    const data_read = try read_in.readAtLeast(self.buf[0..len], len);
                    std.debug.assert(data_read == len);
                    const hdr_data_len = self.buf[2];
                    const inner_data = self.buf[3 + hdr_data_len .. len];

                    const pts_dts_ind = (self.buf[1] & 0b11000000) >> 6;

                    var pts: ?u32 = null;
                    var dts: ?u32 = null;

                    if (pts_dts_ind == 0b00) {
                        //nothing
                    } else if (pts_dts_ind == 0b10) {
                        //pts only
                        const pts_bytesx = self.buf[3 .. 3 + 5];
                        pts = parse_pts(PTS_FLAG, pts_bytesx.*);
                    } else if (pts_dts_ind == 0b11) {
                        //pts dts

                        const pts_bytesx = self.buf[3 .. 3 + 5];
                        const dts_bytesx = self.buf[3 + 5 .. 3 + 5 + 5];
                        pts = parse_pts(PTSDTS_PTS_FLAG, pts_bytesx.*);
                        dts = parse_pts(PTSDTS_PTS_FLAG, dts_bytesx.*);
                    } else {
                        unreachable;
                    }

                    // std.debug.print("framecnt {} \n", .{inner_data[1]});

                    //const framecnt = inner_data[1];
                    //                    const first_acc_unit = (@as(u16, inner_data[2]) << 8) + inner_data[3];

                    const inner_id = inner_data[0];
                    if (inner_id >= 0x80 and inner_id <= 0x87) {
                        const idx = inner_id - 0x80;
                        if (ac3_write_out.audioIndex(idx)) {
                            try ac3_write_out.writeAll(inner_data[1 + 3 ..]);
                        }
                    }
                    if (inner_id >= 0xA0 and inner_id <= 0xA7) {
                        const idx = inner_id - 0xA0;
                        if (lpcm_write_out.audioIndex(idx)) {
                            try lpcm_write_out.writeAll(inner_data[1 + 3 ..]);
                        }
                    }
                },
                //other possible pes streams that aren't video
                0xBB, 0xBE => {
                    const len = try read_in.readIntBig(u16);
                    _ = try read_in.skipBytes(len, .{});
                },
                //video
                0xE0 => {
                    var len = try read_in.readIntBig(u16);

                    if (len > self.buf.len) {
                        self.allocator.free(self.buf);
                        self.buf = try self.allocator.alloc(u8, len);
                    }
                    const data_read = try read_in.readAtLeast(self.buf[0..len], len);
                    std.debug.assert(data_read == len);

                    const hdr_data_len = self.buf[2];
                    const mpeg2_data = self.buf[3 + hdr_data_len .. len];

                    _ = try m2v_write_out.writeAll(mpeg2_data);
                },
                else => {
                    unreachable;
                },
            }
        }
    };
}
