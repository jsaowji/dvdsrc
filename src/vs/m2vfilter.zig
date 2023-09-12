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

pub const M2vFilter = struct {
    const M2vFilterData = struct {
        const Self = @This();

        video_info: vs.VSVideoInfo,
        file: std.fs.File,
        randy: rad.RandomAccessDecoder(std.fs.File),

        fn init(path: []const u8, video_info: vs.VSVideoInfo, goplookup: m2v_index.GopLookup, fconf: cmn.FilterConfiguration) Self {
            var file = std.fs.openFileAbsolute(path, .{}) catch unreachable;

            var ss = Self{
                .file = file,
                .video_info = video_info,
                .randy = .{
                    .m2v = file,
                    .gopy = goplookup,
                    .decoder_state = null,
                    .video_info = video_info,
                    .guess_ar = fconf.guess_ar,
                    .fake_vfr = fconf.fake_vfr,
                    .extra_data_frames = undefined,
                },
            };
            for (0..ss.randy.extra_data_frames.len) |i| {
                ss.randy.extra_data_frames[i] = null;
            }
            return ss;
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

        if (d.randy.getframe_exit_early(@as(u64, @intCast(n)), vsapi, core)) |a| {
            return a;
        }
        d.randy.prefetchFrame(@as(u64, @intCast(n)), vsapi, core);
        return d.randy.fetchFrame(@as(u64, @intCast(n)), vsapi);
    }

    export fn filterFree(instanceData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) void {
        _ = core;
        var d: *M2vFilterData = @ptrCast(@alignCast(instanceData));
        d.deinit(vsapi);
        cmn.mm.destroy(d);
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
                        std.debug.print("{?}\n", .{e});
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

        const goplookup = m2v_index.GopLookup.init(cmn.mm, gop_rd.reader()) catch unreachable;

        var fake_vfr = goplookup.framestats.rff != 0;
        _ = fake_vfr;
        var vi = rad.seqToVideoInfo(&seq, goplookup.total_frame_cnt);

        _ = vsapi.*.getVideoFormatByID.?(&vi.format, vs.pfYUV420P8, core);

        var data = cmn.mm.create(M2vFilterData) catch unreachable;
        data.* = M2vFilterData.init(idxnfo.path, vi, goplookup, .{
            .guess_ar = true,
            .fake_vfr = true,
        });

        vsapi.*.createVideoFilter.?(out, "M2V", &data.video_info, filterGetFrame, filterFree, vs.fmUnordered, null, 0, data, core);
    }
};
