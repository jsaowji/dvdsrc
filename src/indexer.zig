const std = @import("std");

const mpeg2 = @import("./bindings/mpeg2.zig");

const utils = @import("utils.zig");
const ps_index = @import("ps_index.zig");
const m2v_index = @import("m2v_index.zig");
const dvd_reader = @import("dvd_reader.zig");
const m2v_in_ps = @import("m2v_in_ps.zig");

const debugPrint = utils.debugPrint;

pub fn MakeIndexer(comptime gopbuf_writer: anytype) type {
    return struct {
        const Self = @This();

        const BuffReader = std.io.BufferedReader(8192, dvd_reader.DvdReader.Reader);

        mpeg2dec: *mpeg2.mpeg2dec_t,

        total_framecnt: u64,

        psindex: ps_index.PsIndex,
        psindex_last_mpeg2pos: u64,

        current_gop: m2v_index.OutGopInfo,
        wroteout_gop: bool,
        mpeg2_file_pos: u64,
        slice_cnt: u8,
        first_sequence: ?mpeg2.mpeg2_sequence_t,
        mpeg2_last_non_buffer: u64,

        dvd_reader: dvd_reader.DvdReader,
        gop_buf: gopbuf_writer,

        buff_reader: BuffReader,
        cnting_reader: std.io.CountingReader(BuffReader.Reader),

        pub fn deinit(self: *Self) void {
            self.psindex.indexs.deinit();
        }

        pub fn writeAll(self: *Self, mpeg2_data: []const u8) !void {
            try self.handleDataInBuf(mpeg2_data);
        }

        pub fn init(
            rdd: dvd_reader.DvdReader,
            gop_buf: gopbuf_writer,
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
                .dvd_reader = rdd,
                .mpeg2dec = mpeg2.mpeg2_init().?,
                .current_gop = .{},
                .mpeg2_file_pos = 0,
                .slice_cnt = 0,
                .first_sequence = null,
                .mpeg2_last_non_buffer = 0,
                .total_framecnt = 0,
                .psindex = psindex,
                .gop_buf = gop_buf,
                .wroteout_gop = false,
                .buff_reader = undefined,
                .cnting_reader = undefined,
                .psindex_last_mpeg2pos = 0,
            };

            slf.buff_reader = std.io.bufferedReaderSize(8192, slf.dvd_reader.reader());
            slf.cnting_reader = std.io.countingReader(slf.buff_reader.reader());
            return slf;
        }

        fn handleDataInBuf(self: *Self, buf: []const u8) !void {
            const mpeg_dec = self.mpeg2dec;
            const info = &mpeg2.mpeg2_info(mpeg_dec)[0];
            var current_gop = &self.current_gop;

            const pptr = @ptrCast([*c]u8, @constCast(buf.ptr));
            mpeg2.mpeg2_buffer(mpeg_dec, pptr, pptr + buf.len);

            //TODO: maybe write a indexer that does not need to decode the frames this is not fast
            while (true) {
                const decopre = @intCast(u64, mpeg2.mpeg2_getpos(mpeg_dec));
                var state = mpeg2.mpeg2_parse(mpeg_dec);
                const decopost = @intCast(u64, mpeg2.mpeg2_getpos(mpeg_dec));

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
                    mpeg2.STATE_PICTURE_2ND => {},
                    mpeg2.STATE_PICTURE => {
                        const FrameType = m2v_index.FrameType;

                        const curpic = info.*.current_picture.*;
                        const curframe = &current_gop.frames[current_gop.frame_cnt];

                        curframe.temporal_reference = @intCast(u8, curpic.temporal_reference);

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

                        self.slice_cnt = 0;
                        self.wroteout_gop = false;
                    },
                    mpeg2.STATE_SEQUENCE, mpeg2.STATE_SEQUENCE_MODIFIED, mpeg2.STATE_SEQUENCE_REPEATED => {
                        //TODO: check if sequence was acually modiefied or only useless shit like maxBps
                    },
                    mpeg2.STATE_BUFFER => {
                        break;
                    },
                    else => {
                        unreachable;
                    },
                }

                if (state == mpeg2.STATE_SEQUENCE_REPEATED or state == mpeg2.STATE_SEQUENCE_MODIFIED or state == mpeg2.STATE_SEQUENCE) {
                    if (self.total_framecnt != 0) {
                        try current_gop.writeOut(self.gop_buf);
                        self.wroteout_gop = true;
                        debugPrint("wrote gop {}\n", .{current_gop.frame_cnt});
                    }
                }

                if (state == mpeg2.STATE_SEQUENCE_REPEATED or state == mpeg2.STATE_SEQUENCE or state == mpeg2.STATE_SEQUENCE_MODIFIED) {
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

        pub fn decodeAll(self: *Self) !void {
            var timer = try std.time.Timer.start();
            var last_bytes_read: u64 = 0;
            var last_framecnt: u64 = 0;

            var demuxer = try m2v_in_ps.psM2vExtracter(std.heap.c_allocator);

            while (true) {
                var rdd = self.cnting_reader.reader();
                if (timer.read() > 1_000_000_000) {
                    std.debug.print("{}fps {}% frames seen {}\n", .{ (self.total_framecnt - last_framecnt), (100 * self.cnting_reader.bytes_read) / (self.dvd_reader.block_cnt * 2048), self.total_framecnt });
                    last_bytes_read = self.cnting_reader.bytes_read;
                    last_framecnt = self.total_framecnt;
                    timer.reset();
                }

                //eof
                const should_stop = self.cnting_reader.bytes_read >= self.dvd_reader.block_cnt * 2048;

                var end_pos = self.cnting_reader.bytes_read;

                const current_unwritten_size = self.mpeg2_file_pos - self.psindex_last_mpeg2pos;

                //This controlls how large the ps_index file gets
                //settings this too large makes playback stutter because reads take long
                const INDEX_CHUNK_SIZE = 1024 * 1024 * 3;

                if (should_stop or (current_unwritten_size >= INDEX_CHUNK_SIZE)) {
                    var startpos: u64 = 0;
                    if (self.psindex.indexs.getLastOrNull()) |last| {
                        startpos = last.in_end;
                    }
                    try self.psindex.add(startpos, end_pos, @intCast(u32, current_unwritten_size));
                    self.psindex_last_mpeg2pos = self.mpeg2_file_pos;
                }

                if (should_stop) {
                    break;
                }

                try demuxer.demuxOne(rdd, self);
            }

            try self.current_gop.writeOut(self.gop_buf);
            debugPrint("last gop write framecount: {any}\n", .{self.current_gop.frame_cnt});
            debugPrint("Total frames seen: {}\n", .{self.total_framecnt});
        }
    };
}

const index_manager = @import("index_manager.zig");
const dvdread = @import("./bindings/dvdread.zig");

pub const IndexingError = error{ dvdopen, fileopen };

pub fn doIndexing(dvds: [*c]const u8, ii: index_manager.IndexInfo) !void {
    var index_folder = try index_manager.IndexManager.getIndexFolder(ii);

    var dvd_r = dvdread.DVDOpen(dvds);
    if (dvd_r == null) {
        return IndexingError.dvdopen;
    }

    defer dvdread.DVDClose(dvd_r);

    var file = dvdread.DVDOpenFile(@ptrCast(*dvdread.dvd_reader_t, dvd_r), ii.mode.full.vts, indexManagerDomainToDvdDomain(ii.mode.full.domain));
    if (file == null) {
        return IndexingError.fileopen;
    }
    defer dvdread.DVDCloseFile(file);

    var gop_index = try index_folder.dir.createFile("gops.bin", .{});
    defer gop_index.close();

    var gopbuf = std.io.bufferedWriter(gop_index.writer());
    defer gopbuf.flush() catch unreachable;

    var wrt = gopbuf.writer();

    var indexert = try MakeIndexer(@TypeOf(wrt)).init(dvd_reader.dvdReader(file), wrt);
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

    {
        var sequence_file = (try index_folder.dir.createFile("sequence.bin", .{}));
        defer sequence_file.close();
        try m2v_index.writeoutSequence(&indexert.first_sequence.?, sequence_file.writer());
    }
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
