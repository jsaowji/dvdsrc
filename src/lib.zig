const vs = @import("bindings/vapoursynth.zig");
const std = @import("std");

const mpeg2 = @import("./bindings/mpeg2.zig");
const dvd_reader = @import("./dvd_reader.zig");
const m2v_reader = @import("./m2v_reader.zig");
const ps_index = @import("./ps_index.zig");
const utils = @import("./utils.zig");
const dvdread = @import("./bindings/dvdread.zig");

const rad = @import("./random_access_decoder.zig");
const index_manager = @import("./index_manager.zig");
const m2v_index = @import("./m2v_index.zig");
const indexer = @import("./indexer.zig");

const mm = std.heap.c_allocator;

const FilterData = struct {
    const Self = @This();

    video_info: vs.VSVideoInfo,

    file: *dvdread.dvd_file_t,
    dvd_r: *dvdread.dvd_reader_t,

    randy: rad.RandomAccessDecoder,

    fn init(dvd: [*c]const u8, vts: u8, main: u8, video_info: vs.VSVideoInfo, idx: ps_index.PsIndex, gops: std.ArrayList(m2v_index.OutGopInfo), gopl: std.ArrayList(rad.GopLookup)) Self {
        var dvd_r = dvdread.DVDOpen(dvd);

        var domain: c_uint = undefined;
        if (main == 0) {
            domain = dvdread.DVD_READ_MENU_VOBS;
        } else {
            domain = dvdread.DVD_READ_TITLE_VOBS;
        }

        var file = dvdread.DVDOpenFile(@ptrCast(*dvdread.dvd_reader_t, dvd_r), vts, domain);
        return Self{
            .file = file.?,
            .dvd_r = dvd_r.?,
            .video_info = video_info,

            .randy = rad.RandomAccessDecoder{
                .m2v = m2v_reader.m2vReader(dvd_reader.DvdReader).init(idx, dvd_reader.dvdReader(file)) catch unreachable,

                .gops = gops,
                .goplookup = gopl,

                .decoder_state = null,
                .video_info = video_info,
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

export fn filterGetFrame(n: c_int, activationReason: c_int, instanceData: ?*anyopaque, frameData: [*c]?*anyopaque, frameCtx: ?*vs.VSFrameContext, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) ?*const vs.VSFrame {
    _ = frameData;
    _ = frameCtx;
    _ = activationReason;

    var d = @ptrCast(*FilterData, @alignCast(std.meta.alignment(*FilterData), instanceData));

    d.randy.prefetchFrame(@intCast(u64, n), vsapi, core);

    return d.randy.fetchFrame(@intCast(u64, n));
}

export fn filterFree(instanceData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) void {
    _ = core;
    var d = @ptrCast(*FilterData, @alignCast(std.meta.alignment(*FilterData), instanceData));
    d.deinit(vsapi);

    mm.destroy(d);
    std.debug.print("filterFree\n", .{});
}

export fn filterCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
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
            .vts = @intCast(u8, vts),
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

    if (need_indexing) {
        indexer.doIndexing(dvd, idxnfo) catch |e| {
            switch (e) {
                indexer.IndexingError.fileopen => {
                    vsapi.*.mapSetError.?(out, "dvdsrc: fileopen error, does vts exist?");
                    return;
                },
                indexer.IndexingError.dvdopen => {
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

    var arl = std.ArrayList(m2v_index.OutGopInfo).init(mm);
    var framegoplookup = std.ArrayList(rad.GopLookup).init(mm);
    var total_frame_cnt: c_int = 0;

    var gop_cnt: u32 = 0;
    while (true) {
        //Readin gop from file
        const gpp = m2v_index.OutGopInfo.readIn(gop_rd.reader()) catch break;
        var gopinfo = arl.addOne() catch unreachable;
        gopinfo.* = gpp;

        //Calculate values for quickacces
        const gop_framestart = total_frame_cnt;
        total_frame_cnt += gopinfo.*.frame_cnt;

        const frmcnt = @intCast(usize, gopinfo.*.frame_cnt);
        framegoplookup.appendNTimes(undefined, frmcnt) catch unreachable;

        var arr = framegoplookup.items[framegoplookup.items.len - frmcnt ..];
        for (0..gpp.frame_cnt) |i| {
            const frm = gpp.frames[i];

            arr[frm.temporal_reference].gop = gop_cnt;
            arr[frm.temporal_reference].gop_framestart = @intCast(u32, gop_framestart);
            arr[frm.temporal_reference].decode_frame_offset = @intCast(u8, i);
        }

        gop_cnt += 1;
    }

    const gcd = std.math.gcd(27000000, seq.frame_period);

    var vi = vs.VSVideoInfo{
        .format = undefined,
        .fpsNum = 27000000 / gcd,
        .fpsDen = seq.frame_period / gcd,
        .width = @intCast(c_int, seq.width),
        .height = @intCast(c_int, seq.height),
        .numFrames = total_frame_cnt,
    };
    _ = vsapi.*.getVideoFormatByID.?(&vi.format, vs.pfYUV420P8, core);

    var psidx: ps_index.PsIndex = undefined;
    {
        var file = idxf.dir.openFile("ps_index.bin", .{}) catch unreachable;
        var bufed = std.io.bufferedReader(file.reader());
        psidx = ps_index.PsIndex.readIn(bufed.reader()) catch unreachable;
    }

    var data = mm.create(FilterData) catch unreachable;
    data.* = FilterData.init(dvd, @intCast(u8, vts), @intCast(u8, domain), vi, psidx, arl, framegoplookup);

    vsapi.*.createVideoFilter.?(out, "Full", &data.video_info, filterGetFrame, filterFree, vs.fmUnordered, null, 0, data, core);
}

export fn VapourSynthPluginInit2(plugin: ?*vs.VSPlugin, vspapi: *const vs.VSPLUGINAPI) void {
    _ = vspapi.configPlugin.?("com.jsaowji.dvdsrc", "dvdsrc", "VapourSynth DVD source", vs.VS_MAKE_VERSION(1, 0), vs.VAPOURSYNTH_API_VERSION, 0, plugin);
    _ = vspapi.registerFunction.?("Full", "dvd:data;vts:int;domain:int", "clip:vnode;", filterCreate, vs.NULL, plugin);
}
