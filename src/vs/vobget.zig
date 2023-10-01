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
const secto_reader = @import("../secto_reader.zig");
const m2v_index = @import("../m2v_index.zig");
const indexer = @import("../indexer.zig");

const cmn = @import("cmn.zig");

const fullfilter = @import("fullfilter.zig");

pub const VobGetFilter = struct {
    const VobGetData = struct {
        video_info: vs.VSVideoInfo,
        data_reader: secto_reader.SectoReader,
    };

    export fn VobGetFilterFree(instanceData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) void {
        _ = core;
        var d = @as(*VobGetData, @ptrCast(@alignCast(instanceData)));
        //    d.deinit(vsapi);
        _ = vsapi;
        cmn.mm.destroy(d);
    }

    export fn VobGetFilterGetFrame(n: c_int, activationReason: c_int, instanceData: ?*anyopaque, frameData: [*c]?*anyopaque, frameCtx: ?*vs.VSFrameContext, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) ?*const vs.VSFrame {
        _ = frameData;
        _ = frameCtx;
        _ = activationReason;
        const n64 = @as(u64, @intCast(n));
        var d = @as(*VobGetData, @ptrCast(@alignCast(instanceData)));

        d.data_reader.seekTo(n64 * 2048);

        var retframe = vsapi.*.newVideoFrame.?(&d.video_info.format, 2048, 1, null, core);
        var retwp = vsapi.*.getWritePtr.?(retframe, 0);

        const rd = d.data_reader.reader().readAll(retwp[0..2048]) catch unreachable;
        std.debug.assert(rd == 2048);

        return retframe;
    }

    pub export fn VobGetfilterCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;
        var data = cmn.mm.create(VobGetData) catch unreachable;

        const dvd = vsapi.*.mapGetData.?(in, "dvd", 0, 0);
        const vts = vsapi.*.mapGetInt.?(in, "vts", 0, 0);

        var ret_domain = vsapi.*.mapGetInt.?(in, "domain", 0, 0);
        var domain: c_uint = undefined;
        if (ret_domain == 0) {
            domain = dvdread.DVD_READ_MENU_VOBS;
        } else {
            domain = dvdread.DVD_READ_TITLE_VOBS;
        }
        var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, dvd);

        var sectoReader = fullfilter.openSectoReader(in, vsapi, dvd_r.?, vts, ret_domain);

        data.*.video_info = .{
            .format = undefined,
            .fpsNum = 1,
            .fpsDen = 1,
            .width = 0,
            .height = 0,
            .numFrames = @as(c_int, @intCast(sectoReader.reader.sector_cnt)),
        };
        _ = vsapi.*.getVideoFormatByID.?(&data.video_info.format, vs.pfGray8, core);

        data.*.data_reader = sectoReader.reader;
        vsapi.*.createVideoFilter.?(out, "VobGet", &data.video_info, VobGetFilterGetFrame, VobGetFilterFree, vs.fmUnordered, null, 0, data, core);
    }
};
