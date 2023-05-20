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
    tff: bool = false,
    repeat: bool = false,
    progressive: bool = false,
    temporal_reference: u8 = 255,

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

        try bw.writeBits(flag, 4);
        try bw.writeBits(@as(u8, 0), 2); //padd to 8

        try bw.writeBits(self.temporal_reference, 8);
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
        _ = try br.readBitsNoEof(u8, 2);

        self.temporal_reference = try br.readBitsNoEof(u8, 8);

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
