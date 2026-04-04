const std = @import("std");
const imports = @import("imports.zig");
const ca = imports.termz_core.ca;
const mu = imports.termz_core.mu;
const pty = imports.termz_core.pty;

/// Style flags for a character
pub const Style = enum(u4) { BOLD, ITALIC, UNDERLINE, NUM_STYLES };

/// Enum to keep the type of a CharacterCell
pub const TrailFlag = enum(u2) {
    /// A one-width char
    NORMAL,
    /// The start of a 2-width char
    WIDE_START,
    /// The end of a 2-width char
    WIDE_END,
};

/// Struct to represent a single character cell within the terminal.
/// Consists of:
///      a u8 representing the character in the cell
///      a u32 representing the foreground colour of the cell
///      a u32 representing the background colour of the cell
///      a bool[] representing the style flag of the cell
///      a TrailFlag representing the type of the cell
pub const character_cell = struct {
    char: u8,
    style: [@intFromEnum(Style.NUM_STYLES)]bool,
    backgroundColour: ?*mu.vec4,
    foregroundColour: ?*mu.vec4,
    trailFlag: TrailFlag,

    pub fn init(c: u8) !character_cell {
        return character_cell{ .char = c, .style = .{false, false, false}, .backgroundColour = null, .foregroundColour = null, .trailFlag = TrailFlag.NORMAL };
    }
};

/// Represents a terminal line, i.e. the entire string of characters up to its parent screen buffer's width
/// Stores both its CharacterCell string and whether it wraps from the previous line
const terminal_line = struct {
    characters: *std.ArrayList(character_cell),
    wrapped: bool,

    pub fn init(width: u32, wrap: bool, gpa: std.mem.Allocator) !terminal_line {
        const ch_ptr = try gpa.create(std.ArrayList(character_cell));
        ch_ptr.* = try std.ArrayList(character_cell).initCapacity(gpa, width);

        for(0..width) |i| {
            _=i;
            try ch_ptr.append(gpa, try character_cell.init(0));
        }
        return terminal_line{ .characters = ch_ptr, .wrapped = wrap };
    }

    pub fn deinit(self: *terminal_line, gpa: std.mem.Allocator) void {
        self.characters.deinit(gpa);
        gpa.destroy(self.characters);
    }

    pub fn clearline(self: *terminal_line) void {
        for(0..self.characters.items.len) |i| {
            self.characters.items[i].char = 0; //Setting the char to be a non-printable character by default
            self.characters.items[i].style = .{false, false, false};
            self.characters.items[i].backgroundColour = null;
            self.characters.items[i].foregroundColour = null;
            self.characters.items[i].trailFlag = TrailFlag.NORMAL;
        }
    }
};

const scroll_line = struct {
    characters: *std.ArrayList(character_cell),
    minXPos: u32,
    maxXPos: u32,

    pub fn init(width: u32, gpa: std.mem.Allocator) !scroll_line {
        const ch_ptr = try gpa.create(std.ArrayList(character_cell));
        ch_ptr.* = try std.ArrayList(character_cell).initCapacity(gpa, width);
        return scroll_line{.characters = ch_ptr, .minXPos = 2, .maxXPos = 2};
    }

    pub fn deinit(self: *scroll_line, gpa: std.mem.Allocator) void {
        self.characters.deinit(gpa);
        gpa.destroy(self.characters);
    }

    pub fn insert(self: *scroll_line, pos: u32, ch: character_cell, gpa: std.mem.Allocator) !void {
        if(pos > self.maxXPos+1) {
            for(self.maxXPos+1..pos) |i| {
                _=i;
                try self.characters.append(gpa, try character_cell.init(0));
                self.maxXPos += 1;
            }
        }

        try self.characters.insert(gpa, pos, ch);
        self.maxXPos += 1;
    }

    pub fn overwrite(self: *scroll_line, pos: u32, ch: u8, gpa: std.mem.Allocator) !void {
        if(pos > self.maxXPos) {
            try self.insert(pos, try character_cell.init(ch), gpa);
        }
        else {
            self.characters.items[pos].char = ch;
        }
    }

    pub fn delete(self: *scroll_line, pos: u32) !character_cell {
        const ret = self.characters.orderedRemove(@intCast(pos));
        if(pos == self.maxXPos) {
            for(self.characters.items.len..0) |i| {
                self.maxXPos -= 1;
                if(self.characters.items[i].char != 0) {
                    break;
                }
                else {
                    _= self.characters.orderedRemove(i);
                }
            }
        }
        else {
            self.maxXPos -= 1;
        }

        return ret;
    }
};

