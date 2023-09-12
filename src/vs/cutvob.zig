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

const fullfilter = @import("fullfilter.zig");

pub const VobFilter = struct {
    const VobData = struct {
        video_info: vs.VSVideoInfo,
        data_reader: secto_reader.SectoReader,
    };

    export fn vobFilterFree(instanceData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) void {
        _ = core;
        var d = @as(*VobData, @ptrCast(@alignCast(instanceData)));
        //    d.deinit(vsapi);
        _ = vsapi;
        cmn.mm.destroy(d);
    }

    export fn vobFilterGetFrame(n: c_int, activationReason: c_int, instanceData: ?*anyopaque, frameData: [*c]?*anyopaque, frameCtx: ?*vs.VSFrameContext, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) ?*const vs.VSFrame {
        _ = frameData;
        _ = frameCtx;
        _ = activationReason;
        const n64 = @as(u64, @intCast(n));
        var d = @as(*VobData, @ptrCast(@alignCast(instanceData)));

        const sk = n64 * 2048;

        d.data_reader.seekTo(sk);

        var retframe = vsapi.*.newVideoFrame.?(&d.video_info.format, 2048, 1, null, core);
        var retwp = vsapi.*.getWritePtr.?(retframe, 0);

        const rd = d.data_reader.reader().readAll(retwp[0..2048]) catch unreachable;
        std.debug.assert(rd == 2048);

        return retframe;
    }
    pub export fn vobfilterCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;

        const dvd = vsapi.*.mapGetData.?(in, "dvd", 0, 0);
        const vts = vsapi.*.mapGetInt.?(in, "vts", 0, 0);
        const domain = vsapi.*.mapGetInt.?(in, "domain", 0, 0);
        var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, dvd);
        var secto = fullfilter.openSectoReader(in, vsapi, dvd_r.?, vts, domain);

        var data = cmn.mm.create(VobData) catch unreachable;
        data.*.data_reader = secto.reader;
        data.*.video_info = .{
            .format = undefined,
            .fpsNum = 1,
            .fpsDen = 1,
            .width = 2048,
            .height = 1,
            .numFrames = @as(c_int, @intCast(secto.reader.block_cnt)),
        };

        _ = vsapi.*.getVideoFormatByID.?(&data.video_info.format, vs.pfGray8, core);
        vsapi.*.createVideoFilter.?(out, "CutVob", &data.video_info, vobFilterGetFrame, vobFilterFree, vs.fmUnordered, null, 0, data, core);
    }
};
