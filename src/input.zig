const std = @import("std");
const imports = @import("imports.zig");

const glfw = imports.termz_c_externals.glfw;
const tb = imports.termz_core.tb;
const pty = imports.termz_core.pty;

pub fn keyCallback(text_buf: *tb.text_buffer, pts: *pty.PTY, key: i32, gpa: std.mem.Allocator) void {
    _ = switch(key) {
        glfw.GLFW_KEY_BACKSPACE =>text_buf.deleteText(gpa) catch return,
        glfw.GLFW_KEY_ENTER => {text_buf.writeToPTY(pts, gpa); _=text_buf.createNewLine(gpa) catch return;},
        glfw.GLFW_KEY_LEFT => text_buf.moveCursorX(-1, gpa) catch return,
        glfw.GLFW_KEY_RIGHT => text_buf.moveCursorX(1, gpa) catch return,
        else => {},
    };
}

pub fn onCharInput(text_buf: *tb.text_buffer, codepoint: u32, gpa: std.mem.Allocator) void {
    if(codepoint >= 32 and codepoint < 128) {
        _ = text_buf.insertText(@intCast(codepoint), gpa) catch return;
    }
}