//TODO: OVERWRITE TEXT FUNCTION
//      ERASURE FUNCTION

/// A struct implementing a Terminal text buffer for holding the text currently on the screen and that has been scrolled past
/// Stores two buffers for the screen and scrollback content, alongside the current cursor position
/// It also the foreground and background colours the screen should default to.
pub const text_buffer = struct {
    width: u32,
    height: u32,
    cursorX: u32,
    cursorY: u32,
    bottomIndex: u32,
    bottomOffset: u32,
    backgroundColour: *mu.vec4,
    foregroundColour: *mu.vec4,
    scrollback: *std.ArrayList(*scroll_line),
    screen: *ca.CircularArray(*terminal_line, null),

    pub fn init(w: u32, h: u32, gpa: std.mem.Allocator) !text_buffer {
        const sb_ptr = try gpa.create(std.ArrayList(*scroll_line));
        sb_ptr.* = try std.ArrayList(*scroll_line).initCapacity(gpa, h * 2);

        const init_line = try gpa.create(scroll_line);
        init_line.* = try scroll_line.init(w, gpa);

        try sb_ptr.*.append(gpa, init_line);

        const s_ptr = try gpa.create(ca.CircularArray(*terminal_line, null));
        s_ptr.* = try ca.CircularArray(*terminal_line, null).init(gpa, h);

        for(0..h) |i| {
            _=i;
            const init_tline = try gpa.create(terminal_line);
            init_tline.* = try terminal_line.init(w, false, gpa);

            try s_ptr.addToFront(init_tline, gpa);
        }

        const bc_ptr = try gpa.create(mu.vec4);
        bc_ptr.* = mu.vec4.init(0.0, 0.0, 0.0, 1.0);

        const fc_ptr = try gpa.create(mu.vec4);
        fc_ptr.* = mu.vec4.init(1.0, 1.0, 1.0, 1.0);

        return text_buffer{ .width = w, .height = h, .cursorX = 0, .cursorY = 0, .bottomIndex = 0, .bottomOffset = 1, .backgroundColour = bc_ptr, .foregroundColour = fc_ptr, .scrollback = sb_ptr, .screen = s_ptr };
    }

    pub fn deinit(self: *text_buffer, gpa: std.mem.Allocator) void {
        gpa.destroy(self.backgroundColour);
        gpa.destroy(self.foregroundColour);

        for(0..self.screen.size) |i| {
            const line = self.screen.get(@intCast(i));
            line.deinit(gpa);
            gpa.destroy(line);
        }
        self.screen.deinit(gpa);
        gpa.destroy(self.screen);

        for(0..self.scrollback.items.len) |i| {
            const line = self.scrollback.items[i];
            line.deinit(gpa);
            gpa.destroy(line);
        }
        self.scrollback.deinit(gpa);
        gpa.destroy(self.scrollback);
    }

    /// @return the on-screen x position of the cursor
    pub fn getScreenCursorX(self: *text_buffer) u32 {
        return self.cursorX % self.width;
    }

    /// @return the on-screen y position of the cursor
    pub fn getScreenCursorY(self: *text_buffer) u32 {
        //If the number of lines in the scrollback is less than the height
        var screen_height = self.height;
        if(self.scrollback.items.len <= self.height) {
            //Check if we even have space to scroll
            var line_sum: u32 = 0;
            for(0..self.scrollback.items.len) |i| {
                line_sum += self.logicalToTerminal(i);
            }

            screen_height = @min(line_sum, self.height);
        }

        var screenY: u32 = screen_height-self.bottomOffset;
        var logicalY: u32 = self.bottomIndex;

        while(logicalY >= self.cursorY) {
            screenY -= @min(screenY, self.logicalToTerminal(logicalY)-1);
            if(logicalY <= 0) break;
            logicalY -= 1;
        }

        // Add how far into the cursor line's wrapped segments we are
        screenY += self.cursorX / self.width;

        return @max(0, @min(screenY, self.height - 1)); //Clamp the value
    }

    /// Sets the height of the screen and rebuilds the layout
    /// @param val the new screen height
    pub fn setHeight(self: *text_buffer, h: u32, gpa: std.mem.Allocator) !void {
        self.height = h;
        try self.rebuildScreen(true, gpa);
    }

    /// Sets the width of the screen and rebuilds the layout
    /// @param val the new screen width
    pub fn setWidth(self: *text_buffer, w: u32, gpa: std.mem.Allocator) !void {
        self.width = w;
        try self.rebuildScreen(true, gpa);
    }

    // =============== CURSOR OPERATIONS ==================

    /// Sets a cursor's x position to the specified position, clamped between [0, logical line width)
    /// If the cursor ends at a cell with {@link TrailFlag} WIDE_END, move one cell to the left
    /// @param val the new x position to move the cursor to
    pub fn setCursorX(self: *text_buffer, val: u32, gpa: std.mem.Allocator) !void {
        self.cursorX = @max(0, val);
        if(self.cursorY == self.scrollback.items.len-1 and self.bottomIndex == self.scrollback.items.len-1 and
            self.screen.get(@intCast(self.screen.size-1)).characters.items.len == self.width and
            self.cursorX != 0 and self.cursorX % self.width == 0) {
            if(self.screen.size == self.height) {
                try self.scroll(1, gpa);
            }
        }

        if (self.cursorX > 0 and self.cursorX < self.scrollback.items[self.cursorY].characters.items.len and self.scrollback.items[self.cursorY].characters.items[self.cursorX].trailFlag == TrailFlag.WIDE_END) //Cursor can never land on the end of a wide character
            self.cursorX -= 1;
    }

    /// Sets a cursor's y position to the specified position, clamped between [0, scrollback height)
    /// If the new position is on a line off of the screen, scroll
    /// @param val the new x position to move the cursor to
    pub fn setCursorY(self: *text_buffer, val: u32, gpa: std.mem.Allocator) !void {
        const screenTop: u32 = self.getLogicalScreenTop();
        const clampedVal: i32 = @as(i32, @intCast(@max(0, @min(val, self.scrollback.items.len - 1))));

        if (clampedVal < screenTop) {
            try self.scroll(clampedVal - @as(i32, @intCast(screenTop)), gpa);
        } else if (clampedVal > self.bottomIndex) {
            try self.scroll(clampedVal - @as(i32, @intCast(self.bottomIndex)), gpa);
        }

        self.cursorY = @intCast(clampedVal);
        // try self.setCursorX(@min(self.cursorX, self.scrollback.items[self.cursorY].characters.items.len), gpa); //Setting the x position so that its at not off the end of the line we moved to
    }

    /// Moves the cursor's x position by some amount of steps. Negative values move to the left, positive values move to the right.
    /// The cursor's end position is clamped between [0, line_width), where line_width is the number of characters in the unwrapped line the cursor is on
    /// If the cursor ends at a cell with TrailFlag WIDE_END, move one cell in the direction you want to move to
    /// @param val the number of steps to move
    pub fn moveCursorX(self: *text_buffer, val: i32, isUser: bool, gpa: std.mem.Allocator) !void {
        var pos: u32 = @intCast(@max(0, val + @as(i32, @intCast(self.cursorX))));

        const line: *scroll_line = self.scrollback.items[self.cursorY];
        //If we are moving to an empty flag, skip it
        if (pos > 0 and pos < line.characters.items.len and line.characters.items[pos].trailFlag == TrailFlag.WIDE_END) {
            if (pos < line.characters.items.len and val > 0) {
                pos += 1;
            } //If moving right
            else if (pos > 0 and val < 0) {
                pos -= 1;
            } //If moving left
        }

        if(isUser) pos = @max(line.minXPos, @min(pos, line.characters.items.len));
        try self.setCursorX(pos, gpa);
    }

    /// Moves the cursor's y position by some amount of steps. If the movement would cause the cursor to move off the screen, scroll
    /// The cursor's end position is clamped between [0, number of lines)
    /// @param val the number of steps to move
    pub fn moveCursorY(self: *text_buffer, val: i32, gpa: std.mem.Allocator) !void {
        try self.setCursorY(@as(u32, @intCast(val + @as(i32, @intCast(self.cursorY)))), gpa);
    }

    pub fn screenToLogical(self: *text_buffer, screenY: u32, screenX: u32, gpa: std.mem.Allocator) !void {
        //Clamp the given values
        const localScreenY = @max(0, @min(screenY, self.height-1));
        const localScreenX = @max(0, @min(screenX, self.width-1));

        var lines = self.bottomOffset;
        var logicalY  = self.bottomIndex;

        while(logicalY >= self.getLogicalScreenTop()) {
            if (lines == 0) {
                logicalY -= 1;
                lines = self.logicalToTerminal(logicalY);
            }

            if(self.height - lines == localScreenY) {
                self.cursorY = logicalY;
                self.cursorX = (lines-1) * self.width + localScreenX;
                try self.setCursorX(self.cursorX, gpa);
            }

            lines -= 1;
        }
    }

    // =============== BUFFER MANIPULATION ==================

    /// Moves the bottom index of the screen by some number of spaces
    /// Clears the current screen buffer and rebuilds it using the new bottom of the screen as a reference into the scrollback
    /// @param spaces the number of spaces to scroll by. negative means down, positive means up
    pub fn scroll(self: *text_buffer, spaces: i32, gpa: std.mem.Allocator) !void {
        if(spaces == 0) return; //If we are not moving, early exit

        //If the number of lines in the scrollback is less than the height
        if(self.scrollback.items.len <= self.height) {
            //Check if we even have space to scroll
            var line_sum: u32 = 0;
            for(0..self.scrollback.items.len) |i| {
                line_sum += self.logicalToTerminal(i);
            }
            if(line_sum < self.height) return;
        }

        //If we are scrolling beyond the boundaries of the screen, just rebuild it
        if(@abs(spaces) >= self.height) try self.rebuildScreen(false, gpa);

        //Get the current scrollback line
        var sline = self.scrollback.items[self.bottomIndex];
        var line_x = self.cursorX; //And the current x position
        //Moving down
        if(spaces > 0) {
            //Iterate over the number of spaces we are scrolling down
            for(0..@intCast(spaces)) |i| {
                _=i;

                //Add an empty line at the bottom
                const tline = try self.screen.removeFromFront(gpa);
                tline.clearline();
                try self.screen.addToBack(tline, gpa);

                //If we have reached the end of the line
                if(line_x >= sline.characters.items.len) {
                    if(self.bottomIndex == self.scrollback.items.len-1) break; //If we are at the end of the scrollback, early exit
                    line_x = 0; //Otherwise reset the x position
                    self.bottomIndex += 1; //And move the bottom index down
                    self.bottomOffset = 1;
                    sline = self.scrollback.items[self.bottomIndex]; //Get the next logical line
                }

                //Copy the next batch of characters over onto this line
                for(0..@min(self.width, sline.characters.items.len-line_x)) |x| {
                    tline.characters.items[x].char = sline.characters.items[line_x+x].char;
                }
                line_x += self.width; //Increment the x position
                self.bottomOffset += 1;
            }
        }
        //Moving up
        else if (spaces < 0) {
            //Iterate over number of spaces we are moving up
            for(0..@abs(spaces)) |i| {
                _=i;

                //If we are at or beyond the start of the line
                if(line_x-1 <= 0) {
                    if(self.bottomIndex == 0) break; //If at the top of the screen, early exit
                    self.bottomIndex -= 1; //Otherwise move the bottomIndex back one
                    self.bottomOffset = self.logicalToTerminal(self.bottomIndex);
                    sline = self.scrollback.items[self.bottomIndex]; //Get the next logical line
                    line_x = @intCast(sline.characters.items.len); //Set the x position to be at the end of the line
                }

                const tline = try self.screen.removeFromBack(gpa);
                tline.clearline();
                try self.screen.addToFront(tline, gpa);

                const cap = @min(self.width, line_x); //The capacity that this line can be filled to
                //Fill the line backwards
                for(1..cap) |x| {
                    tline.characters.items[cap-x].char = sline.characters.items[line_x-x].char;
                }
                line_x -= self.width; //Move the x position back
                self.bottomOffset -= 1;
            }
        }

        self.bottomOffset = @max(0, @min(self.bottomOffset, self.logicalToTerminal(self.bottomIndex)));
    }

    /// Inserts a new line
    /// Moves the cursor down one line, scrolling if necessary
    pub fn createNewLine(self: *text_buffer, gpa: std.mem.Allocator) !bool {
        try self.addNewLine(gpa);
        return true;
    }

    /// Clears the lines from the screen. Does not remove anything from the scrollback
    pub fn clearScreen(self: *text_buffer) void {
        for(0..self.height) |i| {
            self.screen.get(@intCast(i)).clearline();
        }
    }

    /// Clears all data from the scrollback except what is currently on the screen
    pub fn clearScrollback(self: *text_buffer, gpa: std.mem.Allocator) !void {
        self.scrollback.clearRetainingCapacity(); //Clear all of the data from the scrollback

        //Copy everything currently on the screen into the scrollback
        var scroll_line_ptr: *scroll_line = undefined;
        for(0..self.height) |i| {
            //Get the current screen line
            const tline = self.screen.get(@intCast(i));
            //If the top line wrapped from something that was in the scrollback, reset it since that other thing doesn't exist anymore
            if(i == 0 and tline.wrapped) tline.wrapped = false;

            //If the screen line doesn't wrap from anything, need to create a new scrollback line to hold it
            if(!tline.wrapped) {
                const nline_ptr = try gpa.create(scroll_line);
                nline_ptr.* = try scroll_line.init(self.width, gpa);
                try self.scrollback.append(gpa, nline_ptr);
                scroll_line_ptr = nline_ptr;
            }

            //Finding the last actually inserted char to remove any extraneous chars
            var end_ch = self.width;
            while(end_ch > 1) {
                if(tline.characters.items[end_ch-1].char != 0) break;
                end_ch -= 1;
            }

            //Copy the terminal line into the scrollback
            for(0..end_ch) |j| {
                try scroll_line_ptr.characters.append(gpa, tline.characters.items[j]);
            }
        }

            self.bottomIndex = @intCast(self.scrollback.items.len-1);
            self.bottomOffset = self.logicalToTerminal(self.bottomIndex);
    }

    /// Clears all data in screen and scrollback buffers
    pub fn clearScreenAndScrollBack(self: *text_buffer) !void {
        self.scrollback.clearRetainingCapacity();
        self.clearScreen();
    }

    // =============== TEXT EDITING ==================

    /// Inserts text at the mouse cursor's position only if the cursor is at the bottom of the screen and scrollback
    /// Moves the cursor to the right w times, where w is the width of the input character
    /// If the cursor starts at the end of a wide character, moves one space to the left before writing
    /// If inserting the input at the current position would overlap with other wide characters, erase them first
    /// @param text the new character to add
    /// @return true if the text was inserted, false if the cursor is not at the bottom line
    pub fn insertText(self: *text_buffer, text: u8, gpa: std.mem.Allocator) !bool {
        const sline: *scroll_line = self.scrollback.items[self.cursorY];
        var tline: *terminal_line = self.screen.get(self.getScreenCursorY());

        // const oldLines: u32 = self.logicalToTerminal(self.cursorY);

        const ch_ptr = try character_cell.init(text);
        try sline.insert(self.cursorX, ch_ptr, gpa);
        try tline.characters.insert(gpa, self.getScreenCursorX(), ch_ptr);

        var end_ch = tline.characters.orderedRemove(tline.characters.items.len-1);
        var line_y = self.getScreenCursorY();
        while(end_ch.char != 0) {
            //If at the bottom of the screen, need to scroll
            if(line_y >= self.height-1) {
                try self.scroll(1, gpa);
            }

            line_y += 1;
            tline = self.screen.get(line_y); //Update the current line
            try tline.characters.insert(gpa, 0, end_ch); //Insert the end character from the previous line at the start of this one
            tline.wrapped = true; //Must be true since we wrapped from the previous line
            end_ch = tline.characters.orderedRemove(tline.characters.items.len-1); //Update the new end char
        }
        try self.moveCursorX(1, false, gpa);
        return true;
    }

    /// Moves the cursor left one position and removes the character at the cursor's new position
    /// If the cursor lands on a wide char, removes both characters in the char
    /// @param gpa the allocator to use to allocate new screen data if necessary
    /// @return true on successful removal, false if it is not at the bottom line in the scrollback or if there is no char to erase
    pub fn deleteText(self: *text_buffer, gpa: std.mem.Allocator) !bool {
        const sline: *scroll_line = self.scrollback.items[self.cursorY];
        if(self.cursorX <= 0 or self.cursorX <= sline.minXPos) return false;

        self.cursorX -= 1;
        var tline: *terminal_line = self.screen.get(self.getScreenCursorY());
        _=try sline.delete(self.cursorX);
        _=tline.characters.orderedRemove(self.getScreenCursorX());

        var line_y = self.getScreenCursorY();
        var end_ch = if(line_y < self.height-1 and self.screen.get(line_y+1).wrapped) self.screen.get(line_y+1).characters.orderedRemove(0) else try character_cell.init(0);

        while(end_ch.char != 0) {
            try tline.characters.append(gpa, end_ch);
            line_y += 1;
            tline = self.screen.get(line_y);
            end_ch = if(line_y < self.height-1 and self.screen.get(line_y+1).wrapped) self.screen.get(line_y+1).characters.orderedRemove(0) else try character_cell.init(0);
        }
        return true;
    }

    // =============== PTY FUNCTIONS =================

    pub fn writeToPTY(self: *text_buffer, pts: *pty.PTY, gpa: std.mem.Allocator) void {
        const line: *scroll_line = self.scrollback.items[self.cursorY];

        if(line.characters.items.len > line.minXPos) {
            std.debug.print("Writing {} bytes to PTY\n", .{line.characters.items.len-line.minXPos});
            var charBuf: []u8 = gpa.alloc(u8, line.characters.items.len-line.minXPos) catch return;
            @memset(charBuf, 0);
            for(line.minXPos..line.characters.items.len) |i|{
                charBuf[i-line.minXPos] = line.characters.items[i].char;
            }
            const n = std.os.linux.write(pts.master, @ptrCast(&charBuf[0]), line.characters.items.len-line.minXPos);
            std.debug.print("Wrote {} bytes\n", .{n});
            gpa.free(charBuf);
        }
        const n2 = std.os.linux.write(pts.master, "\n", 1);
        std.debug.print("Wrote newline: {}\n", .{n2});
    }

    // =============== DEBUG FUNCTIONS ==================

    pub fn printScreenContents(self: *text_buffer) void {
        for(0..self.screen.size) |i| {
            const line = self.screen.get(@intCast(i));
            for(0..line.characters.items.len) |j| {
                if(line.characters.items[j].trailFlag != TrailFlag.WIDE_END) //Skip dummy chars
                    std.debug.print("{c}", .{line.characters.items[j].char});
            }
            std.debug.print("\n", .{});
        }
    }

    // =============== HELPER FUNCTIONS ==================

    /// Rebuilds the screen from the bottom index
    fn rebuildScreen(self: *text_buffer, rebuild: bool, gpa: std.mem.Allocator) !void {
        if(rebuild) {
            for(0..self.screen.size) |i| {
                const line = self.screen.get(@intCast(i));
                line.deinit(gpa);
                gpa.destroy(line);
            }
            try self.screen.clear(gpa);

            for(0..self.height) |i| {
                _=i;
                const init_tline = try gpa.create(terminal_line);
                init_tline.* = try terminal_line.init(self.width, false, gpa);

                try self.screen.addToFront(init_tline, gpa);
            }
        }

        var tline_index = self.height-1;
        var tline_ptr = self.screen.get(@intCast(tline_index));
        var sline_index = self.bottomIndex;
        var sline_ptr = self.scrollback.items[sline_index];
        while(sline_index >= 0 and tline_index > 0) {
            const num_lines = self.logicalToTerminal(sline_index);

            for(0..num_lines) |i| {
                if(tline_index - (num_lines - i+1) < 0) continue;

                for(i * self.width..@min((i+1)*self.width, sline_ptr.characters.items.len)) |x| {
                    tline_ptr.characters.items[x - (i * self.width)].char = sline_ptr.characters.items[x].char;
                }
            }

            tline_index -= num_lines;
            if(tline_index == 0) break;

            tline_ptr = self.screen.get(@intCast(tline_index));
            if(sline_index == 0) break;
            sline_index -= 1;
            sline_ptr = self.scrollback.items[sline_index];
        }

        while(tline_index >= 0) {
            try self.screen.addToBack(try self.screen.removeFromFront(gpa), gpa);
            if(tline_index == 0) break;
            tline_index -= 1;
        }

        self.bottomOffset = self.logicalToTerminal(self.bottomIndex);
    }

    /// Adds an empty line to the bottom of the screen and removes extra lines if we are over the scrollback buffer
    fn addNewLine(self: *text_buffer, gpa: std.mem.Allocator) !void {
        const nline_ptr = try gpa.create(scroll_line);
        nline_ptr.* = try scroll_line.init(self.width, gpa);
        try self.scrollback.insert(gpa, self.cursorY+1, nline_ptr);
        if(self.cursorY == self.bottomIndex) try self.scroll(1, gpa);
        self.cursorY += 1;
        if(self.bottomIndex < self.cursorY) {
            self.bottomIndex = self.cursorY;
            self.bottomOffset = 1;
        }
        self.cursorX = 0;
    }

    /// Helper function to see how many Terminal screen lines the logical line at the given index takes up
    /// @param index the index of the logical line whose size in terminal lines we want to know
    /// @return the number of lines this logical line takes up
    fn logicalToTerminal(self: *text_buffer, index: usize) u32 {
        return @max(1, (@as(u32, @intCast(self.scrollback.items[index].characters.items.len + self.width-1))) / self.width);
    }

    /// Helper function to get the logical line at the top of the current screen
    /// @return the index of the logical line at the top of the screen
    fn getLogicalScreenTop(self: *text_buffer) u32 {
        var screenTop: u32 = self.bottomIndex; //The logical line at the top of the screen
        var remainingRows: usize = self.screen.size - 1; //Number of rows we haven't seen to be filled by a logical line in the screen

        while (screenTop > 0 and remainingRows > 0) {
            remainingRows -= self.logicalToTerminal(screenTop); //Otherwise decrease the number of remaining unfilled rows on the screen
            screenTop -= 1; //Move to the next line up
        }

        return screenTop;
    }
};
