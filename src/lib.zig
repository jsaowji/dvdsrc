const vs = @import("bindings/vapoursynth.zig");
const std = @import("std");

const mpeg2 = @import("./bindings/mpeg2.zig");
const dvd_reader = @import("./dvd_reader.zig");
const m2v_reader = @import("./m2v_reader.zig");
const ps_index = @import("./ps_index.zig");
const utils = @import("./utils.zig");
const dvdread = @import("manual_dvdread.zig");

const rad = @import("./random_access_decoder.zig");
const index_manager = @import("./index_manager.zig");
const m2v_index = @import("./m2v_index.zig");
const indexer = @import("./indexer.zig");

const mm = std.heap.c_allocator;

const FilterConfiguration = struct {
    fake_vfr: bool,
    guess_ar: bool,
};

const M2vFilter = struct {
    const M2vFilterData = struct {
        const Self = @This();

        video_info: vs.VSVideoInfo,
        file: std.fs.File,
        randy: rad.RandomAccessDecoder(std.fs.File),

        fn init(path: []const u8, video_info: vs.VSVideoInfo, goplookup: m2v_index.GopLookup, fconf: FilterConfiguration) Self {
            var file = std.fs.openFileAbsolute(path, .{}) catch unreachable;

            return Self{
                .file = file,
                .video_info = video_info,
                .randy = .{
                    .m2v = file,
                    .gopy = goplookup,
                    .decoder_state = null,
                    .video_info = video_info,
                    .guess_ar = fconf.guess_ar,
                    .fake_vfr = fconf.fake_vfr,
                },
            };
        }

        fn deinit(
            self: *Self,
            vsapi: [*c]const vs.VSAPI,
        ) void {
            self.file.close();
            self.randy.deinit(vsapi);
        }
    };

    export fn filterGetFrame(n: c_int, activationReason: c_int, instanceData: ?*anyopaque, frameData: [*c]?*anyopaque, frameCtx: ?*vs.VSFrameContext, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) ?*const vs.VSFrame {
        _ = frameData;
        _ = frameCtx;
        _ = activationReason;
        var d: *M2vFilterData = @ptrCast(@alignCast(instanceData));

        d.randy.prefetchFrame(@as(u64, @intCast(n)), vsapi, core);
        return d.randy.fetchFrame(@as(u64, @intCast(n)), vsapi);
    }

    export fn filterFree(instanceData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) void {
        _ = core;
        var d: *M2vFilterData = @ptrCast(@alignCast(instanceData));
        d.deinit(vsapi);
        mm.destroy(d);
    }

    pub export fn filterCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;

        const path = vsapi.*.mapGetData.?(in, "path", 0, 0);

        var idxnfo = index_manager.IndexInfo.init(
            path,
            index_manager.ModeInfo.m2v,
        ) catch unreachable;
        defer idxnfo.deinit();
        var idxf = index_manager.IndexManager.getIndexFolder(idxnfo) catch unreachable;
        var need_indexing = false;

        if (!idxf.existed) {
            need_indexing = true;
        }

        //Check if all files really exists
        _ = idxf.dir.statFile("sequence.bin") catch {
            need_indexing = true;
        };
        _ = idxf.dir.statFile("gops.bin") catch {
            need_indexing = true;
        };

        if (need_indexing) {
            indexer.doIndexingM2v(idxnfo) catch |e| {
                switch (e) {
                    else => {
                        vsapi.*.mapSetError.?(out, "dvdsrc: could not index unk error");
                        return;
                    },
                }
            };
        }

        var seq_file = idxf.dir.openFile("sequence.bin", .{}) catch unreachable;
        var seq = m2v_index.readinSequence(seq_file.reader()) catch unreachable;

        var gop_file = idxf.dir.openFile("gops.bin", .{}) catch unreachable;
        var gop_rd = std.io.bufferedReader(gop_file.reader());

        const goplookup = m2v_index.GopLookup.init(mm, gop_rd.reader()) catch unreachable;

        var fake_vfr = goplookup.framestats.rff != 0;
        _ = fake_vfr;
        var vi = rad.seqToVideoInfo(&seq, goplookup.total_frame_cnt);

        _ = vsapi.*.getVideoFormatByID.?(&vi.format, vs.pfYUV420P8, core);

        var data = mm.create(M2vFilterData) catch unreachable;
        data.* = M2vFilterData.init(idxnfo.path, vi, goplookup, .{
            .guess_ar = true,
            .fake_vfr = true,
        });

        vsapi.*.createVideoFilter.?(out, "M2V", &data.video_info, filterGetFrame, filterFree, vs.fmUnordered, null, 0, data, core);
    }
};

