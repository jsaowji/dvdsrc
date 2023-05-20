const std = @import("std");

const ps_index = @import("ps_index.zig");
const m2v_index = @import("m2v_index.zig");
const utils = @import("utils.zig");

const mm = std.heap.c_allocator;

pub fn main() !void {
    var args = try std.process.argsWithAllocator(mm);
    _ = args.skip();
    var dvd = args.next();

    var gops = try std.fs.openFileAbsolute(dvd.?, .{});

    var br = std.io.bufferedReader(gops.reader());
    var total_frames: u64 = 0;
    while (true) {
        const gpp = m2v_index.OutGopInfo.readIn(br.reader()) catch break;
        std.debug.print("{X} GOP closed {} framecnt: {} \n", .{ gpp.sequence_info_start, gpp.closed, gpp.frame_cnt });
        for (0..gpp.frame_cnt) |a| {
            const frm = &gpp.frames[a];
            std.debug.print("{:2} temporal {:2} type {} decodablewo {} tff {} rff {} prog {}\n", .{ a, frm.temporal_reference, frm.frametype, frm.decodable_wo_prev_gop, frm.tff, frm.repeat, frm.progressive });
        }
        total_frames += gpp.frame_cnt;
    }
    std.debug.print("total frames: {}\n", .{total_frames});
}
