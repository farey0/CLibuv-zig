const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.next();
    const filepath = args.next().?;

    var file = try std.fs.openFileAbsolute(filepath, .{ .mode = .read_only });

    var buffered = std.io.bufferedReader(file.reader());
    var reader = buffered.reader();

    var arr = std.ArrayList(u8).init(allocator);
    defer arr.deinit();

    const buff = try allocator.create([5120]u8);
    defer allocator.destroy(buff);

    while (try reader.readUntilDelimiterOrEof(buff, '\n')) |line| {
        try arr.append('\n');

        //thks https://github.com/mitchellh/zig-libuv/ for the patchs

        if (std.mem.eql(u8, "    close_cb: uv_close_cb = @import(\"std\").mem.zeroes(uv_close_cb),", line)) {
            try arr.appendSlice("    close_cb: ?*const anyopaque = null, //BUG uv_close_cb,");
        } else if (std.mem.eql(u8, "    read_cb: uv_read_cb = @import(\"std\").mem.zeroes(uv_read_cb),", line)) {
            try arr.appendSlice("     read_cb: ?*const anyopaque = null, //BUG uv_read_cb,");
        } else {
            try arr.appendSlice(line);
        }
    }

    file.close();

    try std.fs.deleteFileAbsolute(filepath);

    file = try std.fs.createFileAbsolute(filepath, .{});

    try file.writeAll(arr.items);

    file.close();
}
