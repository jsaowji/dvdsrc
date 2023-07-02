const std = @import("std");
const utils = @import("utils.zig");
const dsi = @import("dsi.zig");
const pci = @import("pci.zig");

pub fn psM2vExtracter(comptime allocator: anytype) !PsM2vExtracter(@TypeOf(allocator)) {
    return PsM2vExtracter(@TypeOf(allocator)).init(allocator);
}

pub fn PsM2vExtracter(comptime AllocatorType: anytype) type {
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
        current_vobid: u16 = 0,

        pub fn init(allocat: AllocatorType) !Self {
            return Self{
                .buf = try allocat.alloc(u8, 1024),
                .allocator = allocat,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buf);
        }

        pub fn demuxOne(self: *Self, read_in: anytype, write_out: anytype) !void {
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
                    } else {
                        std.debug.print("GOT AD {}\n", .{self.buf[0]});
                        std.debug.assert(false);
                    }

                    if (self.got_pack and self.got_dsi and self.got_pci) {
                        self.current_vobid = self.dsi.vobu_vob_idn;

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
                //other possible pes streams that aren't video
                0xBD, 0xBB, 0xBE => {
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

                    _ = try write_out.writeAll(mpeg2_data);
                },
                else => {
                    unreachable;
                },
            }
        }
    };
}
