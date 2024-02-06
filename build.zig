const std = @import("std");
const builtin = @import("builtin");
const zcc = @import("compile_commands");
const app_name = "SDL2";

const release_flags = &[_][]const u8{
    "-DNDEBUG",
};

const debug_flags = &[_][]const u8{
    "-g",
};

const include_dirs = &[_][]const u8{
    "src/",
    "include/",
};

const SDLVideoPlatform = enum { dummy, android, arm, cocoa, directfb, emscripten, haiku, kmsdrm, n3ds, nacl, ngage, offscreen, os2, pandora, ps2, psp, qnx, raspberry, riscos, uikit, vita, vivante, wayland, windows, winrt, x11, yuv2rgb };
const SDLTimerPlatform = enum { dummy, haiku, n3ds, ngage, os2, ps2, psp, unix, vita, windows };
const SDLThreadPlatform = enum { dummy, generic, n3ds, ngage, os2, ps2, psp, pthread, stdcpp, vita, windows };
const SDLSensorPlatform = enum { dummy, android, coremotion, n3ds, vita, windows };
const SDLRenderPlatform = enum { software, direct3d, direct3d11, direct3d12, metal, opengl, opengles, opengles2, ps2, psp, vitagxm };
const SDLPowerPlatform = enum { none, android, emscripten, haiku, linux, macosx, n3ds, psp, uikit, vita, windows, winrt };
const SDLMiscPlatform = enum { dummy, android, emscripten, haiku, ios, macosx, riscos, unix, vita, windows, winrt };
const SDLEntrypointPlatform = enum { dummy, android, gdk, haiku, n3ds, nacl, ngage, ps2, psp, uikit, windows, winrt };
const SDLLocalePlatform = enum { dummy, android, emscripten, haiku, macosx, n3ds, unix, vita, windows, winrt };
const SDLLoadSOPlatform = enum { dummy, dlopen, os2, windows };
const SDLJoystickPlatform = enum { dummy, android, bsd, darwin, emscripten, haiku, hidapi, iphoneos, linux, n3ds, os2, ps2, psp, steam, virtual, vita, windows };
const SDLHIDAPIPlatform = enum { android, ios, libusb, linux, mac, windows };
const SDLHapticPlatform = enum { dummy, android, darwin, linux, windows };
const SDLFilesystemPlatform = enum { dummy, android, cocoa, emscripten, gdk, haiku, n3ds, nacl, os2, ps2, psp, riscos, unix, vita, windows, winrt };
const SDLFilePlatform = enum { other, cocoa, n3ds };
const SDLCorePlatform = enum { android, freebsd, gdk, linux, openbsd, os2, unix, windows, winrt };
const SDLAudioPlatform = enum { dummy, aaudio, alsa, android, arts, coreaudio, directsound, disk, dsp, emscripten, esd, fusionsound, haiku, jack, n3ds, nacl, nas, netbsd, openslES, os2, paudio, pipewire, ps2, psp, pulseaudio, qsa, sndio, sun, vita, wasapi, winmm };

const src_subdirs_unconditional = &[_][]const u8{
    "atomic",
    "cpuinfo",
    "dynapi",
    "events",
    "libm",
    "stdlib",
};

const SDLPlatformDescription = struct {
    video: SDLVideoPlatform,
    timer: SDLTimerPlatform,
    thread: SDLThreadPlatform,
    sensor: SDLSensorPlatform,
    render: SDLRenderPlatform,
    power: SDLPowerPlatform,
    misc: SDLMiscPlatform,
    main: SDLEntrypointPlatform,
    locale: SDLLocalePlatform,
    loadso: SDLLoadSOPlatform,
    joystick: SDLJoystickPlatform,
    hidapi: SDLHIDAPIPlatform,
    haptic: SDLHapticPlatform,
    filesystem: SDLFilesystemPlatform,
    file: SDLFilePlatform,
    core: SDLCorePlatform,
    audio: SDLAudioPlatform,
};

const windowsDefaultPlatformDescription = SDLPlatformDescription{
    .video = .windows,
    .timer = .windows,
    .thread = .windows,
    .sensor = .windows,
    .render = .direct3d,
    .power = .windows,
    .misc = .windows,
    .main = .windows,
    .locale = .windows,
    .loadso = .windows,
    .joystick = .windows,
    .hidapi = .windows,
    .haptic = .windows,
    .filesystem = .windows,
    .file = .none,
    .core = .windows,
    .audio = .windows,
};

fn getAllSourceSubdirs(
    ally: std.mem.Allocator,
    unconditional_subdirs: []const []const u8,
) ![]const []const u8 {
    const files = std.ArrayList([]const u8).init(ally);
    inline for (@typeInfo(SDLPlatformDescription).Struct.fields) |fieldname| {
        try files.append(fieldname);
    }
    try files.appendSlice(unconditional_subdirs);
    return try files.toOwnedSlice();
}

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

    for (src_subdirs) |subdir| {
        const subdir_path = b.pathJoin(&.{ ".", "src", subdir });
        defer b.allocator.free(subdir_path);
        std.log.debug("trying to open {s}", .{subdir_path});
        var dir = try std.fs.cwd().openIterableDir(subdir_path, .{});
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
