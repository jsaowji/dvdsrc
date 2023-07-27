const std = @import("std");

const dvdread = @import("manual_dvdread.zig");

export fn dummy_loggerfn(a: ?*anyopaque, b: dvdread.dvd_logger_level_t, c: [*c]const u8, d: [*c]dvdread.struct___va_list_tag) void {
    _ = a;
    _ = b;
    _ = c;
    _ = d;
}
pub const dummy_logger = dvdread.dvd_logger_cb{
    .pf_log = &dummy_loggerfn,
    //.pf_log = null,
};

pub const DVD_BLOCK_SIZE: u16 = @intCast(dvdread.DVD_VIDEO_LB_LEN);

/// Reads blocks of size 2048 from a menu/titlevob dvd_file
pub const DvdReader = struct {
    file: *dvdread.dvd_file_t,
    block_cnt: u64,

    offset: u64,

    buf_block: u64,
    buf: [DVD_BLOCK_SIZE]u8 = undefined,

    const Self = @This();
    pub const Error = error{OutOfBoundsRead};
    pub const Reader = std.io.Reader(*Self, Error, read);

    pub fn init(file: *dvdread.dvd_file_t) Self {
        return Self{
            .file = @ptrCast(file),
            .block_cnt = @as(u64, @intCast(dvdread.DVDFileSize(file))),
            .offset = 0,

            .buf_block = (1 << 63) - 1,
            .buf = undefined,
        };
    }

    pub fn read(self: *Self, dest: []u8) !usize {
        const block = self.offset / DVD_BLOCK_SIZE;
        const block_offset = self.offset % DVD_BLOCK_SIZE;

        if (block >= self.block_cnt) {
            return Error.OutOfBoundsRead;
        }

        if (self.buf_block != block) {
            _ = dvdread.DVDReadBlocks(self.file, @as(c_int, @intCast(block)), @as(usize, @intCast(1)), &self.buf);

            self.buf_block = block;
        }
        const read_this_time = @min(dest.len, dvdread.DVD_VIDEO_LB_LEN - block_offset);

        @memcpy(dest[0..read_this_time], self.buf[block_offset .. block_offset + read_this_time]);
        self.offset += read_this_time;

        return read_this_time;
    }

    pub fn seekBlock(self: *Self, block: u64) void {
        std.debug.assert(block < self.block_cnt);
        self.offset = block * DVD_BLOCK_SIZE;
    }

    pub fn seekTo(self: *Self, bytes: u64) void {
        self.seekBlock(bytes / DVD_BLOCK_SIZE);
        self.offset += bytes % DVD_BLOCK_SIZE;
        std.debug.assert(self.offset == bytes);
    }

    pub fn reader(self: *Self) Reader {
        return .{ .context = self };
    }
};
