const std = @import("std");
const imports = @import("imports.zig");
const tb = imports.termz_core.tb;
const pty = imports.termz_core.pty;
const termz_c = imports.termz_c;

/// Basic ANSI escape sequences
pub const c0_controls = enum (u8) {
    BEL = 0x07, //Terminal bell (^G) [\a]
    BS  = 0x08, //Backspace (^H) [\b]
    HT  = 0x09, //Horizontal tab (^I) [\t]
    LF  = 0x0A, //Linefeed (new line) (^J) [\n]
    VT  = 0x0B, //Vertical tab (^K) [\v]
    FF  = 0x0C, //Formfeed (makes a new page) (^L) (\f)
    CR  = 0x0D, //Carriage return (move cursor to column 0) (^M) (\r)
    ESC = 0x1B, //Escape character (^[) (\e)
    DEL = 0x7F  //Delete character (<none>) (<none>)
};

/// Sequences that can follow ESC if the byte is in the range 0x80 to 0x9F. Usually only need to use the CSI code (usually represented by [)
/// Other sequences are rarely implemented. More info here: https://en.wikipedia.org/wiki/ANSI_escape_code#Fe_Escape_sequences
pub const fe_escape_sequences = enum (u8) {
    SS2 = 0x8E, //Single shift two (^[N)
    SS3 = 0x8F, //Single shift three (^[0)
    DCS = 0x90, //Device control string (^[P)
    CSI = 0x9B, //Control Sequence Introducer -> starts most useful sequences, terminated by a byte in the range 0x40 through 0x7E (^[[)
    ST  = 0x9C, //String terminator (^[\)
    OSC = 0x9D, //Operating System Command (^[])
    SOS = 0x98, //Start of String (^[X)
    PM  = 0x9E, //Privacy Message (^[^)
    APC = 0x9F  //Application Program Command (^[_)
};

const parser_state = enum (u4) {
    NORMAL,
    ESCAPE,
    ESCAPE_CSI
};

pub fn getErrno() i32 {
    return termz_c.__errno_location().*;
}

