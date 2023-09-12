const std = @import("std");
const vs = @import("../bindings/vapoursynth.zig");

const mpeg2 = @import("../bindings/mpeg2.zig");
const dvd_reader = @import("../dvd_reader.zig");
const ps_index = @import("../ps_index.zig");
const utils = @import("../utils.zig");
const dvdread = @import("../manual_dvdread.zig");

const rad = @import("../random_access_decoder_ac3.zig");
const index_manager = @import("../index_manager.zig");
const m2v_index = @import("../m2v_index.zig");
const indexer = @import("../indexer.zig");
const ps_extracter = @import("../ps_extracter.zig");
const ac3_index = @import("../ac3_index.zig");

const cmn = @import("cmn.zig");
const a52 = @import("../bindings/a52.zig");

pub const Ac3Filter = struct {
    const Ac3FilterData = struct {
        const Self = @This();

        radec: rad.Ac3RandomAccessDecoder(std.fs.File),

        fn init(path: []const u8, ac3index: ac3_index.AC3Index, audio_info: vs.VSAudioInfo) Self {
            var file = std.fs.openFileAbsolute(path, .{}) catch unreachable;
            var ss = Self{
                .radec = rad.Ac3RandomAccessDecoder(std.fs.File).init(file, ac3index, audio_info),
            };
            return ss;
        }

        fn deinit(
            self: *Self,
            vsapi: [*c]const vs.VSAPI,
        ) void {
            self.radec.deinit();
            _ = vsapi;
        }
    };

    export fn ac3filterGetFrame(n: c_int, activationReason: c_int, instanceData: ?*anyopaque, frameData: [*c]?*anyopaque, frameCtx: ?*vs.VSFrameContext, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) ?*const vs.VSFrame {
        _ = frameData;
        _ = frameCtx;
        _ = activationReason;
        var d: *Ac3FilterData = @ptrCast(@alignCast(instanceData));

        return d.radec.getFrame(n, core, vsapi);
    }

    export fn ac3filterFree(instanceData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) void {
        _ = core;
        var d: *Ac3FilterData = @ptrCast(@alignCast(instanceData));
        d.deinit(vsapi);
        cmn.mm.destroy(d);
    }

    pub export fn ac3filterCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;

        const path = vsapi.*.mapGetData.?(in, "path", 0, 0);
        const pathlenn = std.mem.indexOfSentinel(u8, 0, path);

        var fl = std.fs.openFileAbsolute(path[0..pathlenn], .{}) catch unreachable;
        var flrdraw = fl.reader();
        var flrd1 = std.io.bufferedReader(flrdraw);
        var flrd = flrd1.reader();

        var ac3indexer = indexer.Ac3Indexerer.init();

        var buf = cmn.mm.alloc(u8, 2048) catch unreachable;
        defer cmn.mm.free(buf);

        while (true) {
            const rd = flrd.readAll(buf) catch unreachable;

            ac3indexer.writeAll(buf[0..rd]) catch unreachable;

            if (rd != buf.len) break;
        }

        var idxnfo = index_manager.IndexInfo.init(
            path,
            index_manager.ModeInfo.ac3,
        ) catch unreachable;
        defer idxnfo.deinit();

        //var idxf = index_manager.IndexManager.getIndexFolder(idxnfo) catch unreachable;
        //var need_indexing = false;

        //if (!idxf.existed) {
        //    need_indexing = true;
        //}
        //
        ////Check if all files really exists
        //_ = idxf.dir.statFile("sequence.bin") catch {
        //    need_indexing = true;
        //};
        //_ = idxf.dir.statFile("gops.bin") catch {
        //    need_indexing = true;
        //};
        //
        //if (need_indexing) {
        //    indexer.doIndexingM2v(idxnfo) catch |e| {
        //        switch (e) {
        //            else => {
        //                std.debug.print("{?}\n", .{e});
        //                vsapi.*.mapSetError.?(out, "dvdsrc: could not index unk error");
        //                return;
        //            },
        //        }
        //    };
        //}

        //var seq_file = idxf.dir.openFile("sequence.bin", .{}) catch unreachable;
        //var seq = m2v_index.readinSequence(seq_file.reader()) catch unreachable;
        //
        //var gop_file = idxf.dir.openFile("gops.bin", .{}) catch unreachable;
        //var gop_rd = std.io.bufferedReader(gop_file.reader());

        const ac3index = ac3indexer.final_index;

        //ac3index.flags
        //assume stereo
        //A52_STEREO
        var ainfo = makeAudioInfo(ac3index);

        var data = cmn.mm.create(Ac3FilterData) catch unreachable;
        data.* = Ac3FilterData.init(idxnfo.path, ac3index, ainfo);

        vsapi.*.createAudioFilter.?(out, "AC3", &ainfo, ac3filterGetFrame, ac3filterFree, vs.fmUnordered, null, 0, data, core);
        fl.close();
    }
};

pub fn makeAudioInfo(ac3index: ac3_index.AC3Index) vs.VSAudioInfo {
    var numSamples = ac3index.frame_sizes.items.len * 6 * 256;
    const szz = @as(u64, vs.VS_AUDIO_FRAME_SAMPLES);

    var ainfo: vs.VSAudioInfo = .{
        .format = .{
            .sampleType = vs.stFloat,
            .bitsPerSample = 32,
            .bytesPerSample = 4,
            .numChannels = 99,
            .channelLayout = 99,
        },
        .sampleRate = @as(c_int, @intCast(ac3index.sample_rate)),
        .numSamples = @as(i64, @intCast(numSamples)),
        .numFrames = @as(c_int, @intCast((@as(u64, numSamples) + szz - 1) / szz)),
    };

    if (ac3index.flags == a52.A52_STEREO) {
        ainfo.format.numChannels = 2;
        ainfo.format.channelLayout = 3;
    } else if (ac3index.flags == a52.A52_3F2R + a52.A52_LFE) {
        //
        ainfo.format.numChannels = 6;
        ainfo.format.channelLayout = (1 << vs.acFrontLeft) + (1 << vs.acFrontRight) + (1 << vs.acFrontCenter) + (1 << vs.acLowFrequency) + (1 << vs.acSideLeft) + (1 << vs.acSideRight);
    } else if (ac3index.flags == a52.A52_3F2R) {
        //
        ainfo.format.numChannels = 5;
        ainfo.format.channelLayout = (1 << vs.acFrontLeft) + (1 << vs.acFrontRight) + (1 << vs.acFrontCenter) + (1 << vs.acSideLeft) + (1 << vs.acSideRight);
    } else {
        unreachable;
    }

    //std.debug.print("{?}\n", .{ainfo});
    return ainfo;
}
