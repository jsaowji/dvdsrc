const std = @import("std");
const mpeg2 = @import("bindings/mpeg2.zig");

pub const LPCMIndex = struct {
    const Self = @This();

    config_bytes: [2]u8,
    frame_sizes: std.ArrayList(u16),

    pub fn init() Self {
        return .{
            .config_bytes = [_]u8{ 0x01, 0x02 },
            .frame_sizes = std.ArrayList(u16).init(std.heap.c_allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.frame_sizes.deinit();
    }

    pub fn writeOut(self: *const Self, r: anytype) !void {
        try r.writeAll(&self.config_bytes);
        try r.writeIntLittle(u64, self.frame_sizes.items.len);
        for (self.frame_sizes.items) |a| {
            try r.writeIntLittle(u16, a);
        }
    }

    pub fn readIn(r: anytype) !Self {
        var self: Self = undefined;
        _ = try r.readAll(&self.config_bytes);

        const framecnt = try r.readIntLittle(u64);

        self.frame_sizes = try std.ArrayList(u16).initCapacity(std.heap.c_allocator, framecnt);
        for (0..framecnt) |_| {
            try self.frame_sizes.append(try r.readIntLittle(u16));
        }

        return self;
    }
};
