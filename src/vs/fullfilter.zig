const std = @import("std");
const vs = @import("../bindings/vapoursynth.zig");

const mpeg2 = @import("../bindings/mpeg2.zig");
const dvd_reader = @import("../dvd_reader.zig");
const ps_reader = @import("../ps_reader.zig");
const ps_index = @import("../ps_index.zig");
const utils = @import("../utils.zig");
const dvdread = @import("../manual_dvdread.zig");

const rad = @import("../random_access_decoder.zig");
const index_manager = @import("../index_manager.zig");
const m2v_index = @import("../m2v_index.zig");
const indexer = @import("../indexer.zig");
const secto_reader = @import("../secto_reader.zig");

const cmn = @import("cmn.zig");

const VsIndexingError = error{
    Genric,
};

pub fn openSectoReader(
    in: ?*const vs.VSMap,
    vsapi: [*c]const vs.VSAPI,
    dvd_r: *dvdread.dvd_reader_t,
    vts: i64,
    domain: i64,
) struct { reader: secto_reader.SectoReader, hash: u64 } {
    var dmn: c_uint = 0;

    if (domain == 0) {
        dmn = dvdread.DVD_READ_MENU_VOBS;
    }
    if (domain == 1) {
        dmn = dvdread.DVD_READ_TITLE_VOBS;
    }

    const sector_cnt = vsapi.*.mapNumElements.?(in, "sectors");
    var dvdfile = dvdread.DVDOpenFile(dvd_r, @as(c_int, @intCast(vts)), dmn);

    var secto = secto_reader.SectoReader.init(@as(usize, @intCast(sector_cnt)), dvdfile);
    var hash: u64 = 1;
    for (0..@as(usize, @intCast(sector_cnt))) |i| {
        secto.sectors[i] = @as(u32, @intCast(vsapi.*.mapGetInt.?(in, "sectors", @as(c_int, @intCast(i)), 0)));
        hash +%= secto.sectors[i];
    }

    return .{
        .reader = secto,
        .hash = hash,
    };
}