/// The actual parser of ANSI sequences
pub const ansi_parser = struct {
    state: parser_state,
    text_buf: *tb.text_buffer,
    bytes: [1024]u8,

    pub fn init(texb: *tb.text_buffer) ansi_parser {
        return ansi_parser{.state = parser_state.NORMAL, .text_buf = texb, .bytes = undefined};
    }

    pub fn parse(self: *ansi_parser, pts: *pty.PTY, gpa: std.mem.Allocator) !void {
        while(true) {
            const n = termz_c.read(pts.master, &self.bytes[0], self.bytes.len);
            //Data to read
            if(n > 0) {
                var current_param: u32 = 0;
                var args: std.ArrayList(u32) = try std.ArrayList(u32).initCapacity(gpa, 32);
                defer args.deinit(gpa);

                for(self.bytes[0..@intCast(n)]) |b| {
                    if(b != 0) {
                        if(self.state == parser_state.NORMAL) {
                            switch(b) {
                                @intFromEnum(c0_controls.BS)  => {_=try self.text_buf.deleteText(gpa);},
                                @intFromEnum(c0_controls.HT)  => {try self.text_buf.moveCursorX(4, gpa);},
                                @intFromEnum(c0_controls.LF)  => {_=try self.text_buf.createNewLine(gpa);},
                                @intFromEnum(c0_controls.VT)  => {try self.text_buf.moveCursorY(4, gpa);},
                                @intFromEnum(c0_controls.FF)  => {try self.text_buf.clearScreen(gpa);},
                                @intFromEnum(c0_controls.CR)  => {try self.text_buf.setCursorX(0, gpa);},
                                @intFromEnum(c0_controls.ESC) => {self.state = parser_state.ESCAPE;},
                                else => {_=try self.text_buf.insertText(b, gpa);}
                            }
                        }
                        else if(self.state == parser_state.ESCAPE) {
                            switch (b) {
                                @intFromEnum(fe_escape_sequences.CSI) => {self.state = parser_state.ESCAPE_CSI;},
                                else => {
                                    std.debug.print("Unsupported Code: {c}\n", .{b});
                                    // const error_msg = " Unsupported Code " ++ b;
                                    // for(0..error_msg.len) |c| {
                                    //     _=try self.text_buf.insertText(c, gpa);
                                    // }
                                }
                            }
                        }
                        else if(self.state == parser_state.ESCAPE_CSI) {
                            //Parameter byte
                            if (0x30 <= b and b <= 0x3F) {
                                switch(b) {
                                    '0'...'9' => current_param = current_param * 10 + (b - '0'),
                                    ';' => try args.insert(gpa, 1, current_param),
                                    else => {} //Should not happen
                                }
                            }
                            if(0x40 <= b and b <= 0x7E) {
                                switch(b) {
                                    // ===================== CURSOR CONTROLS ==================
                                    // TODO: Implement ESC[6n, ESC 7, ESC 8, ESC[s, ESC[u

                                    //ESC[H: Move cursor to (0,0)
                                    //ESC[{line};{column}H: Move cursor to line, column
                                    'H' => {
                                        if(args.items.len == 0) {
                                            try self.text_buf.screenToLogical(0, 0, gpa);
                                        }
                                        if(args.items.len >= 2) {
                                            try self.text_buf.screenToLogical(args.items[args.items.len-2], args.items[args.items.len-1], gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[{line};{column}f: Move cursor to line, column
                                    'f' => {
                                        if(args.items.len >= 2) {
                                            try self.text_buf.screenToLogical(args.items[args.items.len-2], args.items[args.items.len-1], gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#A: move cursor up # lines
                                    'A' => {
                                        if(args.items.len >= 1) {
                                            const newY: i32 = @as(i32, @intCast(self.text_buf.getScreenCursorY())) - @as(i32, @intCast(args.items[args.items.len-1]));
                                            try self.text_buf.screenToLogical(newY, self.text_buf.getScreenCursorX(), gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#B: move cursor down # lines
                                    'B' => {
                                        if(args.items.len >= 1) {
                                            const newY: i32 = @as(i32, @intCast(self.text_buf.getScreenCursorY())) + @as(i32, @intCast(args.items[args.items.len-1]));
                                            try self.text_buf.screenToLogical(newY, self.text_buf.getScreenCursorX(), gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#C: move cursor right # columns
                                    'C' => {
                                        if(args.items.len >= 1) {
                                            const newX: i32 = @as(i32, @intCast(self.text_buf.getScreenCursorX())) + @as(i32, @intCast(args.items[args.items.len-1]));
                                            try self.text_buf.screenToLogical(self.text_buf.getScreenCursorY(), newX, gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#D: move cursor left # columns
                                    'D' => {
                                        if(args.items.len >= 1) {
                                            const newX: i32 = @as(i32, @intCast(self.text_buf.getScreenCursorX())) - @as(i32, @intCast(args.items[args.items.len-1]));
                                            try self.text_buf.screenToLogical(self.text_buf.getScreenCursorY(), newX, gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#E: move cursor to begining of line, # lines down
                                    'E' => {
                                        if(args.items.len >= 1) {
                                            const newY: i32 = @as(i32, @intCast(self.text_buf.getScreenCursorY())) + @as(i32, @intCast(args.items[args.items.len-1]));
                                            try self.text_buf.screenToLogical(newY, 0, gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#E: move cursor to begining of line, # lines up
                                    'F' => {
                                        if(args.items.len >= 1) {
                                            const newY: i32 = @as(i32, @intCast(self.text_buf.getScreenCursorY())) - @as(i32, @intCast(args.items[args.items.len-1]));
                                            try self.text_buf.screenToLogical(newY, 0, gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#G: move cursor to column #
                                    'G' => {
                                        if(args.items.len >= 1) {
                                            try self.text_buf.screenToLogical(self.text_buf.getScreenCursorY(), args.items[args.items.len-1], gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[M: move cursor one line up
                                    'M' => {
                                        const newY: i32 = @as(i32, @intCast(self.text_buf.getScreenCursorY())) - 1;
                                        try self.text_buf.screenToLogical(newY, self.text_buf.getScreenCursorX(), gpa);
                                        args.clearRetainingCapacity();
                                    },

                                    //========================= ERASE FUNCTIONS ======================

                                    'J' => {
                                        if(args.items.len == 0 or args.items[args.items.len-1] == 0) {

                                        }
                                        else if(args.items[args.items.len-1] == 1) {

                                        }
                                        else if(args.items[args.items.len-1] == 2) {

                                        }
                                        else if(args.items[args.items.len-1] == 3) {

                                        }
                                        args.clearRetainingCapacity();
                                    },
                                    'K' => {
                                        if(args.items.len == 0 or args.items[args.items.len-1] == 0) {

                                        }
                                        else if(args.items[args.items.len-1] == 1) {

                                        }
                                        else if(args.items[args.items.len-1] == 2) {

                                        }
                                    },

                                    else => {}
                                }
                            }
                        }
                    }
                }
            }
            //An error
            else if(n < 0) {
                const err = getErrno();
                if(err != termz_c.EAGAIN) {
                    std.debug.print("Read error: {}\n", .{err});
                    return error.ReadError;
                }
                //Reached end of current stream
                else {
                    break;
                }
            }
        }
    }
};
