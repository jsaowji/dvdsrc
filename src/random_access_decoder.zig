const std = @import("std");

const vs = @import("bindings/vapoursynth.zig");
const dvdread = @import("./bindings/dvdread.zig");
const mpeg2 = @import("./bindings/mpeg2.zig");

const dvd_reader = @import("./dvd_reader.zig");
const m2v_reader = @import("./m2v_reader.zig");
const ps_index = @import("./ps_index.zig");
const m2v_index = @import("./m2v_index.zig");
const utils = @import("./utils.zig");

const debugPrint = utils.debugPrint;

pub const GopLookup = struct {
    gop: u32 = 0,
    decode_frame_offset: u8 = 0,
    gop_framestart: u32 = 0,
};

const mm = std.heap.c_allocator;

pub const RandomAccessDecoder = struct {
    const Self = @This();

    m2v: m2v_reader.m2vReader(dvd_reader.DvdReader),
    gops: std.ArrayList(m2v_index.OutGopInfo),
    goplookup: std.ArrayList(GopLookup),

    video_info: vs.VSVideoInfo,

    decoder_state: ?struct {
        decoder: *mpeg2.mpeg2dec_t,
        slice_cnt: u8,
        gop: usize,
        buf: []u8,
        cache: [20]?struct {
            frame: *vs.VSFrame,
            temporal: u8,
        },
        has_prev_gop: bool,
    },

    pub fn deinit(self: *Self) void {
        self.goplookup.deinit();
        self.gops.deinit();
        self.m2v.deinit();
    }

    pub fn fetchFrame(self: *Self, n_display_order: u64) *vs.VSFrame {
        const gopl = self.goplookup.items[n_display_order];
        const wanted_gop = self.gops.items[gopl.gop];
        const wanted_frame = wanted_gop.frames[gopl.decode_frame_offset];

        var ds = &self.decoder_state.?;

        debugPrint("{} {} \n", .{ gopl.gop, ds.gop });
        std.debug.assert(gopl.gop == ds.gop);

        debugPrint("looking for frame deco {} temporal {}\n", .{ gopl.decode_frame_offset, wanted_frame.temporal_reference });

        for (0..ds.cache.len) |i| {
            if (ds.cache[i] != null) {
                var vv = &ds.cache[i].?;
                debugPrint("in cache temporal {}\n", .{vv.temporal});

                if (vv.temporal == wanted_frame.temporal_reference) {
                    var frame = vv.frame;
                    ds.cache[i] = null;
                    return frame;
                }
            }
        }
        unreachable;
    }

    pub fn prefetchFrame(self: *Self, n_display_order: u64, vsapi: [*c]const vs.VSAPI, core: ?*vs.VSCore) void {
        const gopl = self.goplookup.items[n_display_order];
        const wanted_gop = self.gops.items[gopl.gop];
        const wanted_frame = wanted_gop.frames[gopl.decode_frame_offset];

        debugPrint("prefetch decode {} temporal {}  gop {}\n", .{ gopl.decode_frame_offset, wanted_frame.temporal_reference, gopl.gop });
        debugPrint("wanted_gop closed {}\n", .{wanted_gop.closed});

        var need_new_decoder: bool = undefined;
        var need_new_data: bool = undefined;
        var flush_current: bool = undefined;

        if (self.decoder_state != null) {
            var ds = &self.decoder_state.?;
            debugPrint("current decoder gop {}\n", .{ds.gop});

            if (gopl.gop == ds.gop) {
                if (gopl.decode_frame_offset < ds.slice_cnt) {
                    var found = false;
                    for (self.decoder_state.?.cache) |value| {
                        if (value != null) {
                            if (value.?.temporal == wanted_frame.temporal_reference) {
                                found = true;
                                break;
                            }
                        }
                    }
                    if (found) {
                        //No need to do anything frame is in cache
                        return;
                    } else {
                        //Frame is not in cache even though it should have been new decoder needed
                        need_new_decoder = true;
                        need_new_data = true;
                        flush_current = false;
                    }
                } else {
                    if (!wanted_frame.decodable_wo_prev_gop and !ds.has_prev_gop) {
                        //Need new decoder because pattern <prevgop> <BBI...> in display and last decoder started on this GOP with I
                        need_new_decoder = true;
                        need_new_data = true;
                        flush_current = false;
                    } else {
                        //Good we can continue as decoding usual
                        need_new_decoder = false;
                        need_new_data = false;
                        flush_current = false;
                    }
                }
            } else if (gopl.gop == ds.gop + 1) {
                //If next frame is in next gop continue as usual
                if (!wanted_gop.closed) {
                    flush_current = true;
                    need_new_decoder = false;
                    need_new_data = true;
                } else {
                    //Just to be safe (dunno if needed)
                    flush_current = false;
                    need_new_decoder = true;
                    need_new_data = true;
                }
            } else {
                need_new_decoder = true;
                need_new_data = true;
                flush_current = false;
            }
        } else {
            need_new_decoder = true;
            need_new_data = true;
            flush_current = false;
        }
        debugPrint("flush_current {} need_new_decoder {} need_new_data {}\n", .{ flush_current, need_new_decoder, need_new_data });

        if (flush_current) {
            var ds = &self.decoder_state.?;

            for (0..ds.cache.len) |i| {
                if (ds.cache[i] != null) {
                    vsapi.*.freeFrame.?(ds.cache[i].?.frame);
                }
                ds.cache[i] = null;
            }

            if (wanted_gop.closed) {
                mpeg2.mpeg2_reset(ds.decoder, 1);
            } else {
                while (mpeg2.mpeg2_parse(ds.decoder) != mpeg2.STATE_BUFFER) {}

                mpeg2.mpeg2_reset(ds.decoder, 0);
            }
        }

        if (need_new_decoder) {
            std.debug.assert(!flush_current);
            std.debug.assert(need_new_data);

            var decoder = mpeg2.mpeg2_init().?;

            var has_prev_gop = false;

            debugPrint("decodable_wo_prev_gop {}\n", .{wanted_frame.decodable_wo_prev_gop});
            if (wanted_frame.decodable_wo_prev_gop) {
                //Dont't Need prev gop
            } else {
                //Need prev gop
                const prv_gop = self.gops.items[gopl.gop - 1];

                var buf = mm.alloc(u8, wanted_gop.sequence_info_start - prv_gop.sequence_info_start + 4) catch unreachable;
                defer mm.free(buf);

                self.m2v.seek(prv_gop.sequence_info_start);

                const srr = self.m2v.reader().readAtLeast(buf, buf.len) catch unreachable;
                std.debug.assert(srr == buf.len);

                mpeg2.mpeg2_buffer(decoder, buf.ptr, buf.ptr + buf.len);
                while (true) {
                    var status = mpeg2.mpeg2_parse(decoder);
                    std.debug.assert(status != mpeg2.STATE_INVALID);

                    if (status == mpeg2.STATE_BUFFER) {
                        break;
                    }
                }
                mpeg2.mpeg2_reset(decoder, 0);
                has_prev_gop = true;
            }

            //Free old decoder
            if (self.decoder_state != null) {
                mpeg2.mpeg2_close(self.decoder_state.?.decoder);
                mm.free(self.decoder_state.?.buf);
                for (self.decoder_state.?.cache) |cc| {
                    if (cc != null) {
                        vsapi.*.freeFrame.?(cc.?.frame);
                    }
                }
            }

            self.decoder_state = .{
                .decoder = decoder,
                .gop = gopl.gop,
                .buf = undefined,
                .slice_cnt = 0,
                .cache = undefined,
                .has_prev_gop = has_prev_gop,
            };
            for (0..self.decoder_state.?.cache.len) |a| {
                self.decoder_state.?.cache[a] = null;
            }
        }

        if (need_new_data) {
            var ds = &self.decoder_state.?;

            var buf: []u8 = undefined;
            var buf_len: usize = undefined;

            debugPrint("new data from gop @{X}\n", .{wanted_gop.sequence_info_start});

            if (gopl.gop + 1 != self.gops.items.len) {
                debugPrint("not last gop\n", .{});
                const nxt_gop = self.gops.items[gopl.gop + 1];

                buf = mm.alloc(u8, nxt_gop.sequence_info_start - wanted_gop.sequence_info_start + 4) catch unreachable;

                self.m2v.seek(wanted_gop.sequence_info_start);

                const srr = self.m2v.reader().readAtLeast(buf, buf.len) catch unreachable;
                //std.debug.print("got {} expedted {}\n", .{ srr, buf.len });
                std.debug.assert(srr == buf.len);
                buf_len = buf.len;
            } else {
                debugPrint("last gop\n", .{});
                buf = mm.alloc(u8, 1024 * 1024 * 30) catch unreachable;

                self.m2v.seek(wanted_gop.sequence_info_start);

                buf_len = self.m2v.reader().readAtLeast(buf, buf.len) catch unreachable;
                std.debug.assert(buf_len < buf.len);
            }

            mpeg2.mpeg2_buffer(ds.decoder, buf.ptr, buf.ptr + buf_len);

            //Advance one gop when old decoder was used for new data
            if (!need_new_decoder) {
                ds.gop += 1;
                ds.slice_cnt = 0;

                mm.free(ds.buf);
                ds.has_prev_gop = true;
            }

            ds.buf = buf;
        }

        //We have a decoder now
        var ds = &self.decoder_state.?;
        var info = mpeg2.mpeg2_info(ds.decoder);

        var continue_decoding = true;

        while (continue_decoding) {
            var state = mpeg2.mpeg2_parse(ds.decoder);

            debugPrint(" DECODE {s} slice_cnt {}\n", .{ utils.mpeg2decStateToString(state), ds.slice_cnt });

            switch (state) {
                mpeg2.STATE_PICTURE => {
                    const a = wanted_gop.frames[ds.slice_cnt].temporal_reference;
                    const b = info.*.current_picture.*.temporal_reference;
                    if (a != b) {
                        std.debug.print("temp a {} temp b {}\n", .{ a, b });
                        unreachable;
                    }
                },
                mpeg2.STATE_SLICE, mpeg2.STATE_END => {
                    const seq = info.*.sequence.*;

                    if (info.*.current_fbuf != 0) {
                        const fbuf = info.*.current_fbuf.*;
                        var frame_at_slice = &wanted_gop.frames[ds.slice_cnt];

                        if (!frame_at_slice.decodable_wo_prev_gop and !ds.has_prev_gop) {
                            //Dont'cache
                        } else {
                            var did_cache_something = false;
                            for (0..ds.cache.len) |i| {
                                if (ds.cache[i] == null) {
                                    var f2 = vsapi.*.newVideoFrame.?(&self.video_info.format, self.video_info.width, self.video_info.height, null, core);

                                    writeFbufToVsframe(f2, vsapi, fbuf, seq, frame_at_slice, ds.slice_cnt, gopl.gop);
                                    ds.cache[i] = .{
                                        .frame = f2.?,
                                        .temporal = frame_at_slice.temporal_reference,
                                    };
                                    debugPrint("cached deco {} temporal {}\n", .{ ds.slice_cnt, frame_at_slice.temporal_reference });
                                    did_cache_something = true;
                                    break;
                                }
                            }
                            std.debug.assert(did_cache_something);
                        }

                        //Don't wast time decoding too much
                        if (ds.slice_cnt == gopl.decode_frame_offset) {
                            continue_decoding = false;
                        }
                        ds.slice_cnt += 1;
                    } else {
                        debugPrint("Got a slice but no frame\n", .{});
                        unreachable;
                    }
                },
                mpeg2.STATE_INVALID => {
                    unreachable;
                },
                mpeg2.STATE_BUFFER => {
                    break;
                },
                else => {
                    //maybe unreachable ??
                },
            }
        }
        std.debug.assert(!continue_decoding);
    }
};

