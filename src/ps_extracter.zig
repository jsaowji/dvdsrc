const std = @import("std");
const utils = @import("utils.zig");
const dsi = @import("dsi.zig");
const pci = @import("pci.zig");

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

                    // std.debug.print("framecnt {} \n", .{inner_data[1]});

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
