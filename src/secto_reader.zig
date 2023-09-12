const dvdread = @import("./manual_dvdread.zig");
const std = @import("std");
const vs = @import("../bindings/vapoursynth.zig");

pub const SectoReader = struct {
    dvdfile: ?*dvdread.dvd_file_t,
    buffer: [2048]u8 = undefined,
    buffer_left: usize = 0,
    sector_i: usize = 0,

    sector_cnt: usize,
    sectors: []u32,

    block_cnt: u64,

    const Self = @This();

    pub const Error = error{AllRead};
    pub const Reader = std.io.Reader(*Self, Error, read);

    pub fn init(sector_cnt: usize, dvdfile: ?*dvdread.dvd_file_t) Self {
        var self: Self = .{
            .dvdfile = dvdfile,
            .sector_cnt = @as(usize, @intCast(sector_cnt)),
            .sectors = std.heap.c_allocator.alloc(u32, sector_cnt) catch unreachable,
            .block_cnt = sector_cnt,
        };

        return self;
    }
    pub fn deinit(self: *Self) void {
        dvdread.DVDCloseFile(self.dvdfile);
        std.heap.c_allocator.free(self.sectors);
    }

    pub fn seekTo(self: *Self, dst: u64) void {
        //  std.debug.print("\n\n\nsecto seek {}\n\n\n\n", .{dst});
        self.buffer_left = 0;
        self.sector_i = (dst / 2048);
        self.reader().skipBytes(dst % 2048, .{}) catch unreachable;
    }

    pub fn read(self: *Self, dest: []u8) !usize {
        //   std.debug.print("read {}\n", .{dest.len});
        if (self.buffer_left == 0) {
            if (self.sector_i == self.sector_cnt) return Error.AllRead;
            //const sector = self.vsapi.*.mapGetInt.?(self.in, "sectors", @as(c_int, @intCast(self.sector_i)), 0);
            const sector = self.sectors[self.sector_i];
            _ = dvdread.DVDReadBlocks(self.dvdfile, @as(c_int, @intCast(sector)), 1, &self.buffer);
            self.buffer_left = 2048;
            self.sector_i += 1;
        }
        var read_size = @min(self.buffer_left, dest.len);
        const start_ptr = 2048 - self.buffer_left;
        //std.debug.print("start_ptr {} read_size {} self.buffer_left {} dest {}\n", .{ start_ptr, read_size, self.buffer_left, dest.len });
        @memcpy(dest[0..read_size], self.buffer[start_ptr .. start_ptr + read_size]);
        self.buffer_left -= read_size;
        return read_size;
    }

    pub fn reader(self: *Self) Reader {
        return .{ .context = self };
    }
};
