const std = @import("std");
const builtin = @import("builtin");
const app_name = "SDL2";

const release_flags = &[_][]const u8{
    "-DNDEBUG",
};

const debug_flags = &[_][]const u8{
    "-g",
};

const zcc = @import("compile_commands");

const include_dirs = &[_][]const u8{
    "src/",
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();
    try flags.appendSlice(if (optimize == .Debug) debug_flags else release_flags);

    var targets = std.ArrayList(*std.Build.Step.Compile).init(b.allocator);
    defer targets.deinit();

    var sources = std.ArrayList([]const u8).init(b.allocator);
    defer sources.deinit();

    {
        var dir = try std.fs.cwd().openIterableDir("src/", .{});
        var walker = try dir.walk(b.allocator);
        defer walker.deinit();
        while (try walker.next()) |item| {
            const ext = std.fs.path.extension(item.basename);
            if (std.mem.eql(u8, ".c", ext)) {
                const dirname = try item.dir.realpathAlloc(b.allocator, ".");
                const fullpathmem = try b.allocator.realloc(dirname, dirname.len + item.basename.len + 1);
                fullpathmem[dirname.len] = '/';
                @memcpy(fullpathmem[dirname.len + 1 ..], item.basename);
                try sources.append(fullpathmem);
            }
        }
    }

    var libsdl: *std.Build.CompileStep =
        b.addSharedLibrary(.{
        .name = app_name,
        .optimize = optimize,
        .target = target,
    });

    try targets.append(libsdl);
    b.installArtifact(libsdl);

    libsdl.linkLibC();

    for (include_dirs) |include_dir| {
        try flags.append(b.fmt("-I{s}", .{include_dir}));
    }

    {
        const flags_owned = flags.toOwnedSlice() catch @panic("OOM");
        libsdl.addCSourceFiles(try sources.toOwnedSlice(), flags_owned);
    }

    zcc.createStep(b, "cdb", try targets.toOwnedSlice());
}
