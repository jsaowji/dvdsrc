const std = @import("std");

const dvdread = @import("bindings/dvdread.zig");

pub const DVD_BLOCK_SIZE: u16 = @intCast(u16, dvdread.DVD_VIDEO_LB_LEN);

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

    pub fn read(self: *Self, dest: []u8) !usize {
        const block = self.offset / DVD_BLOCK_SIZE;
        const block_offset = self.offset % DVD_BLOCK_SIZE;

        if (block >= self.block_cnt) {
            return Error.OutOfBoundsRead;
        }

        if (self.buf_block != block) {
            _ = dvdread.DVDReadBlocks(self.file, @intCast(c_int, block), @intCast(usize, 1), &self.buf);

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

pub fn dvdReader(file: ?*dvdread.dvd_file_t) DvdReader {
    return DvdReader{
        .file = @ptrCast(*dvdread.dvd_file_t, file),
        .block_cnt = @intCast(u64, dvdread.DVDFileSize(file)),
        .offset = 0,

        .buf_block = (1 << 63) - 1,
        .buf = undefined,
    };
}
