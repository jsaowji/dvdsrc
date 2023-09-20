const std = @import("std");

const mpeg2 = @import("./bindings/mpeg2.zig");

const utils = @import("utils.zig");
const ps_index = @import("ps_index.zig");
const m2v_index = @import("m2v_index.zig");
const dvd_reader = @import("dvd_reader.zig");
const ps_extracter = @import("ps_extracter.zig");
const ac3_index = @import("ac3_index.zig");
const lpcm_index = @import("lpcm_index.zig");

const debugPrint = utils.debugPrint;

pub const PS_INDEX_M2V_FILENAME = "ps_index.bin";

pub const PS_INDEX_AC3 = [_][]const u8{
    "ps_index_ac3_0.bin",
    "ps_index_ac3_1.bin",
    "ps_index_ac3_2.bin",
    "ps_index_ac3_3.bin",
    "ps_index_ac3_4.bin",
    "ps_index_ac3_5.bin",
    "ps_index_ac3_6.bin",
    "ps_index_ac3_7.bin",
};

pub const INDEX_AC3 = [_][]const u8{
    "ac3_0.bin",
    "ac3_1.bin",
    "ac3_2.bin",
    "ac3_3.bin",
    "ac3_4.bin",
    "ac3_5.bin",
    "ac3_6.bin",
    "ac3_7.bin",
};

pub const PS_INDEX_LPCM = [_][]const u8{
    "ps_index_lpcm_0.bin",
    "ps_index_lpcm_1.bin",
    "ps_index_lpcm_2.bin",
    "ps_index_lpcm_3.bin",
    "ps_index_lpcm_4.bin",
    "ps_index_lpcm_5.bin",
    "ps_index_lpcm_6.bin",
    "ps_index_lpcm_7.bin",
};

pub const INDEX_LPCM = [_][]const u8{
    "lpcm_0.bin",
    "lpcm_1.bin",
    "lpcm_2.bin",
    "lpcm_3.bin",
    "lpcm_4.bin",
    "lpcm_5.bin",
    "lpcm_6.bin",
    "lpcm_7.bin",
};
fn fixGop(current_gop: *m2v_index.OutGopInfo) void {
    if (current_gop.indexing_only_slicecnt < current_gop.frame_cnt) {
        std.debug.print("WARNING FOUND GOP WITH MORE PICUTRE THAN SLICE slice {} frame {} marking last as invalid \n", .{ current_gop.indexing_only_slicecnt, current_gop.frame_cnt });
        //current_gop.frame_cnt -= 1;
        current_gop.frames[current_gop.frame_cnt - 1].invalid = true;
    }

    for (0..current_gop.frame_cnt) |i| {
        const currenttr = current_gop.frames[i].temporal_reference;
        if (currenttr >= current_gop.frame_cnt) {
            var maxi: u8 = 0;
            for (0..current_gop.frame_cnt) |j| {
                //find j lowest
                const tr = current_gop.frames[j].temporal_reference;
                if (tr > maxi and (j != i)) {
                    maxi = tr;
                }
            }
            std.debug.print("fixing to {}\n", .{maxi + 1});
            current_gop.frames[i].temporal_reference = maxi + 1;
            std.debug.print("FOUND FUCKED UP TEMPORAL REFERENCE TRYING TO FIX\n", .{});
            std.debug.print("WILL ONLY WORK IF ITS THE ONE CASE I SAW\n", .{});
        }
        std.debug.assert(current_gop.frames[i].temporal_reference < current_gop.frame_cnt);
    }
}

