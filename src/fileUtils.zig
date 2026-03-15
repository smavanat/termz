const std = @import("std");

pub fn readToEnd(path: []const u8, buf: *[]const u8, allocator: std.mem.Allocator) !void {
    var fp: std.fs.File = try std.fs.cwd().openFile(path, .{});
    defer fp.close();

    buf.* = try fp.readToEndAlloc(allocator, std.math.maxInt(u32));
}
