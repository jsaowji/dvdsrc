const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "dvdsrc",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    lib.linkLibCpp();
    if (!target.isWindows()) {
        lib.linkSystemLibraryName("dvdread");
        lib.linkSystemLibraryName("mpeg2");
        lib.linkSystemLibraryName("a52");
        lib.addCSourceFile(.{ .file = .{ .path = "./src/jsonstuff.cpp" }, .flags = &[_][]const u8{} });
    } else {
        lib.addObjectFile(.{ .path = "./libdvdread.a" });
        lib.addObjectFile(.{ .path = "./libmpeg2.a" });
        lib.addObjectFile(.{ .path = "./liba52.a" });

        lib.addIncludePath(.{ .path = "libdvdread-6.1.3/src" });
        lib.addCSourceFile(.{ .file = .{ .path = "./src/jsonstuff.cpp" }, .flags = &[_][]const u8{"-mno-ms-bitfields"} });
    }
    b.installArtifact(lib);
}