fn M2vIndexer(comptime GopBufWriter: type) type {
    return struct {
        const Self = @This();

        mpeg2dec: *mpeg2.mpeg2dec_t,
        total_framecnt: u64, //rename total slicecnt
        total_piccnt: u64,

        gopcnt: u64 = 0,

        current_gop: m2v_index.OutGopInfo,
        wroteout_gop: bool,
        mpeg2_file_pos: u64,
        slice_cnt: u8,
        first_sequence: ?mpeg2.mpeg2_sequence_t,
        mpeg2_last_non_buffer: u64,
        gop_buf: GopBufWriter,

        current_vobidcellid: u32 = 0,
        out_current_vobidcellid: u32 = 0,

        fn init(gop_buf: GopBufWriter) Self {
            return .{
                .mpeg2dec = mpeg2.mpeg2_init().?,
                .current_gop = .{
                    .sequence_info_start = 0,
                    .closed = false,
                    .frame_cnt = 0,
                },
                .mpeg2_file_pos = 0,
                .slice_cnt = 0,
                .first_sequence = null,
                .mpeg2_last_non_buffer = 0,
                .total_framecnt = 0,
                .total_piccnt = 0,
                .wroteout_gop = false,
                .gop_buf = gop_buf,
            };
        }

        fn end(self: *Self) !void {
            fixGop(&self.current_gop);

            debugPrint("last gop write framecount: {any}\n", .{self.current_gop.frame_cnt});
            debugPrint("Total slice seen: {}\n", .{self.total_framecnt});
            debugPrint("Total pictures seen: {}\n", .{self.total_piccnt});

            //if (self.total_framecnt != self.total_piccnt) {
            //    std.debug.print("IMPROPERLY CUT STREAM SLICECNT != PICCNT ??? clamping to lower\n", .{});
            //    std.debug.print("THIS happens at end of stream its ok if not big bad and report issue pls\n", .{});
            //    const delta = self.total_piccnt - self.total_framecnt;
            //    self.current_gop.frame_cnt -= @as(u8, @intCast(delta));
            //}

            try self.current_gop.writeOut(self.gop_buf);
        }

        fn handleDataInBuf(self: *Self, buf: []const u8) !void {
            const mpeg_dec = self.mpeg2dec;
            const info = &mpeg2.mpeg2_info(mpeg_dec)[0];
            var current_gop = &self.current_gop;

            const pptr: [*c]u8 = @ptrCast(@constCast(buf.ptr));
            mpeg2.mpeg2_buffer(mpeg_dec, pptr, pptr + buf.len);

            //TODO: maybe write a indexer that does not need to decode the frames this is not fast
            while (true) {
                const decopre = @as(u64, @intCast(mpeg2.mpeg2_getpos(mpeg_dec)));
                var state = mpeg2.mpeg2_parse(mpeg_dec);
                const decopost = @as(u64, @intCast(mpeg2.mpeg2_getpos(mpeg_dec)));

                const delta = decopre - decopost;
                self.mpeg2_file_pos += delta;

                if (state != mpeg2.STATE_BUFFER) {
                    debugPrint("state {s} delta {}\n", .{ utils.mpeg2decStateToString(state), delta });
                }

                switch (state) {
                    mpeg2.STATE_SLICE, mpeg2.STATE_END => {
                        if (info.*.current_fbuf != 0) {
                            self.slice_cnt += 1;
                            self.total_framecnt += 1;
                        }
                        current_gop.indexing_only_slicecnt += 1;
                    },
                    mpeg2.STATE_PICTURE => {
                        const FrameType = m2v_index.FrameType;

                        const curpic = info.*.current_picture.*;
                        const curframe = &current_gop.frames[current_gop.frame_cnt];

                        curframe.invalid = false;
                        curframe.temporal_reference = @as(u8, @intCast(curpic.temporal_reference));
                        curframe.real_temporal_reference = @as(u8, @intCast(curpic.temporal_reference));

                        //https://github.com/dubhater/D2VWitch/blob/04d367529e936a14c06e364e8e32311a03172886/src/D2V.cpp#L292
                        switch (curpic.flags & mpeg2.PIC_MASK_CODING_TYPE) {
                            mpeg2.PIC_FLAG_CODING_TYPE_I => {
                                curframe.decodable_wo_prev_gop = true;
                                curframe.frametype = FrameType.I;
                            },
                            mpeg2.PIC_FLAG_CODING_TYPE_P => {
                                curframe.decodable_wo_prev_gop = true;
                                curframe.frametype = FrameType.P;
                            },
                            mpeg2.PIC_FLAG_CODING_TYPE_B => {
                                curframe.decodable_wo_prev_gop = false;

                                var possible_refframes: u8 = 0;

                                var i: u8 = 0;
                                while (i < current_gop.frame_cnt) {
                                    if (current_gop.frames[i].frametype == FrameType.I or current_gop.frames[i].frametype == FrameType.P) {
                                        possible_refframes += 1;
                                    }
                                    if (possible_refframes >= 2) {
                                        curframe.decodable_wo_prev_gop = true;
                                        break;
                                    }
                                    i += 1;
                                }

                                curframe.frametype = FrameType.B;
                            },
                            else => unreachable,
                        }

                        if (current_gop.closed) {
                            curframe.decodable_wo_prev_gop = true;
                        }
                        //First gop
                        if (self.gopcnt == 1 and !curframe.decodable_wo_prev_gop) {
                            curframe.invalid = true;
                        }

                        curframe.repeat = (curpic.flags & mpeg2.PIC_FLAG_REPEAT_FIRST_FIELD) != 0;
                        curframe.tff = (curpic.flags & mpeg2.PIC_FLAG_TOP_FIELD_FIRST) != 0;
                        curframe.progressive = (curpic.flags & mpeg2.PIC_FLAG_PROGRESSIVE_FRAME) != 0;

                        current_gop.frame_cnt += 1;
                        self.total_piccnt += 1;
                    },
                    mpeg2.STATE_GOP => {
                        var gop = info.*.gop.*;

                        debugPrint("GOP {}h {}m {}s {}p\n", .{ gop.hours, gop.minutes, gop.seconds, gop.pictures });

                        std.debug.assert(current_gop.frame_cnt == self.slice_cnt);

                        if (self.total_framecnt != 0) {
                            std.debug.assert(self.wroteout_gop);
                        }

                        current_gop.closed = (gop.flags & mpeg2.GOP_FLAG_CLOSED_GOP) != 0;
                        current_gop.frame_cnt = 0;
                        current_gop.indexing_only_slicecnt = 0;
                        current_gop.frames = undefined;

                        self.gopcnt += 1;

                        self.slice_cnt = 0;
                        self.wroteout_gop = false;
                        self.out_current_vobidcellid = self.current_vobidcellid;
                    },
                    mpeg2.STATE_SEQUENCE, mpeg2.STATE_SEQUENCE_MODIFIED, mpeg2.STATE_SEQUENCE_REPEATED => {
                        //TODO: check if sequence was acually modiefied or only useless shit like maxBps
                    },
                    mpeg2.STATE_BUFFER => {
                        break;
                    },
                    mpeg2.STATE_INVALID => {
                        std.debug.print("!!!!!!!GOT INVALID!!!!!!", .{});
                    },

                    mpeg2.STATE_PICTURE_2ND, mpeg2.STATE_SLICE_1ST => {},

                    else => {
                        std.debug.print("GOT {s}\n", .{utils.mpeg2decStateToString(state)});
                        unreachable;
                    },
                }

                if (state == mpeg2.STATE_SEQUENCE_REPEATED or state == mpeg2.STATE_SEQUENCE_MODIFIED or state == mpeg2.STATE_SEQUENCE) {
                    if (self.total_framecnt != 0) {
                        fixGop(&self.current_gop);
                        try current_gop.writeOut(self.gop_buf);
                        self.wroteout_gop = true;
                        debugPrint("wrote gop {}\n", .{current_gop.frame_cnt});
                    }

                    if (self.mpeg2_last_non_buffer == 0) {
                        current_gop.sequence_info_start = self.mpeg2_last_non_buffer;
                    } else {
                        current_gop.sequence_info_start = self.mpeg2_last_non_buffer - 4;
                    }

                    if (self.first_sequence == null) {
                        self.first_sequence = info.sequence.*;
                    }
                }

                if (state != mpeg2.STATE_BUFFER) {
                    self.mpeg2_last_non_buffer = self.mpeg2_file_pos;
                }
            }
            std.debug.assert(mpeg2.mpeg2_getpos(mpeg_dec) == 0);
        }
    };
}

