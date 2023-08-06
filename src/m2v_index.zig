const std = @import("std");
const mpeg2 = @import("bindings/mpeg2.zig");

pub fn writeoutSequence(self: *const mpeg2.mpeg2_sequence_t, ww: anytype) !void {
    try ww.writeIntLittle(c_uint, self.width);
    try ww.writeIntLittle(c_uint, self.height);
    try ww.writeIntLittle(c_uint, self.chroma_width);
    try ww.writeIntLittle(c_uint, self.chroma_height);
    try ww.writeIntLittle(c_uint, self.byte_rate);
    try ww.writeIntLittle(c_uint, self.vbv_buffer_size);
    try ww.writeIntLittle(u32, self.flags);
    try ww.writeIntLittle(c_uint, self.picture_width);
    try ww.writeIntLittle(c_uint, self.picture_height);
    try ww.writeIntLittle(c_uint, self.display_width);
    try ww.writeIntLittle(c_uint, self.display_height);
    try ww.writeIntLittle(c_uint, self.pixel_width);
    try ww.writeIntLittle(c_uint, self.pixel_height);
    try ww.writeIntLittle(c_uint, self.frame_period);
    try ww.writeIntLittle(u8, self.profile_level_id);
    try ww.writeIntLittle(u8, self.colour_primaries);
    try ww.writeIntLittle(u8, self.transfer_characteristics);
    try ww.writeIntLittle(u8, self.matrix_coefficients);
}

pub fn readinSequence(ww: anytype) !mpeg2.mpeg2_sequence_t {
    var self: mpeg2.mpeg2_sequence_t = undefined;
    self.width = try ww.readIntLittle(c_uint);
    self.height = try ww.readIntLittle(c_uint);
    self.chroma_width = try ww.readIntLittle(c_uint);
    self.chroma_height = try ww.readIntLittle(c_uint);
    self.byte_rate = try ww.readIntLittle(c_uint);
    self.vbv_buffer_size = try ww.readIntLittle(c_uint);
    self.flags = try ww.readIntLittle(u32);
    self.picture_width = try ww.readIntLittle(c_uint);
    self.picture_height = try ww.readIntLittle(c_uint);
    self.display_width = try ww.readIntLittle(c_uint);
    self.display_height = try ww.readIntLittle(c_uint);
    self.pixel_width = try ww.readIntLittle(c_uint);
    self.pixel_height = try ww.readIntLittle(c_uint);
    self.frame_period = try ww.readIntLittle(c_uint);
    self.profile_level_id = try ww.readIntLittle(u8);
    self.colour_primaries = try ww.readIntLittle(u8);
    self.transfer_characteristics = try ww.readIntLittle(u8);
    self.matrix_coefficients = try ww.readIntLittle(u8);
    return self;
}

pub const FrameType = enum {
    I,
    P,
    B,
};

pub const Frame = struct {
    const Self = @This();

    frametype: FrameType = FrameType.I,
    decodable_wo_prev_gop: bool = false,
    temporal_reference: u8 = 255,
    real_temporal_reference: u8 = 255,

    tff: bool = false,
    repeat: bool = false,
    progressive: bool = false,
    invalid: bool = false,

    pub fn writeOut(self: *const Self, r: anytype) !void {
        var bw = std.io.bitWriter(std.builtin.Endian.Little, r);
        switch (self.frametype) {
            FrameType.I => try bw.writeBits(@as(u8, 0b00), 2),
            FrameType.P => try bw.writeBits(@as(u8, 0b01), 2),
            FrameType.B => try bw.writeBits(@as(u8, 0b10), 2),
        }

        var flag: u8 = 0;
        if (self.decodable_wo_prev_gop) {
            flag |= 1;
        }
        if (self.tff) {
            flag |= 2;
        }
        if (self.repeat) {
            flag |= 4;
        }
        if (self.progressive) {
            flag |= 8;
        }
        if (self.invalid) {
            flag |= 16;
        }

        try bw.writeBits(flag, 5);
        try bw.writeBits(@as(u8, 0), 1); //padd to 8

        try bw.writeBits(self.temporal_reference, 8);
        try bw.writeBits(self.real_temporal_reference, 8);
        try bw.flushBits();
    }

    pub fn readIn(r: anytype) !Self {
        var self = Self{};

        var br = std.io.bitReader(std.builtin.Endian.Little, r);
        switch (try br.readBitsNoEof(u8, 2)) {
            0b00 => self.frametype = FrameType.I,
            0b01 => self.frametype = FrameType.P,
            0b10 => self.frametype = FrameType.B,
            else => unreachable,
        }
        self.decodable_wo_prev_gop = (try br.readBitsNoEof(u8, 1)) != 0;
        self.tff = (try br.readBitsNoEof(u8, 1)) != 0;
        self.repeat = (try br.readBitsNoEof(u8, 1)) != 0;
        self.progressive = (try br.readBitsNoEof(u8, 1)) != 0;
        self.invalid = (try br.readBitsNoEof(u8, 1)) != 0;
        _ = try br.readBitsNoEof(u8, 1);

        self.temporal_reference = try br.readBitsNoEof(u8, 8);
        self.real_temporal_reference = try br.readBitsNoEof(u8, 8);

        return self;
    }
};

