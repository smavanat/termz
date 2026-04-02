const std = @import("std");
const imports = @import("imports.zig");
const tb = imports.termz_core.tb;
const pty = imports.termz_core.pty;
const termz_c = imports.termz_c;

/// Basic ANSI escape sequences
pub const c0_controls = enum (u32) {
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
pub const fe_escape_sequences = enum (u32) {
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
    ESCAPE
};

pub fn getErrno() i32 {
    return termz_c.__errno_location().*;
}

/// The actual parser of ANSI sequences
pub const ansi_parser = struct {
    state: parser_state,
    text_buf: *tb.text_buffer,
    // bytes: u8[1024],
    more_bytes_to_read: bool,

    pub fn init(texb: *tb.text_buffer) ansi_parser {
        return ansi_parser{.state = parser_state.NORMAL, .text_buf = texb, .more_bytes_to_read = false};
    }

    pub fn parse(self: *ansi_parser, pts: *pty.PTY, gpa: std.mem.Allocator) !void {
        var buf = std.mem.zeroes([256]u8);
        const n = termz_c.read(pts.master, &buf[0], buf.len);
        if(n > 0) {
            for(buf[0..@intCast(n)]) |b| {
                if(b != 0) {
                    if(b == '\r') {
                        try self.text_buf.setCursorX(0, gpa);
                    }
                    else {
                        if(b != '\n') {
                            _=try self.text_buf.insertText(b, gpa);
                        }
                        else if(self.text_buf.getScreenCursorX() != 0 or !self.text_buf.screen.get(self.text_buf.screen.size-1).wrapped){
                            _=try self.text_buf.createNewLine(gpa);
                        }
                    }
                }
            }
        }
        else if(n < 0) {
            const err = getErrno();
            if(err != termz_c.EAGAIN) {
                std.debug.print("Read error: {}\n", .{err});
                return error.ReadError;
            }
        }
    }
};
