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
const lpcm_index = @import("../lpcm_index.zig");

const indexer = @import("../indexer.zig");
const ac3filter = @import("ac3filter.zig");

const cmn = @import("cmn.zig");

const fullfilter = @import("fullfilter.zig");
const secto_reader = @import("../secto_reader.zig");

pub const FullLPCMFilter = struct {
    const FullLPCMFilterError = error{dvddoesnot};

    const FullLPCMFilterData = struct {
        const Self = @This();

        audio_info: vs.VSAudioInfo,

        dvd_r: *dvdread.dvd_reader_t,

        psreader: ps_reader.psReader(secto_reader.SectoReader),
        lpcmi: lpcm_index.LPCMIndex,

        buffer: [3072 * 16]u8,

        fn init(dvd_r: *dvdread.dvd_reader_t, reader: secto_reader.SectoReader, audio_info: vs.VSAudioInfo, idx: ps_index.PsIndex, lpcmi: lpcm_index.LPCMIndex, adio_index: usize) !Self {
            var file = ps_reader.psReader(secto_reader.SectoReader).init(idx, reader, ps_reader.OutInfo{ .LPCM = adio_index }) catch unreachable;

            var ss = Self{
                .dvd_r = dvd_r,
                .audio_info = audio_info,
                .lpcmi = lpcmi,
                .psreader = file,
                .buffer = undefined,
            };

            return ss;
        }

        fn deinit(
            self: *Self,
            vsapi: [*c]const vs.VSAPI,
        ) void {
            dvdread.DVDClose(self.dvd_r);
            self.psreader.deinit();
            _ = vsapi;
        }
    };

    export fn fullLPCMFilterGetFrame(n: c_int, activationReason: c_int, instanceData: ?*anyopaque, frameData: [*c]?*anyopaque, frameCtx: ?*vs.VSFrameContext, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) ?*const vs.VSFrame {
        _ = frameData;
        _ = frameCtx;
        _ = activationReason;
        var d: *FullLPCMFilterData = @ptrCast(@alignCast(instanceData));

        const bytespersmaple = @as(u64, @intCast(d.audio_info.format.bytesPerSample));
        const chnls = @as(u64, @intCast(d.audio_info.format.numChannels));

        var sample_want_from = @as(u64, @intCast(n * vs.VS_AUDIO_FRAME_SAMPLES));
        var sample_want_total = @as(u64, @intCast(vs.VS_AUDIO_FRAME_SAMPLES));

        if (n == d.audio_info.numFrames - 1) {
            sample_want_total = @as(u64, @intCast(d.audio_info.numSamples)) % @as(u64, @intCast(vs.VS_AUDIO_FRAME_SAMPLES));
        }

        var current_offset_bytes: u64 = 0;
        var current_seek_offset: u64 = 0;

        var want_offset = sample_want_from * (bytespersmaple * chnls);
        var want_remaing = sample_want_total * (bytespersmaple * chnls);

        var buffer_offset: usize = 0;

        for (0..d.lpcmi.frame_sizes.items.len) |ii| {
            const fz = d.lpcmi.frame_sizes.items[ii];

            const bytes_in_this_frame = fz - 3;
            //     std.debug.print("{} {}\n", .{ current_offset_bytes + bytes_in_this_frame, want_offset });
            if (current_offset_bytes + bytes_in_this_frame > want_offset) {
                var localoffset = want_offset - current_offset_bytes;
                // std.debug.print("DID {}\n", .{localoffset});

                d.psreader.seekTo(current_seek_offset + 3 + localoffset) catch unreachable;
                var acual_read = bytes_in_this_frame - localoffset;
                //    std.debug.print("Prepread {}\n", .{acual_read});
                const jjjj = d.psreader.reader().readAll(d.buffer[buffer_offset..(buffer_offset + acual_read)]) catch unreachable;
                //   std.debug.print("post\n", .{});
                std.debug.assert(jjjj == acual_read);

                buffer_offset += acual_read;
                want_offset += acual_read;
                if (want_remaing < acual_read) {
                    break;
                }
                want_remaing -= acual_read;
            }
            current_offset_bytes += bytes_in_this_frame;
            current_seek_offset += fz;
        }
        var frnn = vsapi.*.newAudioFrame.?(&d.audio_info.format, @as(c_int, @intCast(sample_want_total)), null, core);

        //var wp0 = vsapi.*.getWritePtr.?(frnn, 0);
        //var wp1 = vsapi.*.getWritePtr.?(frnn, 1);
        var wp0u16 = @as([*]u16, @alignCast(@ptrCast(vsapi.*.getWritePtr.?(frnn, 0))));
        var wp1u16 = @as([*]u16, @alignCast(@ptrCast(vsapi.*.getWritePtr.?(frnn, 1))));
        var bufferu16 = @as([*]u16, @alignCast(@ptrCast(&d.buffer)));

        //std.debug.print("{}\n", .{sample_want_total});
        if (bytespersmaple == 2) {
            for (0..sample_want_total * chnls) |i| {
                const a = d.buffer[i * 2 + 0];
                const b = d.buffer[i * 2 + 1];

                d.buffer[i * 2 + 0] = b;
                d.buffer[i * 2 + 1] = a;
            }

            for (0..sample_want_total) |i| {
                wp0u16[i] = bufferu16[i * 2 + 0];
                wp1u16[i] = bufferu16[i * 2 + 1];
            }
        } else {
            std.debug.print("I dont have non 16 bit sample yet\n", .{});
            unreachable;
        }
        return frnn;
    }

    export fn fullLPCMFilterFree(instanceData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) void {
        _ = core;
        var d = @as(*FullLPCMFilterData, @ptrCast(@alignCast(instanceData)));
        d.deinit(vsapi);
        cmn.mm.destroy(d);
    }

    pub export fn fullLPCMFilterCreate(in: ?*const vs.VSMap, out: ?*vs.VSMap, userData: ?*anyopaque, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) callconv(.C) void {
        _ = userData;
        var ret = fullfilter.make_sure_indexing(in, out, vsapi) catch return;

        const audoindex = vsapi.*.mapGetInt.?(in, "audioidx", 0, 0);
        const audoindex_usize = @as(usize, @intCast(audoindex));

        var psidx = fullfilter.readinPsIndex(indexer.PS_INDEX_LPCM[audoindex_usize], ret.idxf.dir) catch unreachable;

        var r = ret.idxf.dir.openFile(indexer.INDEX_LPCM[audoindex_usize], .{}) catch unreachable;
        var lpcmindx = lpcm_index.LPCMIndex.readIn(r.reader()) catch unreachable;

        var ainfo = makeAudioInfo(lpcmindx, &psidx);

        var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, ret.dvd);
        var reader = fullfilter.openSectoReader(in, vsapi, dvd_r.?, ret.vts, ret.domain);

        var data = cmn.mm.create(FullLPCMFilterData) catch unreachable;
        data.* = FullLPCMFilterData.init(dvd_r.?, reader.reader, ainfo, psidx, lpcmindx, audoindex_usize) catch unreachable;

        vsapi.*.createAudioFilter.?(out, "FullLPCM", &ainfo, fullLPCMFilterGetFrame, fullLPCMFilterFree, vs.fmUnordered, null, 0, data, core);
    }
};

