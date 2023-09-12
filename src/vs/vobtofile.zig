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
const secto_reader = @import("../secto_reader.zig");

const cmn = @import("cmn.zig");

pub const VobToFile = struct {
    pub export fn vobtoFileCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;
        _ = core;
        const outfile = vsapi.*.mapGetData.?(in, "outfile", 0, 0);
        const dvd = vsapi.*.mapGetData.?(in, "dvd", 0, 0);
        const vts = vsapi.*.mapGetInt.?(in, "vts", 0, 0);
        const vsdomain = vsapi.*.mapGetInt.?(in, "domain", 0, 0);
        const novideo = vsapi.*.mapGetInt.?(in, "novideo", 0, 0);

        if (vsdomain == 0) {} else if (vsdomain == 1) {} else {
            vsapi.*.mapSetError.?(out, "dvdsrc: domain only supported 0 menuvob 1 titlevob");
            return;
        }

        var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, dvd);
        defer dvdread.DVDClose(dvd_r);

        if (dvd_r == null) {
            vsapi.*.mapSetError.?(out, "dvdsrc: dvd does not open");
            return;
        }

        var domain: c_uint = undefined;
        if (domain == 0) {
            domain = dvdread.DVD_READ_MENU_VOBS;
        } else {
            domain = dvdread.DVD_READ_TITLE_VOBS;
        }

        var file = std.fs.createFileAbsolute(std.mem.span(outfile), .{}) catch unreachable;
        defer file.close();
        var bufwrite = std.io.bufferedWriter(file.writer());
        defer bufwrite.flush() catch unreachable;

        const sector_cnt = vsapi.*.mapNumElements.?(in, "sectors");
        var dvdfile = dvdread.DVDOpenFile(@as(*dvdread.dvd_reader_t, @ptrCast(dvd_r)), @as(c_int, @intCast(vts)), domain);
        //dont free here
        if (novideo == 1) {
            var secto = secto_reader.SectoReader.init(@as(usize, @intCast(sector_cnt)), dvdfile);
            defer secto.deinit();

            for (0..@as(usize, @intCast(sector_cnt))) |i| {
                secto.sectors[i] = @as(u32, @intCast(vsapi.*.mapGetInt.?(in, "sectors", @as(c_int, @intCast(i)), 0)));
            }

            var buf = std.heap.c_allocator.alloc(u8, 2048 * 116) catch unreachable;

            var read_in = secto.reader();

            while (true) {
                const st = utils.checkStartCode(read_in) catch break;

                //pid filter out 0xE0
                switch (st) {
                    //pack header
                    0xBA => {
                        // read_in.skipBytes(10, .{}) catch unreachable;
                        //we need to include this for some reason or else ffmpeg does weird stuff
                        const data_read = read_in.readAtLeast(buf[0..10], 10) catch unreachable;
                        std.debug.assert(data_read == 10);

                        _ = bufwrite.writer().writeAll(&[_]u8{ 0, 0, 1, st }) catch unreachable;
                        _ = bufwrite.writer().writeAll(buf[0..10]) catch unreachable;
                    },
                    0xBF, 0xBD, 0xBB, 0xBE => {
                        const len = read_in.readIntBig(u16) catch unreachable;

                        if (len > buf.len) {
                            std.heap.c_allocator.free(buf);
                            buf = std.heap.c_allocator.alloc(u8, len) catch unreachable;
                        }
                        const data_read = read_in.readAtLeast(buf[0..len], len) catch unreachable;
                        std.debug.assert(data_read == len);

                        _ = bufwrite.writer().writeAll(&[_]u8{ 0, 0, 1, st }) catch unreachable;
                        bufwrite.writer().writeIntBig(u16, len) catch unreachable;
                        _ = bufwrite.writer().writeAll(buf[0..len]) catch unreachable;
                    },
                    //video don't
                    0xE0 => {
                        var len = read_in.readIntBig(u16) catch unreachable;
                        _ = read_in.skipBytes(len, .{}) catch unreachable;
                    },
                    else => {
                        unreachable;
                    },
                }
            }
        } else {
            var buffer: [2048]u8 = undefined;

            for (0..@as(usize, @intCast(sector_cnt))) |sector_i| {
                const sector = vsapi.*.mapGetInt.?(in, "sectors", @as(c_int, @intCast(sector_i)), 0);
                _ = dvdread.DVDReadBlocks(dvdfile, @as(c_int, @intCast(sector)), 1, &buffer);
                bufwrite.writer().writeAll(&buffer) catch unreachable;
            }
        }
    }
};
