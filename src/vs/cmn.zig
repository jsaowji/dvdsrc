const std = @import("std");
const dvdread = @import("../manual_dvdread.zig");

pub const mm = std.heap.c_allocator;

pub extern fn getstring(bigbuffer: *u8, decoder: ?*dvdread.dvd_reader_t, dvdpath: *const u8, current_vts: u32, current_domain: u32) [*c]const u8;

pub const FilterConfiguration = struct {
    fake_vfr: bool,
    guess_ar: bool,
};
