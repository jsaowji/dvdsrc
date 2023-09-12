const std = @import("std");
const vs = @import("../bindings/vapoursynth.zig");

const mpeg2 = @import("../bindings/mpeg2.zig");
const dvd_reader = @import("../dvd_reader.zig");
const ps_index = @import("../ps_index.zig");
const utils = @import("../utils.zig");
const dvdread = @import("../manual_dvdread.zig");

const rad = @import("../random_access_decoder_ac3.zig");
const index_manager = @import("../index_manager.zig");
const m2v_index = @import("../m2v_index.zig");
const indexer = @import("../indexer.zig");
const ps_extracter = @import("../ps_extracter.zig");
const ac3_index = @import("../ac3_index.zig");

const cmn = @import("cmn.zig");
const a52 = @import("../bindings/a52.zig");

pub const JsonFilter = struct {
    pub export fn jsonFilterCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;
        _ = core;
        const path = vsapi.*.mapGetData.?(in, "dvd", 0, 0);

        var ptr = std.heap.c_allocator.alloc(u8, 8192 * 64) catch unreachable;
        defer std.heap.c_allocator.free(ptr);

        var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, path);
        if (dvd_r == null) {
            vsapi.*.mapSetError.?(out, "dvdsrc: dvd does not open");
            return;
        }

        var json = cmn.getstring(&ptr.ptr[0], dvd_r, path, 0, 0);
        const lenn = std.mem.indexOfSentinel(u8, 0, json);

        _ = vsapi.*.mapSetData.?(out, "json", ptr.ptr, @as(c_int, @intCast(lenn)), vs.dtUtf8, vs.maReplace);
    }
};
