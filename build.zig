/// Adapted from : https://github.com/libuv/libuv/blob/v1.47.0/CMakeLists.txt
///
/// Current libuv version : 1.47.0
///
/// As of now i only tested it for windows.
/// Normally it should work on other platforms if i didn't made
/// any errors translating the CMakeFiles.txt
///
/// If you use it as shared lib, you must add "USING_UV_SHARED=1"
/// in your define before import
///
/// TODO/Questions :
///     - Add the libuv tests to this build ?
///     - See Solaris if
///     - quid of OS390/OS400?
///     - quid of QNX ?
///     - No plans for cywin so no port : see https://github.com/ziglang/zig/issues/751#issuecomment-614272910
const std = @import("std");

fn BuildDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

fn BoolToInt(myBool: bool) usize {
    return if (myBool) 1 else 0;
}

const root = BuildDir() ++ "/libuv/";
const includePath = root ++ "include";

pub fn build(b: *std.Build) !void {
    const resolvedtarget = b.standardTargetOptions(.{});
    const target = resolvedtarget.result;
    const optimize = b.standardOptimizeOption(.{});

    // build option following libuv/CMakeLists.txt
    const qemu = b.option(bool, "qemu", "build for qemu") orelse false;
    const asan = b.option(bool, "asan", "Enable AddressSanitizer (ASan)") orelse false;
    const msan = b.option(bool, "msan", "Enable MemorySanitizer (MSan)") orelse false;
    const tsan = b.option(bool, "tsan", "Enable ThreadSanitizer (TSan)") orelse false;
    const ubsan = b.option(bool, "ubsan", "Enable UndefinedBehaviorSanitizer (UBSan)") orelse false;
    const shared = b.option(bool, "shared", "build shared library") orelse false;

    if ((BoolToInt(asan) + BoolToInt(msan) + BoolToInt(tsan) + BoolToInt(ubsan)) > 1)
        @panic("asan, msan, tsan and ubsan are mutually exclusive options");

    var cFlags = std.ArrayList([]const u8).init(b.allocator);
    defer cFlags.deinit();

    var systemLibs = std.ArrayList([]const u8).init(b.allocator);
    defer systemLibs.deinit();

    try cFlags.appendSlice(&.{
        "-std=gnu90",
        "-Wno-unused-parameter",
        "-Wstrict-prototypes",
        "-Wextra",
        "-Wall",
        "-fno-strict-aliasing",
    });

    if (qemu) {
        try cFlags.appendSlice(&.{
            "-D__QEMU__=1",
        });
    }

    if (asan) {
        try cFlags.appendSlice(&.{
            "-fno-omit-frame-pointer",
            "-fsanitize=address",
            "-D__ASAN__=1",
        });
    }

    if (msan) {
        try cFlags.appendSlice(&.{
            "-fno-omit-frame-pointer",
            "-fsanitize=memory",
            "-D__MSAN__=1",
        });
    }

    if (tsan) {
        try cFlags.appendSlice(&.{
            "-fno-omit-frame-pointer",
            "-fsanitize=thread",
            "-D__TSAN__=1",
        });
    }

    if (ubsan) {
        try cFlags.appendSlice(&.{
            "-fno-omit-frame-pointer",
            "-fsanitize=undefined",
            "-D__UBSAN__=1",
        });
    }

    if (target.os.tag == .windows) {
        try cFlags.appendSlice(&.{
            "-DWIN32_LEAN_AND_MEAN",
            "-D_WIN32_WINNT=0x0602",
        });

        try systemLibs.appendSlice(&.{
            "psapi",
            "user32",
            "advapi32",
            "iphlpapi",
            "userenv",
            "ws2_32",
            "dbghelp",
            "ole32",
            "uuid",
            "shell32",
        });
    } else {
        // no OS390|QNX target in zig?
        if (target.abi == .android) {
            try systemLibs.appendSlice(&.{
                "pthread",
            });
        }
    }

    if (target.os.tag == .aix) {
        try cFlags.appendSlice(&.{
            "-D_ALL_SOURCE",
            "-D_LINUX_SOURCE_COMPAT",
            "-D_THREAD_SAFE",
            "-D_XOPEN_SOURCE=500",
            "-DHAVE_SYS_AHAFS_EVPRODS_H",
        });

        try systemLibs.appendSlice(&.{
            "perfstat",
        });
    }

    if (target.abi == .android) {
        try systemLibs.appendSlice(&.{
            "dl",
        });

        try cFlags.appendSlice(&.{
            "-D_GNU_SOURCE",
        });
    }

    if (target.isDarwin()) {
        try cFlags.appendSlice(&.{
            "-D_DARWIN_UNLIMITED_SELECT=1",
            "-D_DARWIN_USE_64_BIT_INODE=1",
        });
    }

    if (target.os.tag == .linux) {
        try cFlags.appendSlice(&.{
            "-D_GNU_SOURCE",
            "-D_POSIX_C_SOURCE=200112",
        });

        try systemLibs.appendSlice(&.{
            "dl",
            "rt",
        });
    }

    if (target.os.tag == .netbsd) {
        try systemLibs.appendSlice(&.{
            "kvm",
        });
    }

    // see https://en.wikipedia.org/wiki/SunOS
    // and https://github.com/libuv/libuv/blob/v1.47.0/CMakeLists.txt#L390
    // can zig detect targeted version?
    if (target.os.tag == .solaris) {
        try systemLibs.appendSlice(&.{
            "kstat",
            "nsl",
            "sendfile",
            "socket",
            "rt",
        });

        try cFlags.appendSlice(&.{
            "-DSUNOS_NO_IFADDRS",
            "-D__EXTENSIONS__",
            "-D_XOPEN_SOURCE=500",
            "-D_REENTRANT",
        });
    }

    if (target.os.tag == .haiku) {
        try cFlags.appendSlice(&.{
            "-D_BSD_SOURCE",
        });

        try systemLibs.appendSlice(&.{
            "network",
            "bsd",
        });
    }

    var lib: *std.Build.Step.Compile = undefined;

    if (shared) {
        try cFlags.appendSlice(&.{
            "-DBUILDING_UV_SHARED=1",
        });

        lib = b.addSharedLibrary(.{
            .name = "libuv",
            .target = resolvedtarget,
            .optimize = optimize,
        });
    } else {
        lib = b.addStaticLibrary(.{
            .name = "libuv",
            .target = resolvedtarget,
            .optimize = optimize,
        });
    }

    for (systemLibs.items) |libName| {
        lib.linkSystemLibrary(libName);
    }

    lib.addIncludePath(.{ .path = includePath });
    lib.addIncludePath(.{ .path = root ++ "src/" });

    lib.installHeadersDirectory(includePath, "");

    lib.addCSourceFiles(.{
        .files = &.{
            root ++ "src/fs-poll.c",
            root ++ "src/idna.c",
            root ++ "src/inet.c",
            root ++ "src/random.c",
            root ++ "src/strscpy.c",
            root ++ "src/strtok.c",
            root ++ "src/threadpool.c",
            root ++ "src/timer.c",
            root ++ "src/uv-common.c",
            root ++ "src/uv-data-getter-setters.c",
            root ++ "src/version.c",
        },
        .flags = cFlags.items,
    });

    if (target.os.tag == .windows) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/win/async.c",
                root ++ "src/win/core.c",
                root ++ "src/win/detect-wakeup.c",
                root ++ "src/win/dl.c",
                root ++ "src/win/error.c",
                root ++ "src/win/fs.c",
                root ++ "src/win/fs-event.c",
                root ++ "src/win/getaddrinfo.c",
                root ++ "src/win/getnameinfo.c",
                root ++ "src/win/handle.c",
                root ++ "src/win/loop-watcher.c",
                root ++ "src/win/pipe.c",
                root ++ "src/win/thread.c",
                root ++ "src/win/poll.c",
                root ++ "src/win/process.c",
                root ++ "src/win/process-stdio.c",
                root ++ "src/win/signal.c",
                root ++ "src/win/snprintf.c",
                root ++ "src/win/stream.c",
                root ++ "src/win/tcp.c",
                root ++ "src/win/tty.c",
                root ++ "src/win/udp.c",
                root ++ "src/win/util.c",
                root ++ "src/win/winapi.c",
                root ++ "src/win/winsock.c",
            },
            .flags = cFlags.items,
        });
    } else {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/async.c",
                root ++ "src/unix/core.c",
                root ++ "src/unix/dl.c",
                root ++ "src/unix/fs.c",
                root ++ "src/unix/getaddrinfo.c",
                root ++ "src/unix/getnameinfo.c",
                root ++ "src/unix/loop-watcher.c",
                root ++ "src/unix/loop.c",
                root ++ "src/unix/pipe.c",
                root ++ "src/unix/poll.c",
                root ++ "src/unix/process.c",
                root ++ "src/unix/random-devurandom.c",
                root ++ "src/unix/signal.c",
                root ++ "src/unix/stream.c",
                root ++ "src/unix/tcp.c",
                root ++ "src/unix/thread.c",
                root ++ "src/unix/tty.c",
                root ++ "src/unix/udp.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .aix) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/aix.c",
                root ++ "src/unix/aix-common.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.abi == .android) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/linux.c",
                root ++ "src/unix/procfs-exepath.c",
                root ++ "src/unix/random-getentropy.c",
                root ++ "src/unix/random-getrandom.c",
                root ++ "src/unix/random-sysctl-linux.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.isDarwin() or target.os.tag == .linux or target.abi == .android) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/proctitle.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .dragonfly or target.os.tag == .freebsd) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/freebsd.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .dragonfly or target.os.tag == .freebsd or target.os.tag == .netbsd or target.os.tag == .openbsd) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/posix-hrtime.c",
                root ++ "src/unix/bsd-proctitle.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.isDarwin() or target.os.tag == .dragonfly or target.os.tag == .freebsd or target.os.tag == .netbsd or target.os.tag == .openbsd) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/bsd-ifaddrs.c",
                root ++ "src/unix/kqueue.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .freebsd) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/random-getrandom.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.isDarwin() or target.os.tag == .openbsd) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/random-getentropy.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.isDarwin()) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/darwin-proctitle.c",
                root ++ "src/unix/darwin.c",
                root ++ "src/unix/fsevents.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .linux) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/linux.c",
                root ++ "src/unix/procfs-exepath.c",
                root ++ "src/unix/random-getrandom.c",
                root ++ "src/unix/random-sysctl-linux.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .netbsd) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/netbsd.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .openbsd) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/openbsd.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .solaris) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/no-proctitle.c",
                root ++ "src/unix/sunos.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .haiku) {
        lib.addCSourceFiles(.{
            .files = &.{
                root ++ "src/unix/haiku.c",
                root ++ "src/unix/bsd-ifaddrs.c",
                root ++ "src/unix/no-fsevents.c",
                root ++ "src/unix/no-proctitle.c",
                root ++ "src/unix/posix-hrtime.c",
                root ++ "src/unix/posix-poll.c",
            },
            .flags = cFlags.items,
        });
    }

    lib.linkLibC();

    b.installArtifact(lib);
}