pub fn makeAudioInfo(lpcmindex: lpcm_index.LPCMIndex, psindex: *ps_index.PsIndex) vs.VSAudioInfo {
    _ = psindex;
    var a = lpcmindex.config_bytes[0];

    var quants = [_]u8{ 16, 20, 24 };
    const quant = quants[(a & 0b11000000) >> 6];
    var smplrates = [_]u32{ 48000, 96000 };
    const smplrate = smplrates[(a & 0b00110000) >> 4];
    const channels = (a & 0b00000111) + 1;

    const szz = @as(u64, vs.VS_AUDIO_FRAME_SAMPLES);

    var total_data_bytes: u64 = 0;
    for (lpcmindex.frame_sizes.items) |f| {
        total_data_bytes += f - 3;
    }

    const bytespersmaple = (quant + 7) / 8;
    std.debug.assert(total_data_bytes % (bytespersmaple * channels) == 0);
    const numSamples: usize = total_data_bytes / (bytespersmaple * channels);
    //  std.debug.print("umSp {}\n", .{numSamples});

    if (channels != 2) {
        std.debug.print("Want sample havent looked more than 2 ch yet\n", .{});
        std.debug.assert(false);
    }

    var ainfo: vs.VSAudioInfo = .{
        .format = .{
            .sampleType = vs.stInteger,
            .bitsPerSample = @intCast(quant),
            .bytesPerSample = @intCast((quant + 7) / 8),
            .numChannels = channels,
            .channelLayout = 3,
            //TODO: dont hardcode
        },
        .sampleRate = @intCast(smplrate),
        .numSamples = @as(i64, @intCast(numSamples)),
        .numFrames = @as(c_int, @intCast((@as(u64, numSamples) + szz - 1) / szz)),
    };
    return ainfo;
}
