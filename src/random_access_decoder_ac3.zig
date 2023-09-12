const std = @import("std");

const vs = @import("bindings/vapoursynth.zig");
const ac3_index = @import("ac3_index.zig");
const mpeg2 = @import("./bindings/mpeg2.zig");

const a52 = @import("./bindings/a52.zig");

pub fn Ac3RandomAccessDecoder(comptime Ac3StreamDataSource: type) type {
    return struct {
        const Self = @This();

        audio_info: vs.VSAudioInfo,
        ac3index: ac3_index.AC3Index,

        buffer: []u8,

        a52_state: *a52.a52_state_t,

        last_ac3_frame: usize,
        file: Ac3StreamDataSource,

        pub fn init(file: Ac3StreamDataSource, ac3index: ac3_index.AC3Index, audio_info: vs.VSAudioInfo) Self {
            var ss = Self{
                .a52_state = a52.a52_init(0).?,

                .audio_info = audio_info,
                .ac3index = ac3index,
                .file = file,
                .buffer = std.heap.c_allocator.alloc(u8, 8192) catch unreachable,
                .last_ac3_frame = 0,
            };

            return ss;
        }

        pub fn deinit(
            self: *Self,
            //vsapi: [*c]const vs.VSAPI,
        ) void {
            std.heap.c_allocator.free(self.buffer);

            a52.a52_free(self.a52_state);
            //TODO:
            //self.file.deinit();

            //_ = vsapi;
        }

        pub fn getFrame(self: *Self, vsframe_n: c_int, core: ?*vs.VSCore, vsapi: [*c]const vs.VSAPI) ?*const vs.VSFrame {
            var d = self;

            const total_sample_cnt = d.ac3index.frame_sizes.items.len * 256 * 6;

            const sample_want_start = vs.VS_AUDIO_FRAME_SAMPLES * vsframe_n;

            var frameoffset = @as(u64, @intCast(sample_want_start)) / @as(u64, 256 * 6);
            var start_offset1 = vs.VS_AUDIO_FRAME_SAMPLES * vsframe_n - @as(c_int, @intCast(frameoffset)) * 256 * 6;
            var start_offset = @as(usize, @intCast(start_offset1));
            std.debug.assert(start_offset == 0);

            var flags: c_int = 0;
            var sample_rate: c_int = 0;
            var bit_rate: c_int = 0;

            var sampels_want = @min(vs.VS_AUDIO_FRAME_SAMPLES, @as(c_int, @intCast(total_sample_cnt)) - sample_want_start);

            var level: a52.level_t = 1;
            var bias: a52.sample_t = 0;

            //buffer prev frame
            //TODO: only one ?
            if (frameoffset != 0 and self.last_ac3_frame != frameoffset - 1) {
                var offset: u64 = 0;
                var size = d.ac3index.frame_sizes.items[frameoffset - 1];
                for (0..frameoffset - 1) |i| {
                    offset += @as(u64, d.ac3index.frame_sizes.items[i]);
                }
                d.file.seekTo(offset) catch unreachable;
                const rd = d.file.reader().readAll(d.buffer[0..size]) catch unreachable;
                std.debug.assert(rd == size);

                _ = a52.a52_syncinfo(d.buffer.ptr, &flags, &sample_rate, &bit_rate);
                _ = a52.a52_frame(self.a52_state, d.buffer.ptr, &flags, &level, bias);
                for (0..6) |_| {
                    _ = a52.a52_block(self.a52_state);
                }
                std.debug.assert(self.ac3index.flags == flags);
            }
            var samples = a52.a52_samples(self.a52_state);

            std.debug.assert(vs.VS_AUDIO_FRAME_SAMPLES % (6 * 256) == 0);

            var frnn = vsapi.*.newAudioFrame.?(&d.audio_info.format, sampels_want, null, core);

            var channel_cnt = @as(usize, @intCast(self.audio_info.format.numChannels));

            var wp = [_]?[*]f32{ null, null, null, null, null, null, null };
            for (0..channel_cnt) |i| {
                wp[i] = @as([*]f32, @alignCast(@ptrCast(vsapi.*.getWritePtr.?(frnn, @as(c_int, @intCast(i))))));
            }
            //var wp0 = @as([*]f32, @alignCast(@ptrCast(vsapi.*.getWritePtr.?(frnn, 0))));
            //var wp1 = @as([*]f32, @alignCast(@ptrCast(vsapi.*.getWritePtr.?(frnn, 1))));

            while (sampels_want > 0) {
                var offset: u64 = 0;
                var size = d.ac3index.frame_sizes.items[frameoffset];
                for (0..frameoffset) |i| {
                    offset += @as(u64, d.ac3index.frame_sizes.items[i]);
                }
                d.file.seekTo(offset) catch unreachable;
                const rd = d.file.reader().readAll(d.buffer[0..size]) catch unreachable;
                std.debug.assert(rd == size);

                const ss = a52.a52_syncinfo(d.buffer.ptr, &flags, &sample_rate, &bit_rate);

                std.debug.assert(ss == size);

                _ = a52.a52_frame(self.a52_state, d.buffer.ptr, &flags, &level, bias);

                //std.debug.print("{} {} {}\n", .{ frameoffset, start_offset, sampels_want });
                for (0..6) |_| {
                    _ = a52.a52_block(self.a52_state);

                    // var szz = @as(usize, @intCast(256 * d.audio_info.format.bytesPerSample * d.audio_info.format.numChannels));
                    // var samplesu8 = @as([*]u8, @ptrCast(samples));

                    for (0..256) |a1| {
                        for (0..channel_cnt) |i| {
                            wp[i].?[0] = samples[a1 + 256 * i];
                            wp[i].? += 1;
                        }
                        //wp0[0] = samples[a1];
                        //wp1[0] = samples[a1 + 256];

                        sampels_want -= 1;

                        if (sampels_want == 0) {
                            break;
                        }
                        //wp0 += 1;
                        //wp1 += 1;
                    }
                }
                frameoffset += 1;
            }

            return frnn;
        }
    };
}
