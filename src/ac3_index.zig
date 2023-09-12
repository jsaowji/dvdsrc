const std = @import("std");
const mpeg2 = @import("bindings/mpeg2.zig");

pub const AC3Index = struct {
    const Self = @This();
    flags: u32 = 0,
    sample_rate: u32 = 0,

    frame_sizes: std.ArrayList(u16),

    pub fn init() Self {
        var frame_sizes = std.ArrayList(u16).init(std.heap.c_allocator);
        return .{
            .frame_sizes = frame_sizes,
        };
    }

    pub fn deinit(self: *Self) void {
        self.frame_sizes.deinit();
    }

    pub fn writeOut(self: *const Self, r: anytype) !void {
        var bw = std.io.bitWriter(std.builtin.Endian.Little, r);
        try bw.writeBits(self.flags, 32);
        try bw.writeBits(self.sample_rate, 32);
        try bw.writeBits(self.frame_sizes.items.len, 64);

        for (self.frame_sizes.items) |a| {
            try bw.writeBits(a, 16);
        }

        try bw.flushBits();
    }

    pub fn readIn(r: anytype) !Self {
        var self: Self = undefined;

        var br = std.io.bitReader(std.builtin.Endian.Little, r);

        self.flags = try br.readBitsNoEof(u32, 32);
        self.sample_rate = try br.readBitsNoEof(u32, 32);
        const framecnt = try br.readBitsNoEof(u64, 64);

        self.frame_sizes = try std.ArrayList(u16).initCapacity(std.heap.c_allocator, framecnt);
        for (0..framecnt) |_| {
            try self.frame_sizes.append(try br.readBitsNoEof(u16, 16));
        }

        return self;
    }
};