pub const OutGopInfo = struct {
    const Self = @This();

    //where you need to seek to to start decoding this gop (in the m2v stream)
    sequence_info_start: u64 = 0,
    closed: bool = false,
    frame_cnt: u8 = 0,
    frames: [30]Frame = undefined, //in decode order

    indexing_only_slicecnt: u8 = 0,

    pub fn writeOut(self: *const Self, ww: anytype) !void {
        try ww.writeIntLittle(u64, self.sequence_info_start);

        var clsd: u8 = 0;
        if (self.closed) {
            clsd = 1;
        }
        try ww.writeIntLittle(u8, clsd);
        try ww.writeIntLittle(u8, self.frame_cnt);

        for (0..self.frame_cnt) |i| {
            try self.frames[i].writeOut(ww);
        }
    }

    pub fn readIn(rr: anytype) !Self {
        var self: Self = undefined;

        self.sequence_info_start = try rr.readIntLittle(u64);
        self.closed = try rr.readIntLittle(u8) == 1;
        self.frame_cnt = try rr.readIntLittle(u8);

        for (0..self.frame_cnt) |i| {
            self.frames[i] = try Frame.readIn(rr);
        }

        return self;
    }
};

pub const GopLookupEntry = struct {
    gop: u32 = 0,
    decode_frame_offset: u8 = 0,
    gop_framestart: u32 = 0,
};

/// Contains list of OutGopInfo and fast lookup and statics that can be computed from the gops
pub const GopLookup = struct {
    const Self = @This();

    gops: std.ArrayList(OutGopInfo),
    lookuptable: std.ArrayList(GopLookupEntry),
    total_frame_cnt: c_int,
    framestats: struct {
        prog: u64,
        tff: u64,
        rff: u64,
    },

    pub fn deinit(self: *Self) void {
        self.gops.deinit();
        self.lookuptable.deinit();
    }

    pub fn init(mm: std.mem.Allocator, gop_rd: anytype) !GopLookup {
        var arl = std.ArrayList(OutGopInfo).init(mm);
        var framegoplookup = std.ArrayList(GopLookupEntry).init(mm);
        var total_frame_cnt: c_int = 0;

        var gop_cnt: u32 = 0;

        var cnt_progressize: u64 = 0;
        var cnt_tff: u64 = 0;
        var cnt_rff: u64 = 0;

        //TODO: heap fragmentation
        while (true) {
            //Readin gop from file
            const gpp = OutGopInfo.readIn(gop_rd) catch break;
            var gopinfo = try arl.addOne();
            gopinfo.* = gpp;

            //Calculate values for quickacces
            const gop_framestart = total_frame_cnt;
            total_frame_cnt += gpp.frame_cnt;

            const frmcnt: usize = @intCast(gpp.frame_cnt);
            try framegoplookup.appendNTimes(undefined, frmcnt);

            var arr = framegoplookup.items[framegoplookup.items.len - frmcnt ..];

            for (0..gpp.frame_cnt) |i| {
                const frm = gpp.frames[i];

                arr[frm.temporal_reference].gop = gop_cnt;
                arr[frm.temporal_reference].gop_framestart = @as(u32, @intCast(gop_framestart));
                arr[frm.temporal_reference].decode_frame_offset = @as(u8, @intCast(i));

                if (frm.progressive) cnt_progressize += 1;
                if (frm.tff) cnt_tff += 1;
                if (frm.repeat) cnt_rff += 1;
            }

            gop_cnt += 1;
        }

        return .{ .gops = arl, .lookuptable = framegoplookup, .total_frame_cnt = total_frame_cnt, .framestats = .{
            .prog = cnt_progressize,
            .rff = cnt_rff,
            .tff = cnt_tff,
        } };
    }
};