const FullFilter = struct {
    const FullFilterError = error{dvddoesnot};

    const FullFilterData = struct {
        const Self = @This();

        video_info: vs.VSVideoInfo,

        file: *dvdread.dvd_file_t,
        dvd_r: *dvdread.dvd_reader_t,

        randy: rad.RandomAccessDecoder(m2v_reader.m2vReader(dvd_reader.DvdReader)),

        fn init(dvd: [*c]const u8, vts: u8, main: u8, video_info: vs.VSVideoInfo, idx: ps_index.PsIndex, goplookup: m2v_index.GopLookup, fconf: FilterConfiguration) !Self {
            var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, dvd);

            if (dvd_r == null) {
                return FullFilterError.dvddoesnot;
            }

            var domain: c_uint = undefined;
            if (main == 0) {
                domain = dvdread.DVD_READ_MENU_VOBS;
            } else {
                domain = dvdread.DVD_READ_TITLE_VOBS;
            }

            var file = dvdread.DVDOpenFile(@as(*dvdread.dvd_reader_t, @ptrCast(dvd_r)), vts, domain);
            return Self{
                .file = file.?,
                .dvd_r = dvd_r.?,
                .video_info = video_info,

                .randy = .{
                    .m2v = m2v_reader.m2vReader(dvd_reader.DvdReader).init(idx, dvd_reader.DvdReader.init(file.?)) catch unreachable,

                    .gopy = goplookup,

                    .decoder_state = null,
                    .video_info = video_info,
                    .fake_vfr = fconf.fake_vfr,
                    .guess_ar = fconf.guess_ar,
                },
            };
        }

        fn deinit(
            self: *Self,
            vsapi: [*c]const vs.VSAPI,
        ) void {
            dvdread.DVDCloseFile(self.file);
            dvdread.DVDClose(self.dvd_r);
            self.randy.deinit(vsapi);
        }
    };

    export fn fullFilterGetFrame(n: c_int, activationReason: c_int, instanceData: ?*anyopaque, frameData: [*c]?*anyopaque, frameCtx: ?*vs.VSFrameContext, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) ?*const vs.VSFrame {
        _ = frameData;
        _ = frameCtx;
        _ = activationReason;

        var d = @as(*FullFilterData, @ptrCast(@alignCast(instanceData)));

        d.randy.prefetchFrame(@as(u64, @intCast(n)), vsapi, core);
        return d.randy.fetchFrame(@as(u64, @intCast(n)), vsapi);
    }

    export fn fullFilterFree(instanceData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) void {
        _ = core;
        var d = @as(*FullFilterData, @ptrCast(@alignCast(instanceData)));

        if (d.randy.file_frame_position_frame) |a| {
            vsapi.*.freeFrame.?(a);
        }
        if (d.randy.json_frame) |a| {
            vsapi.*.freeFrame.?(a);
        }
        if (d.randy.vobid_frame) |a| {
            vsapi.*.freeFrame.?(a);
        }
        if (d.randy.angle_frame) |a| {
            vsapi.*.freeFrame.?(a);
        }

        d.deinit(vsapi);
        mm.destroy(d);
    }

    pub export fn fullFilterCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;
        const dvd = vsapi.*.mapGetData.?(in, "dvd", 0, 0);
        const vts = vsapi.*.mapGetInt.?(in, "vts", 0, 0);
        const domain = vsapi.*.mapGetInt.?(in, "domain", 0, 0);

        var ii_domain: index_manager.Domain = undefined;

        if (domain == 0) {
            ii_domain = .menuvob;
        } else if (domain == 1) {
            ii_domain = .titlevobs;
        } else {
            vsapi.*.mapSetError.?(out, "dvdsrc: domain only supported 0 menuvob 1 titlevob");
            return;
        }

        var idxnfo = index_manager.IndexInfo.init(dvd, index_manager.ModeInfo{
            .full = .{
                .vts = @as(u8, @intCast(vts)),
                .domain = ii_domain,
            },
        }) catch unreachable;
        defer idxnfo.deinit();

        var idxf = index_manager.IndexManager.getIndexFolder(idxnfo) catch unreachable;
        var need_indexing = false;

        if (!idxf.existed) {
            need_indexing = true;
        }

        //Check if all files really exists
        _ = idxf.dir.statFile("sequence.bin") catch {
            need_indexing = true;
        };
        _ = idxf.dir.statFile("ps_index.bin") catch {
            need_indexing = true;
        };
        _ = idxf.dir.statFile("gops.bin") catch {
            need_indexing = true;
        };
        _ = idxf.dir.statFile("framepos.bin") catch {
            need_indexing = true;
        };
        _ = idxf.dir.statFile("vobid.bin") catch {
            need_indexing = true;
        };
        _ = idxf.dir.statFile("angle.bin") catch {
            need_indexing = true;
        };

        if (need_indexing) {
            indexer.doIndexingFullDvd(dvd, idxnfo) catch |e| {
                switch (e) {
                    indexer.DvdIndexingError.fileopen => {
                        vsapi.*.mapSetError.?(out, "dvdsrc: fileopen error, does vts exist?");
                        return;
                    },
                    indexer.DvdIndexingError.dvdopen => {
                        vsapi.*.mapSetError.?(out, "dvdsrc: dvdopen error, does it exist?");
                        return;
                    },
                    else => {
                        vsapi.*.mapSetError.?(out, "dvdsrc: could not index unk error");
                        return;
                    },
                }
            };
        }

        var seq_file = idxf.dir.openFile("sequence.bin", .{}) catch unreachable;
        var seq = m2v_index.readinSequence(seq_file.reader()) catch unreachable;

        var gop_file = idxf.dir.openFile("gops.bin", .{}) catch unreachable;
        var gop_rd = std.io.bufferedReader(gop_file.reader());

        const goplookup = m2v_index.GopLookup.init(mm, gop_rd.reader()) catch unreachable;

        var fake_vfr = goplookup.framestats.rff != 0;
        _ = fake_vfr;
        var vi = rad.seqToVideoInfo(&seq, goplookup.total_frame_cnt);

        _ = vsapi.*.getVideoFormatByID.?(&vi.format, vs.pfYUV420P8, core);

        var psidx: ps_index.PsIndex = undefined;
        {
            var file = idxf.dir.openFile("ps_index.bin", .{}) catch unreachable;
            var bufed = std.io.bufferedReader(file.reader());
            psidx = ps_index.PsIndex.readIn(bufed.reader()) catch unreachable;
        }

        var data = mm.create(FullFilterData) catch unreachable;

        var format: vs.VSVideoFormat = undefined;
        _ = vsapi.*.getVideoFormatByID.?(&format, vs.pfGray8, core);

        const f1sz = 1920 * 1088 * 15;

        var f1 = vsapi.*.newVideoFrame.?(&format, f1sz, 1, null, core);
        var f2 = vsapi.*.newVideoFrame.?(&format, 1920 * 1088, 1, null, core);
        var vobid_frame = vsapi.*.newVideoFrame.?(&format, f1sz, 1, null, core);
        var angle_frame = vsapi.*.newVideoFrame.?(&format, f1sz, 1, null, core);

        data.* = FullFilterData.init(dvd, @as(u8, @intCast(vts)), @as(u8, @intCast(domain)), vi, psidx, goplookup, .{
            .guess_ar = true,
            .fake_vfr = true,
        }) catch {
            vsapi.*.mapSetError.?(out, "dvdsrc: iso file does not exist");
            return;
        };
        vsapi.*.createVideoFilter.?(out, "Full", &data.video_info, fullFilterGetFrame, fullFilterFree, vs.fmUnordered, null, 0, data, core);
        {
            var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, dvd);
            defer dvdread.DVDClose(dvd_r);
            {
                var f1_ptr = vsapi.*.getWritePtr.?(f1, 0);
                var framepos_file = idxf.dir.openFile("framepos.bin", .{}) catch unreachable;
                var framepos_sz = framepos_file.reader().readAll(f1_ptr[8..f1sz]) catch unreachable;
                std.mem.writeIntSliceLittle(u64, f1_ptr[0..8], framepos_sz);
            }
            {
                var f2_ptr = vsapi.*.getWritePtr.?(f2, 0);

                var json = getstring(f2_ptr + 8, dvd_r, dvd, @as(u32, @intCast(vts)));
                const lenn = std.mem.indexOfSentinel(u8, 0, json);

                std.mem.writeIntSliceLittle(u64, f2_ptr[0..8], lenn);
                //@memcpy(f2_ptr[8 .. 8 + lenn], json[0..lenn]);
            }
            {
                var f3_ptr = vsapi.*.getWritePtr.?(vobid_frame, 0);
                var file = idxf.dir.openFile("vobid.bin", .{}) catch unreachable;

                var file_sz = file.reader().readAll(f3_ptr[8..f1sz]) catch unreachable;
                std.mem.writeIntSliceLittle(u64, f3_ptr[0..8], file_sz);
            }
            {
                var f3_ptr = vsapi.*.getWritePtr.?(angle_frame, 0);
                var file = idxf.dir.openFile("angle.bin", .{}) catch unreachable;

                var file_sz = file.reader().readAll(f3_ptr[8..f1sz]) catch unreachable;
                std.mem.writeIntSliceLittle(u64, f3_ptr[0..8], file_sz);
            }
        }
        data.*.randy.file_frame_position_frame = f1;
        data.*.randy.json_frame = f2;
        data.*.randy.vobid_frame = vobid_frame;
        data.*.randy.angle_frame = angle_frame;
    }
};

