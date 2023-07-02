const std = @import("std");

const mpeg2 = @import("./bindings/mpeg2.zig");

const utils = @import("utils.zig");
const ps_index = @import("ps_index.zig");
const m2v_index = @import("m2v_index.zig");
const dvd_reader = @import("dvd_reader.zig");
const m2v_in_ps = @import("m2v_in_ps.zig");

const debugPrint = utils.debugPrint;

fn fixGop(current_gop: *m2v_index.OutGopInfo) void {
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
        current_gop: m2v_index.OutGopInfo,
        wroteout_gop: bool,
        mpeg2_file_pos: u64,
        slice_cnt: u8,
        first_sequence: ?mpeg2.mpeg2_sequence_t,
        mpeg2_last_non_buffer: u64,
        gop_buf: GopBufWriter,

        current_vobid: u16 = 0,
        out_current_vobid: u16 = 0,

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

            try self.current_gop.writeOut(self.gop_buf);

            debugPrint("last gop write framecount: {any}\n", .{self.current_gop.frame_cnt});
            debugPrint("Total frames seen: {}\n", .{self.total_framecnt});
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
                    },
                    mpeg2.STATE_PICTURE_2ND => {
                        std.debug.assert(false);
                    },
                    mpeg2.STATE_PICTURE => {
                        const FrameType = m2v_index.FrameType;

                        const curpic = info.*.current_picture.*;
                        const curframe = &current_gop.frames[current_gop.frame_cnt];

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

                        curframe.repeat = (curpic.flags & mpeg2.PIC_FLAG_REPEAT_FIRST_FIELD) != 0;
                        curframe.tff = (curpic.flags & mpeg2.PIC_FLAG_TOP_FIELD_FIRST) != 0;
                        curframe.progressive = (curpic.flags & mpeg2.PIC_FLAG_PROGRESSIVE_FRAME) != 0;

                        current_gop.frame_cnt += 1;
                        self.total_piccnt += 1;
                    },
                    mpeg2.STATE_GOP => {
                        var gop = info.*.gop.*;
                        std.debug.assert(current_gop.frame_cnt == self.slice_cnt);

                        if (self.total_framecnt != 0) {
                            std.debug.assert(self.wroteout_gop);
                        }

                        current_gop.closed = (gop.flags & mpeg2.GOP_FLAG_CLOSED_GOP) != 0;
                        current_gop.frame_cnt = 0;
                        current_gop.frames = undefined;

                        //Holy shit whyyyyyyyyy
                        //dvds are cursed
                        if (self.total_piccnt == 0) {
                            current_gop.closed = true;
                        }

                        self.slice_cnt = 0;
                        self.wroteout_gop = false;
                        self.out_current_vobid = self.current_vobid;
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

pub fn MakePsIndexer(comptime GopBufWriter: anytype, comptime FrameBytePositionWriter: anytype, comptime VobIdWriter: anytype) type {
    return struct {
        const Self = @This();

        const BuffReader = std.io.BufferedReader(8192, dvd_reader.DvdReader.Reader);

        m2vindexer: M2vIndexer(GopBufWriter),

        dvd_reader: dvd_reader.DvdReader,
        buff_reader: BuffReader,
        cnting_reader: std.io.CountingReader(BuffReader.Reader),
        psindex: ps_index.PsIndex,
        psindex_last_mpeg2pos: u64,

        predemux_pos: u64,
        frame_byte_writer: FrameBytePositionWriter,
        vobid_writer: VobIdWriter,
        angle_writer: VobIdWriter,

        demuxer: m2v_in_ps.PsM2vExtracter(@TypeOf(std.heap.c_allocator)),

        pub fn deinit(self: *Self) void {
            self.psindex.indexs.deinit();
        }

        pub fn writeAll(self: *Self, mpeg2_data: []const u8) !void {
            const idx = &self.m2vindexer;
            const preframecnt = idx.total_piccnt;

            idx.current_vobid = self.demuxer.current_vobid;

            try idx.handleDataInBuf(mpeg2_data);
            const postframecnt = idx.total_piccnt; //idx.total_piccnt;
            const delta = postframecnt - preframecnt;

            for (0..delta) |_| {
                try self.frame_byte_writer.writeIntLittle(u64, self.predemux_pos); //const pp = self.cnting_reader.bytes_read;
                try self.vobid_writer.writeIntLittle(u16, self.m2vindexer.out_current_vobid);
                try self.angle_writer.writeByte(self.demuxer.current_angles);
            }
        }

        pub fn init(
            rdd: dvd_reader.DvdReader,
            gop_buf: GopBufWriter,
            frame_byte_writer: FrameBytePositionWriter,
            vobid_writer: VobIdWriter,
            angle_writer: VobIdWriter,
        ) !Self {
            var psindex = ps_index.PsIndex{};
            psindex.indexs = std.ArrayList(ps_index.IndexEntry).init(std.heap.c_allocator);

            //Crashes if default
            //4x perforance penalty though
            //TODO: COPYPASTE
            if (utils.is_windows) {
                _ = mpeg2.mpeg2_accel(0);
            }
            var slf = Self{
                .m2vindexer = M2vIndexer(GopBufWriter).init(gop_buf),
                .dvd_reader = rdd,
                .psindex = psindex,
                .buff_reader = undefined,
                .cnting_reader = undefined,
                .psindex_last_mpeg2pos = 0,
                .frame_byte_writer = frame_byte_writer,
                .predemux_pos = 0,
                .demuxer = try m2v_in_ps.psM2vExtracter(std.heap.c_allocator),
                .vobid_writer = vobid_writer,
                .angle_writer = angle_writer,
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

                //eof
                const should_stop = self.cnting_reader.bytes_read >= self.dvd_reader.block_cnt * 2048;

                var end_pos = self.cnting_reader.bytes_read;

                const current_unwritten_size = self.m2vindexer.mpeg2_file_pos - self.psindex_last_mpeg2pos;

                //This controlls how large the ps_index file gets
                //settings this too large makes playback stutter because reads take long
                const INDEX_CHUNK_SIZE = 1024 * 1024 * 3;

                if (should_stop or (current_unwritten_size >= INDEX_CHUNK_SIZE)) {
                    var startpos: u64 = 0;
                    if (self.psindex.indexs.getLastOrNull()) |last| {
                        startpos = last.in_end;
                    }
                    try self.psindex.add(startpos, end_pos, @as(u32, @intCast(current_unwritten_size)));
                    self.psindex_last_mpeg2pos = self.m2vindexer.mpeg2_file_pos;
                }

                if (should_stop) {
                    break;
                }
                self.predemux_pos = self.cnting_reader.bytes_read;
                try self.demuxer.demuxOne(rdd, self);
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
        var out = try cntr.reader().read(&buffer);
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
    var sequence_file = (try folder.createFile("sequence.bin", .{}));
    defer sequence_file.close();
    var wrter = std.io.bufferedWriter(sequence_file.writer());
    defer wrter.flush() catch unreachable;

    try m2v_index.writeoutSequence(seq, wrter.writer());
}

pub const DvdIndexingError = error{ dvdopen, fileopen };

pub fn doIndexingFullDvd(dvds: [*c]const u8, ii: index_manager.IndexInfo) !void {
    var index_folder = try index_manager.IndexManager.getIndexFolder(ii);

    var dvd_r = dvdread.DVDOpen2(null, &dvd_reader.dummy_logger, dvds);
    if (dvd_r == null) {
        return DvdIndexingError.dvdopen;
    }

    defer dvdread.DVDClose(dvd_r);

    var file = dvdread.DVDOpenFile(@as(*dvdread.dvd_reader_t, @ptrCast(dvd_r)), ii.mode.full.vts, indexManagerDomainToDvdDomain(ii.mode.full.domain));
    if (file == null) {
        return DvdIndexingError.fileopen;
    }
    defer dvdread.DVDCloseFile(file);

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

    var vobidpos = try index_folder.dir.createFile("vobid.bin", .{});
    defer vobidpos.close();
    var vobidposwrtr = std.io.bufferedWriter(vobidpos.writer());
    defer vobidposwrtr.flush() catch unreachable;
    var vobidposwrtrwrtr = vobidposwrtr.writer();

    var anglepos = try index_folder.dir.createFile("angle.bin", .{});
    defer anglepos.close();
    var angleposwrtr = std.io.bufferedWriter(anglepos.writer());
    defer angleposwrtr.flush() catch unreachable;
    var angleposwrtrwrtr = angleposwrtr.writer();

    var indexert = try MakePsIndexer(@TypeOf(gopbufwrt), @TypeOf(frameposwrtrwrtr), @TypeOf(vobidposwrtrwrtr)).init(dvd_reader.DvdReader.init(file.?), gopbufwrt, frameposwrtrwrtr, vobidposwrtrwrtr, angleposwrtrwrtr);
    defer indexert.deinit();

    try indexert.decodeAll();

    {
        var ps_file = (try index_folder.dir.createFile("ps_index.bin", .{}));
        defer ps_file.close();

        var file_writer = ps_file.writer();
        var wd1 = std.io.bufferedWriter(file_writer);
        defer wd1.flush() catch unreachable;

        try indexert.psindex.writeOut(wd1.writer());
    }

    try writeoutSequenceToFile(&index_folder.dir, &indexert.m2vindexer.first_sequence.?);
}

fn indexManagerDomainToDvdDomain(cd: index_manager.Domain) u8 {
    switch (cd) {
        .titlevobs => {
            return dvdread.DVD_READ_TITLE_VOBS;
        },
        .menuvob => {
            return dvdread.DVD_READ_MENU_VOBS;
        },
    }
}
