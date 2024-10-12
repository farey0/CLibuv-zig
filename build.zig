/// Adapted from : https://github.com/libuv/libuv/blob/v1.47.0/CMakeLists.txt
///
/// Current libuv version : 1.48.0
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

pub fn build(b: *std.Build) !void {
    const resolvedtarget = b.standardTargetOptions(.{});
    const target = resolvedtarget.result;
    const optimize = b.standardOptimizeOption(.{});

    const libuvSrc = b.dependency("libuv_src", .{});

    const generateZigBinding = b.option(
        bool,
        "zigBinding",
        "Generate Zig binding. Use this instead of cImport as it patches faulty translation",
    ) orelse true;

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
            "-D_CRT_DECLARE_NONSTDC_NAMES=0",
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

    lib.addIncludePath(libuvSrc.path("include/"));
    lib.addIncludePath(libuvSrc.path("src/"));

    lib.installHeadersDirectory(libuvSrc.path("include/"), "", .{});

    lib.addCSourceFiles(.{
        .root = libuvSrc.path(""),
        .files = &.{
            "src/fs-poll.c",
            "src/idna.c",
            "src/inet.c",
            "src/random.c",
            "src/strscpy.c",
            "src/strtok.c",
            "src/threadpool.c",
            "src/timer.c",
            "src/uv-common.c",
            "src/uv-data-getter-setters.c",
            "src/version.c",
        },
        .flags = cFlags.items,
    });

    if (target.os.tag == .windows) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/win/async.c",
                "src/win/core.c",
                "src/win/detect-wakeup.c",
                "src/win/dl.c",
                "src/win/error.c",
                "src/win/fs.c",
                "src/win/fs-event.c",
                "src/win/getaddrinfo.c",
                "src/win/getnameinfo.c",
                "src/win/handle.c",
                "src/win/loop-watcher.c",
                "src/win/pipe.c",
                "src/win/thread.c",
                "src/win/poll.c",
                "src/win/process.c",
                "src/win/process-stdio.c",
                "src/win/signal.c",
                "src/win/snprintf.c",
                "src/win/stream.c",
                "src/win/tcp.c",
                "src/win/tty.c",
                "src/win/udp.c",
                "src/win/util.c",
                "src/win/winapi.c",
                "src/win/winsock.c",
            },
            .flags = cFlags.items,
        });
    } else {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/async.c",
                "src/unix/core.c",
                "src/unix/dl.c",
                "src/unix/fs.c",
                "src/unix/getaddrinfo.c",
                "src/unix/getnameinfo.c",
                "src/unix/loop-watcher.c",
                "src/unix/loop.c",
                "src/unix/pipe.c",
                "src/unix/poll.c",
                "src/unix/process.c",
                "src/unix/random-devurandom.c",
                "src/unix/signal.c",
                "src/unix/stream.c",
                "src/unix/tcp.c",
                "src/unix/thread.c",
                "src/unix/tty.c",
                "src/unix/udp.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .aix) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/aix.c",
                "src/unix/aix-common.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.abi == .android) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/linux.c",
                "src/unix/procfs-exepath.c",
                "src/unix/random-getentropy.c",
                "src/unix/random-getrandom.c",
                "src/unix/random-sysctl-linux.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.isDarwin() or target.os.tag == .linux or target.abi == .android) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/proctitle.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .dragonfly or target.os.tag == .freebsd) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/freebsd.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .dragonfly or target.os.tag == .freebsd or target.os.tag == .netbsd or target.os.tag == .openbsd) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/posix-hrtime.c",
                "src/unix/bsd-proctitle.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.isDarwin() or target.os.tag == .dragonfly or target.os.tag == .freebsd or target.os.tag == .netbsd or target.os.tag == .openbsd) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/bsd-ifaddrs.c",
                "src/unix/kqueue.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .freebsd) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/random-getrandom.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.isDarwin() or target.os.tag == .openbsd) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/random-getentropy.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.isDarwin()) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/darwin-proctitle.c",
                "src/unix/darwin.c",
                "src/unix/fsevents.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .linux) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/linux.c",
                "src/unix/procfs-exepath.c",
                "src/unix/random-getrandom.c",
                "src/unix/random-sysctl-linux.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .netbsd) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/netbsd.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .openbsd) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/openbsd.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .solaris) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/no-proctitle.c",
                "src/unix/sunos.c",
            },
            .flags = cFlags.items,
        });
    }

    if (target.os.tag == .haiku) {
        lib.addCSourceFiles(.{
            .root = libuvSrc.path(""),
            .files = &.{
                "src/unix/haiku.c",
                "src/unix/bsd-ifaddrs.c",
                "src/unix/no-fsevents.c",
                "src/unix/no-proctitle.c",
                "src/unix/posix-hrtime.c",
                "src/unix/posix-poll.c",
            },
            .flags = cFlags.items,
        });
    }

    lib.linkLibC();

    b.installArtifact(lib);

    if (generateZigBinding) {
        const zBindings = b.addTranslateC(.{
            .optimize = optimize,
            .target = resolvedtarget,
            .root_source_file = libuvSrc.path("include/uv.h"),
        });

        // see https://github.com/ziglang/zig/issues/20065
        if (target.abi == .msvc) {
            zBindings.defineCMacroRaw("MIDL_INTERFACE=struct");
            zBindings.defineCMacroRaw("_UCRT"); // zig links against ucrt, not MSVCRT
        }

        zBindings.addIncludePath(libuvSrc.path("include"));

        const patcher = b.addExecutable(.{
            .name = "patcher",
            .optimize = .ReleaseFast,
            .target = b.host,
            .root_source_file = b.path("patcher.zig"),
        });

        const run_patcher = b.addRunArtifact(patcher);

        run_patcher.addFileArg(zBindings.getOutput());

        run_patcher.step.dependOn(&patcher.step);
        run_patcher.step.dependOn(&zBindings.step);

        const write_file = b.addNamedWriteFiles("cLibuv");

        const czigPath = write_file.addCopyFile(zBindings.getOutput(), "c.zig");

        write_file.step.dependOn(&run_patcher.step);

        lib.step.dependOn(&write_file.step);

        const cLibuv = b.addModule(
            "cLibuv",
            .{
                .root_source_file = czigPath,
                .link_libc = true,
            },
        );

        cLibuv.linkLibrary(lib);
    }
}
