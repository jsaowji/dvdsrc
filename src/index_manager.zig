const std = @import("std");
const utils = @import("utils.zig");

const mm = std.heap.c_allocator;

pub const Mode = enum {
    m2v,
    full,
};

pub const Domain = enum {
    titlevobs,
    menuvob,
};

pub const ModeFull = struct {
    vts: u8,
    domain: Domain,
};

pub const ModeInfo = union(Mode) {
    m2v,
    full: ModeFull,
};

pub const IndexInfo = struct {
    const Self = @This();

    //DVD iso, dvd folder, m2v file
    path: []u8,
    mode: ModeInfo,

    pub fn init(path: [*:0]const u8, mode: ModeInfo) !Self {
        return Self{
            .path = try std.fmt.allocPrint(mm, "{s}", .{path}),
            .mode = mode,
        };
    }

    pub fn deinit(self: *Self) void {
        mm.free(self.path);
    }
};

pub const IndexManager = struct {
    pub fn getIndexFolder(ii: IndexInfo) !struct { existed: bool, dir: std.fs.Dir } {
        var basename = std.fs.path.basename(ii.path);
        var hash = std.hash.Crc32.init();

        std.hash.autoHashStrat(&hash, "version99", .Deep);
        std.hash.autoHashStrat(&hash, ii.path, .Deep);
        const finalhash = hash.final();

        var pp: []u8 = undefined;
        switch (ii.mode) {
            .full => |a| {
                pp = try std.fmt.allocPrint(mm, "{s}_{}_{}_{}", .{ basename, a.vts, a.domain, finalhash });
            },
            .m2v => {
                pp = try std.fmt.allocPrint(mm, "{s}_{}", .{ basename, finalhash });
            },
        }
        defer mm.free(pp);

        const illegal = [_]u8{
            ' ',
            '!',
            '*',
            '-',
            '.',
            ',',
            '/',
            '\\',
        };

        for (illegal) |i| {
            for (0..pp.len) |b| {
                if (pp[b] == i) {
                    pp[b] = '_';
                }
            }
        }

        const md = try getMainFolder();

        var existed = true;

        _ = md.openDir(pp, .{}) catch {
            try md.makeDir(pp);
            existed = false;
        };

        var dir = try md.openDir(pp, .{});
        return .{
            .existed = existed,
            .dir = dir,
        };
    }

    pub fn getMainFolder() !std.fs.Dir {
        var fullpath: []u8 = undefined;
        defer mm.free(fullpath);

        if (utils.is_windows) {
            const home = try std.process.getEnvVarOwned(mm, "userprofile");
            defer mm.free(home);

            const paths = &[_][]const u8{
                home,
                ".vsdvdsrc",
            };

            fullpath = try std.fs.path.join(mm, paths);
        } else {
            const home = try std.process.getEnvVarOwned(mm, "HOME");
            defer mm.free(home);

            const paths = &[_][]const u8{
                home,
                ".cache",
                "dvdsrc",
            };

            fullpath = try std.fs.path.join(mm, paths);
        }
        _ = try checkCreateFolder(fullpath);

        var dir = std.fs.openDirAbsolute(fullpath, .{}) catch unreachable;
        return dir;
    }
};

fn checkCreateFolder(path: []u8) !bool {
    _ = std.fs.openDirAbsolute(path, .{}) catch {
        try std.fs.makeDirAbsolute(path);
        return false;
    };
    return true;
}
