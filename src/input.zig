const std = @import("std");
const imports = @import("imports.zig");

const glfw = imports.termz_c_externals.glfw;
const tb = imports.termz_core.tb;

pub fn keyCallback(text_buf: *tb.text_buffer, key: i32, gpa: std.mem.Allocator) void {
    if(key == glfw.GLFW_KEY_BACKSPACE) {
        _ = text_buf.deleteText(gpa) catch return;
    }

    if(key == glfw.GLFW_KEY_ENTER) {
        _ = text_buf.createNewLine(gpa) catch return;
    }
}

pub fn onCharInput(text_buf: *tb.text_buffer, codepoint: u32, gpa: std.mem.Allocator) void {
    if(codepoint >= 32 and codepoint < 128) {
        _ = text_buf.insertText(@intCast(codepoint), gpa) catch return;
    }
}
