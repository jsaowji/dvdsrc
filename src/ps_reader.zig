const std = @import("std");

const ps_index = @import("ps_index.zig");
const ps_extracter = @import("ps_extracter.zig");

pub const OutType = enum {
    Video,
    AC3,
    LPCM,
};

pub const OutInfo = union(OutType) {
    Video,
    AC3: usize,
    LPCM: usize,
};

pub fn psReader(comptime InnerReaderType: type) type {
    return struct {
        offset: u64 = 0,

        current_index: usize = 0,
        ps_index: ps_index.PsIndex = undefined,
        inner: InnerReaderType,

        buffed_index: ?usize = null,
        buf: []u8,
        outtype: OutInfo,

        const Self = @This();
        const Error = error{OutOfBnds};

        pub const Reader = std.io.Reader(*Self, Error, read);

        pub fn init(a: ps_index.PsIndex, inner: InnerReaderType, outtype: OutInfo) !Self {
            return Self{
                .inner = inner,
                .ps_index = a,
                .buf = try std.heap.c_allocator.alloc(u8, 1024 * 1024 * 50),
                .outtype = outtype,
            };
        }

        pub fn deinit(self: *Self) void {
            self.ps_index.deinit();
        }
        //TODO: fix out of bounds reads here
        pub fn read(self: *Self, dest: []u8) !usize {
            if (self.current_index >= self.ps_index.indexs.items.len) {
                //return Error.OutOfBnds;
                return 0;
            }
            var crnt = self.ps_index.indexs.items[self.current_index];

            std.debug.assert(self.offset >= crnt.out_pos);
            std.debug.assert(self.offset < crnt.out_pos + crnt.size);

            var crnt_offset = self.offset - crnt.out_pos;
            std.debug.assert(crnt_offset < crnt.size);

            const rd_size = @min(crnt.size - crnt_offset, dest.len);

            var rebuf = true;
            if (self.buffed_index) |a| {
                rebuf = self.current_index != a;
            }

            if (rebuf) {
                self.inner.seekTo(crnt.in_start);

                var deco = ps_extracter.psExtracter(std.heap.c_allocator) catch unreachable;
                defer deco.deinit();

                var fb = std.io.fixedBufferStream(self.buf);

                while (fb.getPos() catch unreachable < crnt.size) {
                    switch (self.outtype) {
                        OutType.Video => {
                            deco.demuxOne(self.inner.reader(), fb.writer(), ps_extracter.DummyWriteout{}, ps_extracter.DummyWriteout{}) catch break;
                        },
                        OutType.AC3 => |e| {
                            deco.demuxOne(self.inner.reader(), ps_extracter.DummyWriteout{}, ps_extracter.audioIdFilter(fb.writer(), e), ps_extracter.DummyWriteout{}) catch break;
                        },
                        OutType.LPCM => |e| {
                            deco.demuxOne(
                                self.inner.reader(),
                                ps_extracter.DummyWriteout{},
                                ps_extracter.DummyWriteout{},
                                ps_extracter.audioIdFilter(fb.writer(), e),
                            ) catch break;
                        },
                    }
                }
            }
            @memcpy(dest[0..rd_size], self.buf[crnt_offset .. crnt_offset + rd_size]);

            self.offset += rd_size;
            crnt_offset = self.offset - crnt.out_pos;
            if (crnt_offset >= crnt.size) {
                std.debug.assert(crnt_offset == crnt.size);
                self.current_index += 1;
            }
            return rd_size;
        }

        pub fn seekTo(self: *Self, dst: u64) !void {
            self.offset = dst;
            var cummulative_size: u64 = 0;
            var i: usize = 0;
            for (self.ps_index.indexs.items) |itm| {
                if (dst >= cummulative_size and dst < cummulative_size + itm.size) {
                    self.current_index = i;
                    break;
                }
                cummulative_size += itm.size;
                i += 1;
            }
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}
