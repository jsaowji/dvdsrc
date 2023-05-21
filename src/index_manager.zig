const std = @import("std");
const utils = @import("utils.zig");

const mm = std.heap.c_allocator;

pub const Mode = enum {
    full,
};

pub const Domain = enum {
    titlevobs,
    menuvob,
};

pub const ModeInfo = union(Mode) {
    full: struct {
        vts: u8,
        domain: Domain,
    },
};

pub const IndexInfo = struct {
    const Self = @This();

    dvd: []u8,
    mode: ModeInfo,

    pub fn init(dvd: [*:0]const u8, mode: ModeInfo) !Self {
        return Self{
            .dvd = try std.fmt.allocPrint(mm, "{s}", .{dvd}),
            .mode = mode,
        };
    }

    pub fn deinit(self: *Self) void {
        mm.free(self.dvd);
    }
};

pub const IndexManager = struct {
    pub fn getIndexFolder(ii: IndexInfo) !struct { existed: bool, dir: std.fs.Dir } {
        var basename = std.fs.path.basename(ii.dvd);
        var hash = std.hash.Crc32.init();

        std.hash.autoHashStrat(&hash, "version0", .Deep);
        std.hash.autoHashStrat(&hash, ii.dvd, .Deep);
        const finalhash = hash.final();

        var pp = try std.fmt.allocPrint(mm, "{s}_{}_{}_{}", .{ basename, ii.mode.full.vts, ii.mode.full.domain, finalhash });
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
