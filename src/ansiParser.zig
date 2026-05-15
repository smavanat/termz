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
pub const escape_sequences = enum (u8) {
    SGR7= 0x37, //Save cursor position and attributes (^[7)
    SGR8= 0x38, //Load cursor position and attributes (^[8)
    IND = 0x44, //Move/scroll window up one line (^[D)
    RI  = 0x4D, //Move/scroll window down one line (^[M)
    SS2 = 0x4E, //Single shift two (^[N)
    SS3 = 0x4F, //Single shift three (^[0)
    DCS = 0x50, //Device control string (^[P)
    CSI = 0x5B, //Control Sequence Introducer -> starts most useful sequences, terminated by a byte in the range 0x40 through 0x7E (^[[)
    ST  = 0x5C, //String terminator (^[\)
    OSC = 0x5D, //Operating System Command (^[])
    SOS = 0x58, //Start of String (^[X)
    PM  = 0x5E, //Privacy Message (^[^)
    APC = 0x5F  //Application Program Command (^[_)
};

const parser_state = enum (u4) {
    NORMAL,
    ESCAPE,
    ESCAPE_CSI,
    ESCAPE_OSC,
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
        self.state = parser_state.NORMAL;
        while(true) {
            const n = termz_c.read(pts.master, &self.bytes[0], self.bytes.len);
            //Data to read
            if(n > 0) {
                var args: std.ArrayList(u32) = try std.ArrayList(u32).initCapacity(gpa, 32);
                defer args.deinit(gpa);

                for(self.bytes[0..@intCast(n)]) |b| {
                    std.debug.print("{x} ", .{b});
                    if(b != 0) {
                        if(self.state == parser_state.NORMAL) {
                            switch(b) {
                                @intFromEnum(c0_controls.BS)  => {_=try self.text_buf.deleteText(gpa);},
                                @intFromEnum(c0_controls.HT)  => {
                                    const nextX = self.text_buf.getScreenCursorX() + (4 - (self.text_buf.getScreenCursorX() % 4));
                                    try self.text_buf.screenToLogical(self.text_buf.getScreenCursorY(), nextX, gpa);
                                },
                                @intFromEnum(c0_controls.LF)  => {try self.text_buf.createNewLine(gpa);},
                                @intFromEnum(c0_controls.VT)  => {try self.text_buf.screenToLogical(self.text_buf.getScreenCursorY() + 4, self.text_buf.getScreenCursorX(), gpa);},
                                @intFromEnum(c0_controls.FF)  => {try self.text_buf.clearScreen();},
                                @intFromEnum(c0_controls.CR)  => {try self.text_buf.screenToLogical(self.text_buf.getScreenCursorY(), 0, gpa);},
                                @intFromEnum(c0_controls.ESC) => {self.state = parser_state.ESCAPE;},
                                else => {_=try self.text_buf.overwriteText(b, gpa);}
                            }
                        }
                        else if(self.state == parser_state.ESCAPE) {
                            switch (b) {
                                @intFromEnum(escape_sequences.SGR7)=> {self.text_buf.saveCursorPos();},
                                @intFromEnum(escape_sequences.SGR8)=> {self.text_buf.loadCursorPos();},
                                @intFromEnum(escape_sequences.IND) => {
                                    const newY: i32 = @max(0, @as(i32, @intCast(self.text_buf.getScreenCursorY())) + 1);
                                    try self.text_buf.screenToLogical(@intCast(newY), self.text_buf.getScreenCursorX(), gpa);
                                },
                                @intFromEnum(escape_sequences.RI) => {
                                    const newY: i32 = @max(0, @as(i32, @intCast(self.text_buf.getScreenCursorY())) - 1);
                                    try self.text_buf.screenToLogical(@intCast(newY), self.text_buf.getScreenCursorX(), gpa);
                                },
                                @intFromEnum(escape_sequences.CSI) => {self.state = parser_state.ESCAPE_CSI; args.clearRetainingCapacity();},
                                @intFromEnum(escape_sequences.OSC) => {self.state = parser_state.ESCAPE_OSC; args.clearRetainingCapacity();},
                                @intFromEnum(escape_sequences.ST) => {self.state = parser_state.ESCAPE_OSC; args.clearRetainingCapacity();},
                                else => {
                                    std.debug.print("Unsupported Code: {c}\n", .{b});
                                    self.state = parser_state.NORMAL;
                                }
                            }
                        }
                        else if (self.state == parser_state.ESCAPE_OSC) {
                            if(b == @intFromEnum(c0_controls.BEL)) {self.state = parser_state.NORMAL; args.clearRetainingCapacity();}
                            if(b == @intFromEnum(c0_controls.ESC)) {self.state = parser_state.ESCAPE; args.clearRetainingCapacity();}
                        }
                        else if(self.state == parser_state.ESCAPE_CSI) {
                            //Parameter byte
                            if (0x30 <= b and b <= 0x3F) {
                                if(args.items.len == 0) try args.append(gpa, 0);
                                switch(b) {
                                    '0'...'9' => {
                                        var current_param = args.items[args.items.len-1];
                                        current_param = current_param * 10 + (b - '0');
                                        args.items[args.items.len-1] = current_param;

                                    },
                                    ';' => try args.append(gpa, 0),
                                    else => {} //Should not happen
                                }
                            }
                            if(0x40 <= b and b <= 0x7E) {
                                switch(b) {
                                    // ===================== CURSOR CONTROLS ==================
                                    //ESC[H: Move cursor to (0,0)
                                    //ESC[{line};{column}H: Move cursor to line, column
                                    'H' => {
                                        if(args.items.len == 0) {
                                            try self.text_buf.screenToLogical(0, 0, gpa);
                                            args.clearRetainingCapacity();
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
                                            const newY: i32 = @max(0, @as(i32, @intCast(self.text_buf.getScreenCursorY())) - @as(i32, @intCast(args.items[args.items.len-1])));
                                            try self.text_buf.screenToLogical(@intCast(newY), self.text_buf.getScreenCursorX(), gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#B: move cursor down # lines
                                    'B' => {
                                        if(args.items.len >= 1) {
                                            const newY: i32 = @as(i32, @intCast(self.text_buf.getScreenCursorY())) + @as(i32, @intCast(args.items[args.items.len-1]));
                                            try self.text_buf.screenToLogical(@intCast(newY), self.text_buf.getScreenCursorX(), gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#C: move cursor right # columns
                                    'C' => {
                                        if(args.items.len >= 1) {
                                            const newX: i32 = @as(i32, @intCast(self.text_buf.getScreenCursorX())) + @as(i32, @intCast(args.items[args.items.len-1]));
                                            try self.text_buf.screenToLogical(self.text_buf.getScreenCursorY(), @intCast(newX), gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#D: move cursor left # columns
                                    'D' => {
                                        if(args.items.len >= 1) {
                                            const newX: i32 = @max(0, @as(i32, @intCast(self.text_buf.getScreenCursorX())) - @as(i32, @intCast(args.items[args.items.len-1])));
                                            try self.text_buf.screenToLogical(self.text_buf.getScreenCursorY(), @intCast(newX), gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#E: move cursor to begining of line, # lines down
                                    'E' => {
                                        if(args.items.len >= 1) {
                                            const newY: i32 = @as(i32, @intCast(self.text_buf.getScreenCursorY())) + @as(i32, @intCast(args.items[args.items.len-1]));
                                            try self.text_buf.screenToLogical(@intCast(newY), 0, gpa);
                                            args.clearRetainingCapacity();
                                        }
                                    },
                                    //ESC[#E: move cursor to begining of line, # lines up
                                    'F' => {
                                        if(args.items.len >= 1) {
                                            const newY: i32 = @max(0, @as(i32, @intCast(self.text_buf.getScreenCursorY())) - @as(i32, @intCast(args.items[args.items.len-1])));
                                            try self.text_buf.screenToLogical(@intCast(newY), 0, gpa);
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
                                    //ESC[s: saves the cursor position
                                    's' => {
                                        self.text_buf.saveCursorPos();
                                    },
                                    //ESC[u: loads the saved cursor position
                                    'u' => {
                                        self.text_buf.loadCursorPos();
                                    },
                                    //ESC[6n: queries the current cursor position
                                    'n' => {
                                        if(args.items.len > 0 and args.items[args.items.len-1] == 6) {
                                            //Need to write the response to the pty in the form ESC[{Row};{Column}R
                                            var buf: [256]u8 = undefined;
                                            const msg = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}R", .{self.text_buf.getScreenCursorY()+1, self.text_buf.getScreenCursorX()+1});
                                            _=pts.write(msg);
                                        }
                                    },

                                    //========================= ERASE FUNCTIONS ======================

                                    'J' => {
                                        //ESC[J/ESC[0J: Erase from cursor until end of screen
                                        if(args.items.len == 0 or args.items[args.items.len-1] == 0) {
                                            try self.text_buf.eraseText(.{.x=self.text_buf.getScreenCursorX(), .y=self.text_buf.getScreenCursorY()}, .{.x=self.text_buf.width-1, .y=self.text_buf.height-1});
                                            std.debug.print("ESC[J\n", .{});
                                        }
                                        //ESC[1J: erase from cursor to beginning of screen
                                        else if(args.items[args.items.len-1] == 1) {
                                            try self.text_buf.eraseText(.{.x=0, .y=0}, .{.x=self.text_buf.getScreenCursorX(), .y=self.text_buf.getScreenCursorY()}, );
                                            std.debug.print("ESC[1J\n", .{});
                                        }
                                        //ESC[2J: erase entire screen
                                        else if(args.items[args.items.len-1] == 2) {
                                            try self.text_buf.clearScreen();
                                            std.debug.print("ESC[2J\n", .{});
                                        }
                                        //ESC[3J: erase saved lines
                                        else if(args.items[args.items.len-1] == 3) {
                                            try self.text_buf.clearScrollback(gpa);
                                            std.debug.print("ESC[3J\n", .{});
                                        }
                                        args.clearRetainingCapacity();
                                    },
                                    'K' => {
                                        //ESC[K/ESC[0K: erase from cursor to end of line
                                        if(args.items.len == 0 or args.items[args.items.len-1] == 0) {
                                            try self.text_buf.eraseText(.{.x=self.text_buf.getScreenCursorX(), .y=self.text_buf.getScreenCursorY()}, .{.x=self.text_buf.width-1, .y=self.text_buf.getScreenCursorY()});
                                            std.debug.print("ESC[K\n", .{});
                                        }
                                        //ESC[1K: erase start line to cursor
                                        else if(args.items[args.items.len-1] == 1) {
                                            try self.text_buf.eraseText(.{.x=0, .y=self.text_buf.getScreenCursorY()}, .{.x=self.text_buf.getScreenCursorX(), .y=self.text_buf.getScreenCursorY()}, );
                                            std.debug.print("ESC[1K\n", .{});
                                        }
                                        //ESC[2K: erase entire line
                                        else if(args.items[args.items.len-1] == 2) {
                                            try self.text_buf.eraseText(.{.x=0, .y=self.text_buf.getScreenCursorY()}, .{.x=self.text_buf.width-1, .y=self.text_buf.getScreenCursorY()}, );
                                            std.debug.print("ESC[2K\n", .{});
                                        }
                                    },

                                    //========================= COLOUR/GRAPHICS MODES ================================
                                    'm' => {
                                        var sp_bg: u8 = 0;
                                        var sp_fg: u8 = 0;

                                        for(args.items[0..args.items.len]) |i| {
                                            std.debug.print("{}\n", .{i});
                                            if(sp_bg == 5) {
                                                self.text_buf.backgroundColour = c_256(@intCast(i));
                                                sp_bg = 0;
                                                continue;
                                            }
                                            if(sp_fg == 5) {
                                                self.text_buf.foregroundColour = c_256(@intCast(i));
                                                sp_fg = 0;
                                                continue;
                                            }

                                            switch(i) {
                                                // ========= STYLE CODES =========

                                                //SET CODES

                                                //ESC[1m: Set bold mode
                                                1 => {},
                                                //ESC[2m: Set dim/faint mode
                                                2 => {},
                                                //ESC[3m: Set italic mode
                                                3 => {},
                                                //ESC[4m: Set underline mode
                                                4 => {},
                                                //ESC[5m: Set blinking mode
                                                5 => {
                                                    //For xterm-256 colours
                                                    if(sp_fg == 1) sp_fg = 5;
                                                    if(sp_bg == 1) sp_bg = 5;
                                                },
                                                //ESC[7m: Set inverse/reverse mode
                                                7 => {},
                                                //ESC[8m: Set hidden/invisible mode
                                                8 => {},
                                                //ESC[9m: Set strikethrough mode
                                                9 => {},

                                                //RESET CODES

                                                //ESC[0m: Reset all styles (modes and colours)
                                                0 => {
                                                    self.text_buf.currentBackgroundColour = self.text_buf.backgroundColour;
                                                    self.text_buf.currentForegroundColour = self.text_buf.foregroundColour;
                                                },
                                                //ESC[22m: Reset bold mode/Reset dim/faint mode
                                                22 => {},
                                                //ESC[23m: Reset italic mode
                                                23 => {},
                                                //ESC[24m: Reset underline mode
                                                24 => {},
                                                //ESC[25m: Reset blinking mode
                                                25 => {},
                                                //ESC[27m: Reset inverse/reverse mode
                                                27 => {},
                                                //ESC[28m: Reset hidden/invisible mode
                                                28 => {},
                                                //ESC[29m: Reset strikethrough mode
                                                29 => {},

                                                //========= COLOUR CODES ==========

                                                //ESC[30m: Set foreground to Black
                                                30 => {self.text_buf.currentForegroundColour = tb.basic_colours[0]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[31m: Set foreground to Red
                                                31 => {self.text_buf.currentForegroundColour = tb.basic_colours[1]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[32m: Set foreground to Green
                                                32 => {self.text_buf.currentForegroundColour = tb.basic_colours[2]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[33m: Set foreground to Yellow
                                                33 => {self.text_buf.currentForegroundColour = tb.basic_colours[3]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[34m: Set foreground to Blue
                                                34 => {self.text_buf.currentForegroundColour = tb.basic_colours[4]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[35m: Set foreground to Magenta
                                                35 => {self.text_buf.currentForegroundColour = tb.basic_colours[5]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[36m: Set foreground to Cyan
                                                36 => {self.text_buf.currentForegroundColour = tb.basic_colours[6]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[37m: Set foreground to White
                                                37 => {self.text_buf.currentForegroundColour = tb.basic_colours[7]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[38m: Set foreground using xterm-256 or RGB
                                                38 => {sp_fg = 1; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[39m: Set foreground to default
                                                39 => {self.text_buf.currentForegroundColour = self.text_buf.foregroundColour; std.debug.print("Colour Changed\n", .{});},

                                                //ESC[40m: Set background to Black
                                                40 => {self.text_buf.currentBackgroundColour = tb.basic_colours[0]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[41m: Set background to Red
                                                41 => {self.text_buf.currentBackgroundColour = tb.basic_colours[1]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[42m: Set background to Green
                                                42 => {self.text_buf.currentBackgroundColour = tb.basic_colours[2]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[43m: Set background to Yellow
                                                43 => {self.text_buf.currentBackgroundColour = tb.basic_colours[3]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[44m: Set background to Blue
                                                44 => {self.text_buf.currentBackgroundColour = tb.basic_colours[4]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[45m: Set background to Magenta
                                                45 => {self.text_buf.currentBackgroundColour = tb.basic_colours[5]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[46m: Set background to Cyan
                                                46 => {self.text_buf.currentBackgroundColour = tb.basic_colours[6]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[47m: Set background to White
                                                47 => {self.text_buf.currentBackgroundColour = tb.basic_colours[7]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[48m: Set background using xterm-256 or RGB
                                                48 => {sp_bg = 1;},
                                                //ESC[49m: Set background to default
                                                49 => {self.text_buf.currentBackgroundColour = self.text_buf.backgroundColour;},

                                                //ESC[90m: Set foreground to Bright Black
                                                90 => {self.text_buf.currentForegroundColour = tb.basic_colours[8]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[91m: Set foreground to Bright Red
                                                91 => {self.text_buf.currentForegroundColour = tb.basic_colours[9]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[92m: Set foreground to Bright Green
                                                92 => {self.text_buf.currentForegroundColour = tb.basic_colours[10]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[93m: Set foreground to Bright Yellow
                                                93 => {self.text_buf.currentForegroundColour = tb.basic_colours[11]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[94m: Set foreground to Bright Blue
                                                94 => {self.text_buf.currentForegroundColour = tb.basic_colours[12]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[95m: Set foreground to Bright Magenta
                                                95 => {self.text_buf.currentForegroundColour = tb.basic_colours[13]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[96m: Set foreground to Bright Cyan
                                                96 => {self.text_buf.currentForegroundColour = tb.basic_colours[14]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[97m: Set foreground to Bright White
                                                97 => {self.text_buf.currentForegroundColour = tb.basic_colours[15]; std.debug.print("Colour Changed\n", .{});},

                                                //ESC[100m: Set background to Bright Black
                                                100 => {self.text_buf.currentBackgroundColour = tb.basic_colours[8]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[101m: Set background to Bright Red
                                                101 => {self.text_buf.currentBackgroundColour = tb.basic_colours[9]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[102m: Set background to Bright Green
                                                102 => {self.text_buf.currentBackgroundColour = tb.basic_colours[10]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[103m: Set background to Bright Yellow
                                                103 => {self.text_buf.currentBackgroundColour = tb.basic_colours[11]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[104m: Set background to Bright Blue
                                                104 => {self.text_buf.currentBackgroundColour = tb.basic_colours[12]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[105m: Set background to Bright Magenta
                                                105 => {self.text_buf.currentBackgroundColour = tb.basic_colours[13]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[106m: Set background to Bright Cyan
                                                106 => {self.text_buf.currentBackgroundColour = tb.basic_colours[14]; std.debug.print("Colour Changed\n", .{});},
                                                //ESC[107m: Set background to Bright White
                                                107 => {self.text_buf.currentBackgroundColour = tb.basic_colours[15]; std.debug.print("Colour Changed\n", .{});},

                                                else =>{}
                                            }
                                        }

                                        args.clearRetainingCapacity();
                                    },

                                    else => {}
                                }
                                self.state = parser_state.NORMAL;
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

    //Should be used to do a test run of the instructions from the pty to find any codes we are not familiar with
    fn test_parse(self: *ansi_parser) bool {
        _=self;
    }

    fn c_256(index: u8) tb.colour {
        if(index < 16) return tb.basic_colours[index];

        if(index < 232) {
            const r: u8 = (index - 16) / 36;
            const g: u8 = (r % 36) / 6;
            const b: u8 = g % 6;

            return .{r, g, b};
        }
        else {
            const c:u8 = 8 + 10 * (index - 232);
            return .{c, c, c};
        }
    }
};
