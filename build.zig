const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const print_gops = b.addExecutable(.{
        .name = "print_gops",
        .root_source_file = .{ .path = "src/print_gops.zig" },
        .target = target,
        .optimize = optimize,
    });
    print_gops.linkLibC();

    const lib = b.addSharedLibrary(.{
        .name = "dvdsrc",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    if (!target.isWindows()) {
        lib.linkSystemLibraryName("dvdread");
        lib.linkSystemLibraryName("mpeg2");
    } else {
        lib.addObjectFile("./libdvdread.a");
        lib.addObjectFile("./libmpeg2.a");
    }

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(print_gops);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // This *creates* a RunStep in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const print_gops_cmd = b.addRunArtifact(print_gops);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        print_gops_cmd.addArgs(args);
    }

    {
        const run2_step = b.step("print_gops", "Run");
        run2_step.dependOn(&print_gops_cmd.step);
    }
}
