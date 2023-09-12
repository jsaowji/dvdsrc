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

const cmn = @import("cmn.zig");

const fullfilter = @import("fullfilter.zig");

pub const BLOCKSIZE: u64 = 2048;

pub const RawAc3Filter = struct {
    const RawAc3Data = struct {
        video_info: vs.VSVideoInfo,
        data_reader: ps_reader.psReader(dvd_reader.DvdReader),
        maxsize: u64,
    };

    export fn rawAc3FilterFree(instanceData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) void {
        _ = core;
        var d = @as(*RawAc3Data, @ptrCast(@alignCast(instanceData)));
        //    d.deinit(vsapi);
        _ = vsapi;
        cmn.mm.destroy(d);
    }

    export fn rawAc3FilterGetFrame(n: c_int, activationReason: c_int, instanceData: ?*anyopaque, frameData: [*c]?*anyopaque, frameCtx: ?*vs.VSFrameContext, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) ?*const vs.VSFrame {
        _ = frameData;
        _ = frameCtx;
        _ = activationReason;
        const n64 = @as(u64, @intCast(n));
        var d = @as(*RawAc3Data, @ptrCast(@alignCast(instanceData)));

        const sk = n64 * BLOCKSIZE;

        d.data_reader.seekTo(sk) catch unreachable;

        var read_size = @min(d.maxsize - sk, BLOCKSIZE);

        var retframe = vsapi.*.newVideoFrame.?(&d.video_info.format, read_size, 1, null, core);
        var retwp = vsapi.*.getWritePtr.?(retframe, 0);

        const rd = d.data_reader.reader().readAll(retwp[0..read_size]) catch unreachable;
        std.debug.assert(rd == read_size);

        return retframe;
    }
    pub export fn rawAc3filterCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;
        var ret = fullfilter.make_sure_indexing(in, out, vsapi) catch return;
        var psidx = fullfilter.readinPsIndex(indexer.PS_INDEX_AC3[0], ret.idxf.dir) catch unreachable;

        var data = cmn.mm.create(RawAc3Data) catch unreachable;
        data.*.maxsize = psidx.total_size;
        data.*.video_info = .{
            .format = undefined,
            .fpsNum = 1,
            .fpsDen = 1,
            .width = 0,
            .height = 0,
            .numFrames = @as(c_int, @intCast((psidx.total_size + BLOCKSIZE - 1) / BLOCKSIZE)),
        };

        _ = vsapi.*.getVideoFormatByID.?(&data.video_info.format, vs.pfGray8, core);

        var domain: c_uint = undefined;
        if (ret.domain == 0) {
            domain = dvdread.DVD_READ_MENU_VOBS;
        } else {
            domain = dvdread.DVD_READ_TITLE_VOBS;
        }
        var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, ret.dvd);
        var file = dvdread.DVDOpenFile(@as(*dvdread.dvd_reader_t, @ptrCast(dvd_r)), @as(c_int, @intCast(ret.vts)), domain);

        data.*.data_reader = ps_reader.psReader(dvd_reader.DvdReader).init(psidx, dvd_reader.DvdReader.init(file.?), ps_reader.OutInfo{ .AC3 = 0 }) catch unreachable;

        vsapi.*.createVideoFilter.?(out, "RawAc3", &data.video_info, rawAc3FilterGetFrame, rawAc3FilterFree, vs.fmUnordered, null, 0, data, core);
    }
};
