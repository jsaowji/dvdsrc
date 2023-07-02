const std = @import("std");

pub const AddrType = u64;

pub const IndexEntry = struct {
    /// where to seek
    in_start: AddrType,
    /// how much data you get when decoding
    size: u32,
    /// where your supposed to end when you decoded size amount of m2v (currently unused)
    in_end: AddrType,

    //calculated on readIn
    out_pos: u64,
};

/// Mpeg program stream index
pub const PsIndex = struct {
    const Self = @This();

    indexs: std.ArrayList(IndexEntry) = undefined,
    current_size: u64 = 0,

    pub fn deinit(self: *Self) void {
        self.indexs.deinit();
    }

    pub fn writeOut(self: *Self, r: anytype) !void {
        try r.writeIntLittle(u64, self.indexs.items.len);
        for (self.indexs.items) |e| {
            try r.writeIntLittle(AddrType, e.in_start);
            try r.writeIntLittle(u32, e.size);
            try r.writeIntLittle(AddrType, e.in_end);
        }
    }

    pub fn readIn(r: anytype) !Self {
        const cnt = try r.readIntLittle(u64);
        var ini = Self{};

        ini.indexs = try std.ArrayList(IndexEntry).initCapacity(std.heap.c_allocator, cnt);

        var i: usize = 0;

        var bytes_sz: u64 = 0;
        while (i < cnt) {
            const entr = try ini.indexs.addOne();

            entr.in_start = try r.readIntLittle(AddrType);
            entr.size = try r.readIntLittle(u32);
            entr.in_end = try r.readIntLittle(AddrType);

            entr.out_pos = bytes_sz;
            bytes_sz += entr.size;
            i += 1;
        }
        ini.current_size = cnt;
        return ini;
    }

    pub fn add(self: *Self, in_start: u64, in_end: u64, size: u32) !void {
        const one = try self.indexs.addOne();
        one.* = IndexEntry{
            .in_start = @intCast(in_start),
            .in_end = in_end,
            .size = size,
            .out_pos = self.current_size,
        };
        self.current_size += size;
    }
};
