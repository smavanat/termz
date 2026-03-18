const std = @import("std");
const imports = @import("imports.zig");

const glfw = imports.termz_c_externals.glfw;
const tb = imports.termz_core.tb;

//Could be useful later?
pub fn keyCallback(window: *glfw.GLFWwindow, key: i32, scancode: i32, action: i32, mods: i32) void {
    _ = window;
    _ = key;
    _ = scancode;
    _ = action;
    _ = mods;
}

pub fn onCharInput(text_buf: *tb.text_buffer, codepoint: u32, gpa: std.mem.Allocator) void {
    if(codepoint >= 32 and codepoint < 128) {
        _ = text_buf.insertText(@intCast(codepoint), gpa) catch return;
    }
}
