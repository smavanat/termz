const std = @import("std");

/// Helper function to copy files from one directory into another
/// If the source directory does not exist, throws an error
/// If the destination directory does not exist, it is automatically created
/// @param src_path the path to the source directory
/// @param dest_path the path to the destination directory
/// @param gpa the allocator used to walk the source directory
pub fn copyDir(src_path: []const u8, dest_path: []const u8, gpa: std.mem.Allocator) !void {
    var src_dir = try std.fs.cwd().openDir(src_path, .{});
    defer src_dir.close();

    std.fs.cwd().access(dest_path, .{}) catch {
        try std.fs.cwd().makeDir(dest_path);
    };

    var dest_dir = try std.fs.cwd().makeOpenPath(dest_path, .{});
    defer dest_dir.close();

    var walker = try src_dir.walk(gpa);
    defer walker.deinit();

    while(try walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                try entry.dir.copyFile(entry.basename, dest_dir, entry.path, .{});
            },
            .directory => {
                try dest_dir.makeDir(entry.path);
            },
            else => return error.UnexpectedEntryKind,
        }
    }
}

pub fn readToEnd(path: []const u8, buf: *[]const u8, allocator: std.mem.Allocator) !void {
    var fp: std.fs.File = try std.fs.cwd().openFile(path, .{});
    defer fp.close();

    buf.* = try fp.readToEndAlloc(allocator, std.math.maxInt(u32));
}