pub fn make_sure_indexing(
    in: ?*const vs.VSMap,
    out: ?*vs.VSMap,
    vsapi: [*c]const vs.VSAPI,
) !struct {
    dvd: [*c]const u8,
    vts: i64,
    domain: i64,
    extra_hash: u64,
    idxf: index_manager.IdxFolder,
} {
    const dvd = vsapi.*.mapGetData.?(in, "dvd", 0, 0);
    const vts = vsapi.*.mapGetInt.?(in, "vts", 0, 0);
    const domain = vsapi.*.mapGetInt.?(in, "domain", 0, 0);

    //TODO put somehwer eleses
    if (domain < 0 or domain > 1) {
        vsapi.*.mapSetError.?(out, "dvdsrc: domain only supported 0 menuvob 1 titlevob");
        return VsIndexingError.Genric;
    }

    //TODO: copy paste
    const sector_cnt = vsapi.*.mapNumElements.?(in, "sectors");
    var precalchash: u64 = 1;
    for (0..@as(usize, @intCast(sector_cnt))) |i| {
        precalchash +%= @as(u32, @intCast(vsapi.*.mapGetInt.?(in, "sectors", @as(c_int, @intCast(i)), 0)));
    }

    var idxnfo = index_manager.IndexInfo.init(dvd, index_manager.ModeInfo{
        .neofull = .{
            .vts = @as(u8, @intCast(vts)),
            .domain = domain,
            .sectors_hash = precalchash,
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
    _ = idxf.dir.statFile(indexer.PS_INDEX_M2V_FILENAME) catch {
        need_indexing = true;
    };
    _ = idxf.dir.statFile("gops.bin") catch {
        need_indexing = true;
    };
    _ = idxf.dir.statFile("framepos.bin") catch {
        need_indexing = true;
    };
    _ = idxf.dir.statFile("vobidcellid.bin") catch {
        need_indexing = true;
    };
    _ = idxf.dir.statFile("angle.bin") catch {
        need_indexing = true;
    };

    if (need_indexing) {
        var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, dvd);
        if (dvd_r == null) {
            unreachable;
        }
        var reader = openSectoReader(in, vsapi, dvd_r.?, vts, domain);
        defer reader.reader.deinit();
        std.debug.assert(precalchash == reader.hash);

        indexer.doIndexingFullDvd(reader.reader, idxnfo) catch |e| {
            switch (e) {
                //   indexer.DvdIndexingError.fileopen => {
                //       vsapi.*.mapSetError.?(out, "dvdsrc: fileopen error, does vts exist?");
                //       return VsIndexingError.Genric;
                //   },
                //   indexer.DvdIndexingError.dvdopen => {
                //       vsapi.*.mapSetError.?(out, "dvdsrc: dvdopen error, does it exist?");
                //       return VsIndexingError.Genric;
                //   },
                else => {
                    std.debug.print("{?}\n", .{e});
                    vsapi.*.mapSetError.?(out, "dvdsrc: could not index unk error");
                    return VsIndexingError.Genric;
                },
            }
        };
    }
    return .{
        .idxf = idxf,
        .dvd = dvd,
        .vts = vts,
        .domain = domain,
        .extra_hash = precalchash,
    };
}

pub fn readinPsIndex(
    sub_path: []const u8,
    dir: std.fs.Dir,
) !ps_index.PsIndex {
    var psidx: ps_index.PsIndex = undefined;

    var file = dir.openFile(sub_path, .{}) catch unreachable;
    var bufed = std.io.bufferedReader(file.reader());
    psidx = ps_index.PsIndex.readIn(bufed.reader()) catch unreachable;
    return psidx;
}
pub const FullFilter = struct {
    const FullFilterError = error{dvddoesnot};

    const FullFilterData = struct {
        const Self = @This();

        video_info: vs.VSVideoInfo,

        dvd_r: *dvdread.dvd_reader_t,
        reader: secto_reader.SectoReader,

        randy: rad.RandomAccessDecoder(ps_reader.psReader(secto_reader.SectoReader)),

        fn init(dvd_r: *dvdread.dvd_reader_t, reader: secto_reader.SectoReader, video_info: vs.VSVideoInfo, idx: ps_index.PsIndex, goplookup: m2v_index.GopLookup, fconf: cmn.FilterConfiguration) !Self {
            var ss = Self{
                .dvd_r = dvd_r,
                .video_info = video_info,
                .reader = reader,

                .randy = .{
                    .m2v = ps_reader.psReader(@TypeOf(reader)).init(idx, reader, ps_reader.OutType.Video) catch unreachable,

                    .gopy = goplookup,

                    .decoder_state = null,
                    .video_info = video_info,
                    .fake_vfr = fconf.fake_vfr,
                    .guess_ar = fconf.guess_ar,
                    .extra_data_frames = undefined,
                },
            };
            return ss;
        }

        fn deinit(
            self: *Self,
            vsapi: [*c]const vs.VSAPI,
        ) void {
            self.reader.deinit();
            dvdread.DVDClose(self.dvd_r);
            self.randy.deinit(vsapi);
        }
    };

    fn fullFilterGetFrame(n: c_int, activationReason: c_int, instanceData: ?*anyopaque, frameData: [*c]?*anyopaque, frameCtx: ?*vs.VSFrameContext, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) ?*const vs.VSFrame {
        _ = frameData;
        _ = frameCtx;
        _ = activationReason;

        var d = @as(*FullFilterData, @ptrCast(@alignCast(instanceData)));

        if (d.randy.getframe_exit_early(@as(u64, @intCast(n)), vsapi, core)) |a| {
            return a;
        }
        d.randy.prefetchFrame(@as(u64, @intCast(n)), vsapi, core);
        return d.randy.fetchFrame(@as(u64, @intCast(n)), vsapi);
    }

    fn fullFilterFree(instanceData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = core;
        var d = @as(*FullFilterData, @ptrCast(@alignCast(instanceData)));

        for (d.randy.extra_data_frames) |a| {
            if (a) |b| {
                vsapi.*.freeFrame.?(b.frame);
            }
        }

        d.deinit(vsapi);
        cmn.mm.destroy(d);
    }

    pub fn fullFilterCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;

        var ret = make_sure_indexing(in, out, vsapi) catch return;

        var idxf = ret.idxf;
        var dvd = ret.dvd;
        var vts = ret.vts;
        var domain = ret.domain;

        var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, dvd);
        var reader = openSectoReader(in, vsapi, dvd_r.?, ret.vts, ret.domain);

        var seq_file = idxf.dir.openFile("sequence.bin", .{}) catch unreachable;
        var seq = m2v_index.readinSequence(seq_file.reader()) catch unreachable;

        var gop_file = idxf.dir.openFile("gops.bin", .{}) catch unreachable;
        var gop_rd = std.io.bufferedReader(gop_file.reader());

        const goplookup = m2v_index.GopLookup.init(cmn.mm, gop_rd.reader()) catch unreachable;

        var fake_vfr = goplookup.framestats.rff != 0;
        _ = fake_vfr;
        var vi = rad.seqToVideoInfo(&seq, goplookup.total_frame_cnt);

        _ = vsapi.*.getVideoFormatByID.?(&vi.format, vs.pfYUV420P8, core);

        var psidx: ps_index.PsIndex = readinPsIndex(indexer.PS_INDEX_M2V_FILENAME, idxf.dir) catch unreachable;

        var data = cmn.mm.create(FullFilterData) catch unreachable;

        var format: vs.VSVideoFormat = undefined;
        _ = vsapi.*.getVideoFormatByID.?(&format, vs.pfGray8, core);

        const f1sz = 1920 * 1088 * 15;

        var f1 = vsapi.*.newVideoFrame.?(&format, f1sz, 1, null, core);
        var f2 = vsapi.*.newVideoFrame.?(&format, 1920 * 1088, 1, null, core);
        var vobidcellid_frame = vsapi.*.newVideoFrame.?(&format, f1sz, 1, null, core);
        var angle_frame = vsapi.*.newVideoFrame.?(&format, f1sz, 1, null, core);
        var rff_frame = vsapi.*.newVideoFrame.?(&format, 1920 * 1088 * 3, 1, null, core);
        var tff_frame = vsapi.*.newVideoFrame.?(&format, 1920 * 1088 * 3, 1, null, core);

        data.* = FullFilterData.init(dvd_r.?, reader.reader, vi, psidx, goplookup, .{
            .guess_ar = true,
            .fake_vfr = true,
        }) catch {
            vsapi.*.mapSetError.?(out, "dvdsrc: iso file does not exist");
            return;
        };

        vsapi.*.createVideoFilter.?(out, "FullM2V", &data.video_info, fullFilterGetFrame, fullFilterFree, vs.fmUnordered, null, 0, data, core);
        {
            {
                var f1_ptr = vsapi.*.getWritePtr.?(f1, 0);
                var framepos_file = idxf.dir.openFile("framepos.bin", .{}) catch unreachable;
                var framepos_sz = framepos_file.reader().readAll(f1_ptr[8..f1sz]) catch unreachable;
                std.mem.writeIntSliceLittle(u64, f1_ptr[0..8], framepos_sz);
            }
            {
                var f2_ptr = vsapi.*.getWritePtr.?(f2, 0);

                var json = cmn.getstring(f2_ptr + 8, dvd_r, dvd, @as(u32, @intCast(vts)), @as(u32, @intCast(domain)));
                const lenn = std.mem.indexOfSentinel(u8, 0, json);

                std.mem.writeIntSliceLittle(u64, f2_ptr[0..8], lenn);
                //@memcpy(f2_ptr[8 .. 8 + lenn], json[0..lenn]);
            }
            {
                var f3_ptr = vsapi.*.getWritePtr.?(vobidcellid_frame, 0);
                var file = idxf.dir.openFile("vobidcellid.bin", .{}) catch unreachable;

                var file_sz = file.reader().readAll(f3_ptr[8..f1sz]) catch unreachable;
                std.mem.writeIntSliceLittle(u64, f3_ptr[0..8], file_sz);
            }
            {
                var f3_ptr = vsapi.*.getWritePtr.?(angle_frame, 0);
                var file = idxf.dir.openFile("angle.bin", .{}) catch unreachable;

                var file_sz = file.reader().readAll(f3_ptr[8..f1sz]) catch unreachable;
                std.mem.writeIntSliceLittle(u64, f3_ptr[0..8], file_sz);
            }
            {
                var rff_ptr = vsapi.*.getWritePtr.?(rff_frame, 0);
                var tff_ptr = vsapi.*.getWritePtr.?(tff_frame, 0);
                var frame_cnt: u64 = 0;
                for (goplookup.gops.items) |gp| {
                    var offset = frame_cnt;
                    for (0..gp.frame_cnt) |i| {
                        rff_ptr[8 + offset + gp.frames[i].temporal_reference] = @intFromBool(gp.frames[i].repeat);
                        tff_ptr[8 + offset + gp.frames[i].temporal_reference] = @intFromBool(gp.frames[i].tff);
                        frame_cnt += 1;
                    }
                }

                std.mem.writeIntSliceLittle(u64, rff_ptr[0..8], frame_cnt);
                std.mem.writeIntSliceLittle(u64, tff_ptr[0..8], frame_cnt);
            }
        }

        for (0..data.*.randy.extra_data_frames.len) |i| {
            data.*.randy.extra_data_frames[i] = null;
        }
        data.*.randy.extra_data_frames[0] = .{
            .name = "_FileFramePositionFrame",
            .frame = f1,
        };
        data.*.randy.extra_data_frames[1] = .{
            .name = "_JsonFrame",
            .frame = f2,
        };
        data.*.randy.extra_data_frames[2] = .{
            .name = "_VobIdCellIdFrame",
            .frame = vobidcellid_frame,
        };
        data.*.randy.extra_data_frames[3] = .{
            .name = "_AngleFrame",
            .frame = angle_frame,
        };
        data.*.randy.extra_data_frames[4] = .{
            .name = "_RffFrame",
            .frame = rff_frame,
        };
        data.*.randy.extra_data_frames[5] = .{
            .name = "_TffFrame",
            .frame = tff_frame,
        };

        data.*.randy.seq = seq;
    }
};