pub extern fn getstring(bigbuffer: *u8, decoder: ?*dvdread.dvd_reader_t, dvdpath: *const u8, current_vts: u32) [*c]const u8;

const VobToFile = struct {
    pub export fn vobtoFileCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;
        _ = core;
        const outfile = vsapi.*.mapGetData.?(in, "outfile", 0, 0);
        const dvd = vsapi.*.mapGetData.?(in, "dvd", 0, 0);
        const vts = vsapi.*.mapGetInt.?(in, "vts", 0, 0);
        const vsdomain = vsapi.*.mapGetInt.?(in, "domain", 0, 0);

        var ii_domain: index_manager.Domain = undefined;

        if (vsdomain == 0) {
            ii_domain = .menuvob;
        } else if (vsdomain == 1) {
            ii_domain = .titlevobs;
        } else {
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

        var dvdfile = dvdread.DVDOpenFile(@as(*dvdread.dvd_reader_t, @ptrCast(dvd_r)), @as(c_int, @intCast(vts)), domain);
        defer dvdread.DVDCloseFile(dvdfile);

        const sector_cnt = vsapi.*.mapNumElements.?(in, "sectors");

        var file = std.fs.createFileAbsolute(std.mem.span(outfile), .{}) catch unreachable;
        defer file.close();
        var bufwrite = std.io.bufferedWriter(file.writer());
        defer bufwrite.flush() catch unreachable;

        const dontVideo = true;

        if (dontVideo) {
            const SectoReader = struct {
                dvdfile: ?*dvdread.dvd_file_t,
                buffer: [2048]u8 = undefined,
                buffer_left: usize = 0,
                sector_i: usize = 0,
                sector_cnt: usize,
                vsapi: [*c]const vs.VSAPI,
                in: ?*const vs.VSMap,
                const Self = @This();
                pub const Error = error{AllRead};
                pub const Reader = std.io.Reader(*Self, Error, read);

                pub fn read(self: *Self, dest: []u8) !usize {
                    if (self.buffer_left == 0) {
                        if (self.sector_i == self.sector_cnt) return Error.AllRead;
                        const sector = self.vsapi.*.mapGetInt.?(self.in, "sectors", @as(c_int, @intCast(self.sector_i)), 0);
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
            var secto: SectoReader = .{
                .vsapi = vsapi,
                .in = in,

                .dvdfile = dvdfile,
                .sector_cnt = @as(usize, @intCast(sector_cnt)),
            };
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

export fn VapourSynthPluginInit2(plugin: ?*vs.VSPlugin, vspapi: *const vs.VSPLUGINAPI) void {
    _ = vspapi.configPlugin.?("com.jsaowji.dvdsrc", "dvdsrc", "VapourSynth DVD source", vs.VS_MAKE_VERSION(1, 0), vs.VAPOURSYNTH_API_VERSION, 0, plugin);
    _ = vspapi.registerFunction.?("Full", "dvd:data;vts:int;domain:int", "clip:vnode;", FullFilter.fullFilterCreate, vs.NULL, plugin);
    _ = vspapi.registerFunction.?("M2V", "path:data", "clip:vnode;", M2vFilter.filterCreate, vs.NULL, plugin);

    _ = vspapi.registerFunction.?("VobToFile", "dvd:data;vts:int;domain:int;sectors:int[];outfile:data", "", VobToFile.vobtoFileCreate, vs.NULL, plugin);
}
