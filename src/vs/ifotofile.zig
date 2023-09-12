const std = @import("std");
const vs = @import("../bindings/vapoursynth.zig");

const mpeg2 = @import("../bindings/mpeg2.zig");
const dvd_reader = @import("../dvd_reader.zig");
const ps_index = @import("../ps_index.zig");
const utils = @import("../utils.zig");
const dvdread = @import("../manual_dvdread.zig");

const rad = @import("../random_access_decoder.zig");
const index_manager = @import("../index_manager.zig");
const m2v_index = @import("../m2v_index.zig");
const indexer = @import("../indexer.zig");

const cmn = @import("cmn.zig");

pub const IfoToFile = struct {
    pub export fn ifoToFileCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;
        _ = core;
        const outfile = vsapi.*.mapGetData.?(in, "outfile", 0, 0);
        const dvd = vsapi.*.mapGetData.?(in, "dvd", 0, 0);
        const ifo = vsapi.*.mapGetInt.?(in, "ifo", 0, 0);

        var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, dvd);
        defer dvdread.DVDClose(dvd_r);

        if (dvd_r == null) {
            vsapi.*.mapSetError.?(out, "dvdsrc: dvd does not open");
            return;
        }

        var dvdstat: dvdread.dvd_stat_t = undefined;
        _ = dvdread.DVDFileStat(@as(*dvdread.dvd_reader_t, @ptrCast(dvd_r)), @as(c_int, @intCast(ifo)), dvdread.DVD_READ_INFO_FILE, &dvdstat);
        const ifofilesize: usize = @as(usize, @intCast(dvdstat.size));

        var dvdfile = dvdread.DVDOpenFile(@as(*dvdread.dvd_reader_t, @ptrCast(dvd_r)), @as(c_int, @intCast(ifo)), dvdread.DVD_READ_INFO_FILE);
        defer dvdread.DVDCloseFile(dvdfile);
        std.debug.assert(dvdstat.nr_parts == 1);

        var buffer = std.heap.c_allocator.alloc(u8, ifofilesize) catch unreachable;
        defer std.heap.c_allocator.free(buffer);

        const rdrd = dvdread.DVDReadBytes(dvdfile, buffer.ptr, ifofilesize);
        std.debug.assert(rdrd == ifofilesize);

        var file = std.fs.createFileAbsolute(std.mem.span(outfile), .{}) catch unreachable;
        defer file.close();

        file.writeAll(buffer) catch unreachable;
    }
};