const a52 = @import("bindings/a52.zig");

pub const Ac3Indexerer = struct {
    //Ac3Indexer
    const Self = @This();

    accumulated: u64 = 0,
    state: *a52.a52_state_t,
    arr: []u8,
    arr_pos: usize,

    //frame_sizes //guaranteed to be an even number between 128 and 3840

    first: bool,

    final_index: ac3_index.AC3Index,

    inner_accumulated: u64 = 0,

    outer_ac3_indexer_last_pos: u64,
    ac3_psindex: ps_index.PsIndex,

    pub fn init() Self {
        var arr = std.heap.c_allocator.alloc(u8, 8192) catch unreachable;

        var psindex2 = ps_index.PsIndex{};
        psindex2.indexs = std.ArrayList(ps_index.IndexEntry).init(std.heap.c_allocator);

        return .{
            .arr = arr,
            .state = a52.a52_init(0).?,
            .arr_pos = 0,
            .final_index = ac3_index.AC3Index.init(),
            .inner_accumulated = 0,
            .first = true,
            .outer_ac3_indexer_last_pos = 0,
            .ac3_psindex = psindex2,
        };
    }

    pub fn deinit(self: *Self) void {
        a52.a52_free(self.state);
        self.final_index.deinit();
        std.heap.c_allocator.free(self.arr);
        self.ac3_psindex.indexs.deinit();
    }

    pub fn othercodestuff(self: *Self, should_stop: bool, end_pos: u64) !void {
        const INDEX_CHUNK_SIZE2: usize = 1;
        {
            const current_unwritten_size = self.accumulated - self.outer_ac3_indexer_last_pos;
            if (should_stop or (current_unwritten_size >= INDEX_CHUNK_SIZE2)) {
                var startpos: u64 = 0;
                if (self.ac3_psindex.indexs.getLastOrNull()) |last| {
                    startpos = last.in_end;
                }
                try self.ac3_psindex.add(startpos, end_pos, @as(u32, @intCast(current_unwritten_size)));
                self.outer_ac3_indexer_last_pos = self.accumulated;
            }
        }
    }

    pub fn writeAll(self: *Self, data: []const u8) !void {
        self.accumulated += data.len;

        var flags: c_int = 0;
        var sample_rate: c_int = 0;
        var bit_rate: c_int = 0;

        @memcpy(self.arr[self.arr_pos .. self.arr_pos + data.len], data);
        self.arr_pos += data.len;

        while (true) {
            const rd = a52.a52_syncinfo(self.arr.ptr, &flags, &sample_rate, &bit_rate);

            //TODO: check elsewhere
            //if (flags == a52.A52_STEREO) {
            //    //ok!
            //} else if (flags == a52.A52_3F2R + a52.A52_LFE) {
            //    //
            //} else {
            //    std.debug.print("want sample havent looked at non stereo flags: {}\n", .{flags});
            //    std.debug.assert(false);
            //}

            //std.debug.print("{} {}\n", .{ rd, self.arr_pos });
            std.debug.assert(rd != 0);

            if (rd > self.arr_pos) {
                //need more data
                break;
            } else {
                const flags32 = @as(u32, @intCast(flags));
                const sampler32 = @as(u32, @intCast(sample_rate));
                try self.final_index.frame_sizes.append(@as(u16, @intCast(rd)));
                if (self.first) {
                    self.final_index.flags = flags32;
                    self.final_index.sample_rate = sampler32;
                } else {
                    std.debug.assert(flags32 == self.final_index.flags);
                    std.debug.assert(sampler32 == self.final_index.sample_rate);
                }

                const rdu = @as(usize, @intCast(rd));
                //std.debug.print("{} {}\n", .{ self.arr_pos, rdu });
                std.mem.copyForwards(u8, self.arr[0..(self.arr_pos - rdu)], self.arr[rdu..self.arr_pos]);
                self.arr_pos -= rdu;
            }
        }

        //var bptr = data.ptr;
        //
        //while (@intFromPtr(bptr) < @intFromPtr(data.ptr + data.len)) {
        //    const rd = a52.a52_syncinfo(@constCast(bptr), &flags, &sample_rate, &bit_rate);
        //    std.debug.print("rd {} {} || {} {} {} \n", .{ rd, data.len, sample_rate, bit_rate, flags });
        //
        //    std.debug.assert(rd != 0);
        //    bptr += @as(usize, @intCast(rd));
        //}
    }
};

