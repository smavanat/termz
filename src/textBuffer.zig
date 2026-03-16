const std = @import("std");

const Style = enum(u4) {
    BOLD,
    ITALIC,
    UNDERLINE,
    NUM_STYLES
};

const TrailFlag = enum(u2) {
    NORMAL,
    WIDE_START,
    WIDE_END
};

const character_cell = struct {
    char: u8,
    style: [Style.NUM_STYLES] bool,
    backgroundColour: u32,
    foregroundColour: u32,

};

const text_buffer = struct {
    width: u32,
    height: u32,
    cursorX: u32,
    cursorY: u32,
    bottomIndex: u32,
};
