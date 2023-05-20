const std = @import("std");
const utils = @import("utils.zig");

pub fn psM2vExtracter(comptime allocator: anytype) !PsM2vExtracter(@TypeOf(allocator)) {
    return PsM2vExtracter(@TypeOf(allocator)).init(allocator);
}

pub fn PsM2vExtracter(comptime AllocatorType: anytype) type {
    return struct {
        const Self = @This();
        buf: []u8,
        allocator: AllocatorType,

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
                },
                //other possible pes streams that aren't video
                0xBF, 0xBD, 0xBB, 0xBE => {
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