pub const LPCMIndexerer = struct {
    //Ac3Indexer
    const Self = @This();

    accumulated: u64,
    first: bool,

    outer_lpcm_indexer_last_pos: u64,
    lpcm_psindex: ps_index.PsIndex,

    final_index: lpcm_index.LPCMIndex,

    pub fn init() Self {
        var psindex2 = ps_index.PsIndex{};
        psindex2.indexs = std.ArrayList(ps_index.IndexEntry).init(std.heap.c_allocator);

        return .{
            .accumulated = 0,
            .first = true,
            .outer_lpcm_indexer_last_pos = 0,
            .lpcm_psindex = psindex2,
            .final_index = lpcm_index.LPCMIndex.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.lpcm_psindex.indexs.deinit();
    }

    pub fn othercodestuff(self: *Self, should_stop: bool, end_pos: u64) !void {
        const INDEX_CHUNK_SIZE2: usize = 1;
        {
            const current_unwritten_size = self.accumulated - self.outer_lpcm_indexer_last_pos;
            if (should_stop or (current_unwritten_size >= INDEX_CHUNK_SIZE2)) {
                var startpos: u64 = 0;
                if (self.lpcm_psindex.indexs.getLastOrNull()) |last| {
                    startpos = last.in_end;
                }
                try self.lpcm_psindex.add(startpos, end_pos, @as(u32, @intCast(current_unwritten_size)));
                self.outer_lpcm_indexer_last_pos = self.accumulated;
            }
        }
    }

    pub fn writeAll(self: *Self, data: []const u8) !void {
        self.accumulated += data.len;

        if (self.first) {
            @memcpy(self.final_index.config_bytes[0..2], data[1..3]);
            self.first = false;
        } else {
            std.debug.assert(data[1] == self.final_index.config_bytes[0]);
            std.debug.assert(data[2] == self.final_index.config_bytes[1]);
        }
        try self.final_index.frame_sizes.append(@as(u16, @intCast(data.len)));
    }
};

pub const Ac3IndexererDistributor = IndexererDistributor(Ac3Indexerer);
pub const LPCMIndexererDistributor = IndexererDistributor(LPCMIndexerer);

fn IndexererDistributor(comptime InnerType: type) type {
    return struct {
        const Self = @This();

        inner: [8]InnerType,
        id: usize = 255,

        fn init() Self {
            var inner: [8]InnerType = undefined;
            for (0..8) |i| {
                inner[i] = InnerType.init();
            }
            return .{
                .inner = inner,
            };
        }
        fn deinit(self: *Self) void {
            for (0..8) |i| {
                self.inner[i].deinit();
            }
        }

        pub fn othercodestuff(self: *Self, should_stop: bool, end_pos: u64) !void {
            for (&self.inner) |*a| {
                try a.othercodestuff(should_stop, end_pos);
            }
        }

        pub fn audioIndex(self: *Self, id: usize) bool {
            self.id = id;
            return true;
        }

        pub fn writeAll(self: *Self, buf: []u8) !void {
            try self.inner[self.id].writeAll(buf);
        }
    };
}

pub fn MakePsIndexer(comptime DvdReaderType: anytype, comptime GopBufWriter: anytype, comptime FrameBytePositionWriter: anytype, comptime VobIdCellIdWriter: anytype) type {
    return struct {
        const Self = @This();

        const BuffReader = std.io.BufferedReader(8192, DvdReaderType.Reader);

        m2vindexer: M2vIndexer(GopBufWriter),

        dvd_reader: DvdReaderType,
        buff_reader: BuffReader,
        cnting_reader: std.io.CountingReader(BuffReader.Reader),

        m2v_psindex: ps_index.PsIndex,
        m2v_psindex_last_mpeg2pos: u64,

        predemux_pos: u64,
        frame_byte_writer: FrameBytePositionWriter,
        vobidcellid_writer: VobIdCellIdWriter,
        angle_writer: VobIdCellIdWriter,

        demuxer: ps_extracter.PsExtracter(@TypeOf(std.heap.c_allocator)),

        ac3id: Ac3IndexererDistributor,
        lpcmid: LPCMIndexererDistributor,

        pub fn deinit(self: *Self) void {
            self.m2v_psindex.indexs.deinit();
            self.ac3id.deinit();
            self.lpcmid.deinit();
        }

        pub fn writeAll(self: *Self, mpeg2_data: []const u8) !void {
            const idx = &self.m2vindexer;
            const preframecnt = idx.total_piccnt;

            idx.current_vobidcellid = self.demuxer.current_vobidcellid;

            try idx.handleDataInBuf(mpeg2_data);
            const postframecnt = idx.total_piccnt; //idx.total_piccnt;
            const delta = postframecnt - preframecnt;

            for (0..delta) |_| {
                try self.frame_byte_writer.writeIntLittle(u64, self.predemux_pos); //const pp = self.cnting_reader.bytes_read;
                try self.vobidcellid_writer.writeIntLittle(u32, self.m2vindexer.out_current_vobidcellid);
                try self.angle_writer.writeByte(self.demuxer.current_angles);
            }
        }

        pub fn init(
            rdd: DvdReaderType,
            gop_buf: GopBufWriter,
            frame_byte_writer: FrameBytePositionWriter,
            vobidcellid_writer: VobIdCellIdWriter,
            angle_writer: VobIdCellIdWriter,
        ) !Self {
            var psindex1 = ps_index.PsIndex{};
            psindex1.indexs = std.ArrayList(ps_index.IndexEntry).init(std.heap.c_allocator);

            //Crashes if default
            //4x perforance penalty though
            //TODO: COPYPASTE
            if (utils.is_windows) {
                _ = mpeg2.mpeg2_accel(0);
            }
            var slf = Self{
                .m2vindexer = M2vIndexer(GopBufWriter).init(gop_buf),
                .dvd_reader = rdd,

                .m2v_psindex = psindex1,
                .m2v_psindex_last_mpeg2pos = 0,

                .buff_reader = undefined,
                .cnting_reader = undefined,
                .frame_byte_writer = frame_byte_writer,
                .predemux_pos = 0,
                .demuxer = try ps_extracter.psExtracter(std.heap.c_allocator),
                .vobidcellid_writer = vobidcellid_writer,
                .angle_writer = angle_writer,

                .ac3id = Ac3IndexererDistributor.init(),
                .lpcmid = LPCMIndexererDistributor.init(),
            };

            slf.buff_reader = std.io.bufferedReaderSize(8192, slf.dvd_reader.reader());
            slf.cnting_reader = std.io.countingReader(slf.buff_reader.reader());

            return slf;
        }

        pub fn decodeAll(self: *Self) !void {
            var timer = try std.time.Timer.start();
            var last_framecnt: u64 = 0;

            var rdd = self.cnting_reader.reader();

            while (true) {
                if (timer.read() > 1_000_000_000) {
                    const frmcnt = self.m2vindexer.total_framecnt;
                    std.debug.print("{}fps {}% frames seen {}\n", .{ (frmcnt - last_framecnt), (100 * self.cnting_reader.bytes_read) / (self.dvd_reader.block_cnt * 2048), frmcnt });
                    last_framecnt = frmcnt;
                    timer.reset();
                }

                //This controlls how large the ps_index file gets
                //settings this too large makes playback stutter because reads take long
                const INDEX_CHUNK_SIZE1 = 1024 * 1024 * 3;

                //eof
                const should_stop = self.cnting_reader.bytes_read >= self.dvd_reader.block_cnt * 2048;

                var end_pos = self.cnting_reader.bytes_read;
                //generic

                {
                    const current_unwritten_size = self.m2vindexer.mpeg2_file_pos - self.m2v_psindex_last_mpeg2pos;
                    if (should_stop or (current_unwritten_size >= INDEX_CHUNK_SIZE1)) {
                        var startpos: u64 = 0;
                        if (self.m2v_psindex.indexs.getLastOrNull()) |last| {
                            startpos = last.in_end;
                        }
                        try self.m2v_psindex.add(startpos, end_pos, @as(u32, @intCast(current_unwritten_size)));
                        self.m2v_psindex_last_mpeg2pos = self.m2vindexer.mpeg2_file_pos;
                    }
                }
                try self.ac3id.othercodestuff(should_stop, end_pos);
                try self.lpcmid.othercodestuff(should_stop, end_pos);

                if (should_stop) {
                    _ = try self.m2vindexer.handleDataInBuf(&m2v_index.M2V_SEQ_END);

                    break;
                }
                self.predemux_pos = self.cnting_reader.bytes_read;
                try self.demuxer.demuxOne(rdd, self, &self.ac3id, &self.lpcmid);
            }

            try self.m2vindexer.end();
        }
    };
}

const index_manager = @import("index_manager.zig");
const dvdread = @import("manual_dvdread.zig");

pub fn doIndexingM2v(ii: index_manager.IndexInfo) !void {
    var index_folder = try index_manager.IndexManager.getIndexFolder(ii);

    var gop_index = try index_folder.dir.createFile("gops.bin", .{});
    defer gop_index.close();

    var gopbuf = std.io.bufferedWriter(gop_index.writer());
    defer gopbuf.flush() catch unreachable;

    var wrt = gopbuf.writer();

    var flz = try std.fs.openFileAbsolute(ii.path, .{});
    const flz_sz = (try flz.stat()).size;
    var indexert = M2vIndexer(@TypeOf(wrt)).init(wrt);

    var buffer: [8192]u8 = undefined;

    var timer = try std.time.Timer.start();

    var cntr = std.io.countingReader(flz.reader());

    var last_framecnt: u64 = 0;

    while (true) {
        var out = try cntr.reader().readAll(&buffer);
        if (out != 0) {
            _ = try indexert.handleDataInBuf(buffer[0..out]);
        } else {
            break;
        }

        if (timer.read() > 1_000_000_000) {
            const frmcnt = indexert.total_framecnt;
            std.debug.print("{}fps {}% frames seen {}\n", .{ (frmcnt - last_framecnt), (100 * cntr.bytes_read) / (flz_sz), frmcnt });
            last_framecnt = frmcnt;
            timer.reset();
        }
    }

    _ = try indexert.end();

    try writeoutSequenceToFile(&index_folder.dir, &indexert.first_sequence.?);
}

fn writeoutSequenceToFile(folder: *std.fs.Dir, seq: *mpeg2.mpeg2_sequence_t) !void {
    var sequence_file = try folder.createFile("sequence.bin", .{});
    defer sequence_file.close();
    var wrter = std.io.bufferedWriter(sequence_file.writer());
    defer wrter.flush() catch unreachable;

    try m2v_index.writeoutSequence(seq, wrter.writer());
}

pub const DvdIndexingError = error{};

pub fn doIndexingFullDvd(datasrc: anytype, ii: index_manager.IndexInfo) !void {
    var index_folder = try index_manager.IndexManager.getIndexFolder(ii);

    var gop_index = try index_folder.dir.createFile("gops.bin", .{});
    defer gop_index.close();
    var gopbuf = std.io.bufferedWriter(gop_index.writer());
    defer gopbuf.flush() catch unreachable;
    var gopbufwrt = gopbuf.writer();

    var framepos = try index_folder.dir.createFile("framepos.bin", .{});
    defer framepos.close();
    var frameposwrtr = std.io.bufferedWriter(framepos.writer());
    defer frameposwrtr.flush() catch unreachable;
    var frameposwrtrwrtr = frameposwrtr.writer();

    var vobidpos = try index_folder.dir.createFile("vobidcellid.bin", .{});
    defer vobidpos.close();
    var vobidposwrtr = std.io.bufferedWriter(vobidpos.writer());
    defer vobidposwrtr.flush() catch unreachable;
    var vobidposwrtrwrtr = vobidposwrtr.writer();

    var anglepos = try index_folder.dir.createFile("angle.bin", .{});
    defer anglepos.close();
    var angleposwrtr = std.io.bufferedWriter(anglepos.writer());
    defer angleposwrtr.flush() catch unreachable;
    var angleposwrtrwrtr = angleposwrtr.writer();

    var indexert = try MakePsIndexer(@TypeOf(datasrc), @TypeOf(gopbufwrt), @TypeOf(frameposwrtrwrtr), @TypeOf(vobidposwrtrwrtr)).init(datasrc, gopbufwrt, frameposwrtrwrtr, vobidposwrtrwrtr, angleposwrtrwrtr);
    defer indexert.deinit();

    try indexert.decodeAll();

    for (0..8) |i| {
        try writeoutAc3Index(&index_folder.dir, INDEX_AC3[i], PS_INDEX_AC3[i], &indexert.ac3id.inner[i]);
    }
    for (0..8) |i| {
        try writeoutLPCMIndex(&index_folder.dir, INDEX_LPCM[i], PS_INDEX_LPCM[i], &indexert.lpcmid.inner[i]);
    }

    try writeOutPsIndex(PS_INDEX_M2V_FILENAME, &index_folder.dir, &indexert.m2v_psindex);

    try writeoutSequenceToFile(&index_folder.dir, &indexert.m2vindexer.first_sequence.?);
}

fn writeoutAc3Index(dir: *std.fs.Dir, indexpath: []const u8, psindexpath: []const u8, ac3i: *Ac3Indexerer) !void {
    var ac3_indexx = try dir.createFile(indexpath, .{});
    defer ac3_indexx.close();
    var ac3buf = std.io.bufferedWriter(ac3_indexx.writer());
    defer ac3buf.flush() catch unreachable;
    var ac3bufwrt = ac3buf.writer();

    try ac3i.final_index.writeOut(ac3bufwrt);

    try writeOutPsIndex(psindexpath, dir, &ac3i.ac3_psindex);
}
fn writeoutLPCMIndex(dir: *std.fs.Dir, indexpath: []const u8, psindexpath: []const u8, lpcmi: *LPCMIndexerer) !void {
    //TODO: copypaste
    var ac3_indexx = try dir.createFile(indexpath, .{});
    defer ac3_indexx.close();
    var ac3buf = std.io.bufferedWriter(ac3_indexx.writer());
    defer ac3buf.flush() catch unreachable;
    var ac3bufwrt = ac3buf.writer();

    try lpcmi.final_index.writeOut(ac3bufwrt);

    try writeOutPsIndex(psindexpath, dir, &lpcmi.lpcm_psindex);
}

fn writeOutPsIndex(sub_path: []const u8, dir: *std.fs.Dir, psindex: *ps_index.PsIndex) !void {
    var ps_file = (try dir.createFile(sub_path, .{}));
    defer ps_file.close();

    var file_writer = ps_file.writer();
    var wd1 = std.io.bufferedWriter(file_writer);
    defer wd1.flush() catch unreachable;

    try psindex.writeOut(wd1.writer());
}

fn indexManagerDomainToDvdDomain(cd: i64) u8 {
    if (cd == 0) return 0;
    if (cd == 1) return 1;
    unreachable;
}
