const std = @import("std");
const vs = @import("../bindings/vapoursynth.zig");

const mpeg2 = @import("../bindings/mpeg2.zig");
const dvd_reader = @import("../dvd_reader.zig");
const ps_reader = @import("../ps_reader.zig");
const ps_index = @import("../ps_index.zig");
const utils = @import("../utils.zig");
const dvdread = @import("../manual_dvdread.zig");

const rad = @import("../random_access_decoder_ac3.zig");
const index_manager = @import("../index_manager.zig");
const ac3_index = @import("../ac3_index.zig");
const indexer = @import("../indexer.zig");
const ac3filter = @import("ac3filter.zig");
const secto_reader = @import("../secto_reader.zig");

const cmn = @import("cmn.zig");

const fullfilter = @import("fullfilter.zig");

pub const FullAc3Filter = struct {
    const FullAc3FilterError = error{dvddoesnot};

    const FullAc3FilterData = struct {
        const Self = @This();

        audio_info: vs.VSAudioInfo,

        dvd_r: *dvdread.dvd_reader_t,

        randy: rad.Ac3RandomAccessDecoder(ps_reader.psReader(secto_reader.SectoReader)),

        fn init(dvd_r: *dvdread.dvd_reader_t, reader: secto_reader.SectoReader, audio_info: vs.VSAudioInfo, idx: ps_index.PsIndex, ac3i: ac3_index.AC3Index, adio_index: usize) !Self {
            var file = ps_reader.psReader(secto_reader.SectoReader).init(idx, reader, ps_reader.OutInfo{ .AC3 = adio_index }) catch unreachable;
            var randy = rad.Ac3RandomAccessDecoder(ps_reader.psReader(secto_reader.SectoReader)).init(file, ac3i, audio_info);

            var ss = Self{
                .dvd_r = dvd_r,
                .audio_info = audio_info,

                .randy = randy,
            };

            return ss;
        }

        fn deinit(
            self: *Self,
            vsapi: [*c]const vs.VSAPI,
        ) void {
            dvdread.DVDClose(self.dvd_r);
            self.randy.deinit();
            _ = vsapi;
        }
    };

    export fn fullAc3FilterGetFrame(n: c_int, activationReason: c_int, instanceData: ?*anyopaque, frameData: [*c]?*anyopaque, frameCtx: ?*vs.VSFrameContext, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) ?*const vs.VSFrame {
        _ = frameData;
        _ = frameCtx;
        _ = activationReason;

        var d: *FullAc3FilterData = @ptrCast(@alignCast(instanceData));

        return d.randy.getFrame(n, core, vsapi);
    }

    export fn fullAc3FilterFree(instanceData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) void {
        _ = core;
        var d = @as(*FullAc3FilterData, @ptrCast(@alignCast(instanceData)));
        d.deinit(vsapi);
        cmn.mm.destroy(d);
    }

    pub export fn fullAc3FilterCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;
        var ret = fullfilter.make_sure_indexing(in, out, vsapi) catch return;

        const audoindex = vsapi.*.mapGetInt.?(in, "audioidx", 0, 0);
        const audoindex_usize = @as(usize, @intCast(audoindex));

        var psidx = fullfilter.readinPsIndex(indexer.PS_INDEX_AC3[audoindex_usize], ret.idxf.dir) catch unreachable;

        var r = ret.idxf.dir.openFile(indexer.INDEX_AC3[audoindex_usize], .{}) catch unreachable;
        var ac3indx = ac3_index.AC3Index.readIn(r.reader()) catch unreachable;

        var ainfo = ac3filter.makeAudioInfo(ac3indx);

        var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, ret.dvd);
        var reader = fullfilter.openSectoReader(in, vsapi, dvd_r.?, ret.vts, ret.domain);

        var data = cmn.mm.create(FullAc3FilterData) catch unreachable;
        data.* = FullAc3FilterData.init(dvd_r.?, reader.reader, ainfo, psidx, ac3indx, audoindex_usize) catch unreachable;

        vsapi.*.createAudioFilter.?(out, "AC3", &ainfo, fullAc3FilterGetFrame, fullAc3FilterFree, vs.fmUnordered, null, 0, data, core);
    }
};