fn writeFbufToVsframe(f: ?*vs.VSFrame, vsapi: [*c]const vs.VSAPI, fbuf: mpeg2.mpeg2_fbuf_t, seq: mpeg2.mpeg2_sequence_t, frm: *const m2v_index.Frame, index_in_gop: u8, gop: u64) void {
    //Copy plane data
    {
        var wp0 = vsapi.*.getWritePtr.?(f, 0);
        var wp1 = vsapi.*.getWritePtr.?(f, 1);
        var wp2 = vsapi.*.getWritePtr.?(f, 2);

        var st0 = @intCast(usize, vsapi.*.getStride.?(f, 0));
        var st1 = @intCast(usize, vsapi.*.getStride.?(f, 1));
        var st2 = @intCast(usize, vsapi.*.getStride.?(f, 2));

        //TODO: vapoursynth helpers bitblt
        for (0..seq.height) |h| {
            const slp = fbuf.buf[0] + h * seq.width;
            const dlp = wp0 + h * st0;

            @memcpy(dlp[0..seq.width], slp[0..seq.width]);
        }
        for (0..seq.chroma_height) |h| {
            const slp = fbuf.buf[1] + h * seq.chroma_width;
            const dlp = wp1 + h * st1;

            @memcpy(dlp[0..seq.chroma_width], slp[0..seq.chroma_width]);
        }
        for (0..seq.chroma_height) |h| {
            const slp = fbuf.buf[2] + h * seq.chroma_width;
            const dlp = wp2 + h * st2;

            @memcpy(dlp[0..seq.chroma_width], slp[0..seq.chroma_width]);
        }
    }

    var map = vsapi.*.getFramePropertiesRW.?(f).?;
    if (!frm.progressive) {
        if (frm.tff) {
            _ = vsapi.*.mapSetInt.?(map, "_FieldBased", vs.VSC_FIELD_TOP, vs.maReplace);
        } else {
            _ = vsapi.*.mapSetInt.?(map, "_FieldBased", vs.VSC_FIELD_BOTTOM, vs.maReplace);
        }
    }

    switch (frm.frametype) {
        m2v_index.FrameType.I => {
            _ = vsapi.*.mapSetData.?(map, "_PictType", "I", 1, vs.dtUtf8, vs.maAppend);
        },
        m2v_index.FrameType.P => {
            _ = vsapi.*.mapSetData.?(map, "_PictType", "P", 1, vs.dtUtf8, vs.maAppend);
        },
        m2v_index.FrameType.B => {
            _ = vsapi.*.mapSetData.?(map, "_PictType", "B", 1, vs.dtUtf8, vs.maAppend);
        },
    }

    //SAR
    if (seq.pixel_width > 0 and seq.pixel_height > 0) {
        _ = vsapi.*.mapSetInt.?(map, "_SARNum", seq.pixel_width, vs.maReplace);
        _ = vsapi.*.mapSetInt.?(map, "_SARDen", seq.pixel_height, vs.maReplace);
    }

    //Color stuff
    {
        var primaries: c_int = undefined;

        switch (seq.colour_primaries) {
            1 => primaries = vs.VSC_PRIMARIES_BT709,
            4 => primaries = vs.VSC_PRIMARIES_BT470_M,
            5 => primaries = vs.VSC_PRIMARIES_BT470_BG,
            6 => primaries = vs.VSC_PRIMARIES_ST170_M,
            7 => primaries = vs.VSC_PRIMARIES_ST240_M,
            else => primaries = vs.VSC_PRIMARIES_UNSPECIFIED,
        }

        var transfer: c_int = undefined;
        switch (seq.transfer_characteristics) {
            1 => transfer = vs.VSC_TRANSFER_BT709,
            4 => transfer = vs.VSC_TRANSFER_BT470_M,
            5 => transfer = vs.VSC_TRANSFER_BT470_BG,
            6 => transfer = vs.VSC_TRANSFER_BT601, // SMPTE 170M
            7 => transfer = vs.VSC_TRANSFER_ST240_M,
            8 => transfer = vs.VSC_TRANSFER_LINEAR,
            else => transfer = vs.VSC_TRANSFER_UNSPECIFIED,
        }
        var matrix: c_int = undefined;
        switch (seq.matrix_coefficients) {
            1 => matrix = vs.VSC_MATRIX_BT709,
            4 => matrix = vs.VSC_MATRIX_FCC,
            5 => matrix = vs.VSC_MATRIX_BT470_BG,
            6 => matrix = vs.VSC_MATRIX_ST170_M,
            7 => matrix = vs.VSC_MATRIX_ST240_M,
            else => matrix = vs.VSC_MATRIX_UNSPECIFIED,
        }
        _ = vsapi.*.mapSetInt.?(map, "_Matrix", matrix, vs.maReplace);
        _ = vsapi.*.mapSetInt.?(map, "_Transfer", transfer, vs.maReplace);
        _ = vsapi.*.mapSetInt.?(map, "_Primaries", primaries, vs.maReplace);

        _ = vsapi.*.mapSetInt.?(map, "_ChromaLocation", vs.VSC_CHROMA_LEFT, vs.maReplace);
    }

    //Debug stuff
    {
        var progressive: i64 = 1;
        var rff: i64 = 0;
        var tff: i64 = 0;
        if (!frm.progressive) {
            progressive = 0;
        }
        if (frm.repeat) {
            rff = 1;
        }
        if (frm.tff) {
            tff = 1;
        }
        _ = vsapi.*.mapSetInt.?(map, "_DbgProgressive", progressive, vs.maReplace);
        _ = vsapi.*.mapSetInt.?(map, "_DbgTFF", rff, vs.maReplace);
        _ = vsapi.*.mapSetInt.?(map, "_DbgRFF", rff, vs.maReplace);
        _ = vsapi.*.mapSetInt.?(map, "_DbgIndexInGop", index_in_gop, vs.maReplace);
        _ = vsapi.*.mapSetInt.?(map, "_DbgGop", @intCast(i64, gop), vs.maReplace);
    }
}
