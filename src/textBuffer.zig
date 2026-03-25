const std = @import("std");
const imports = @import("imports.zig");
const ca = imports.termz_core.ca;
const mu = imports.termz_core.mu;

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
    width: u32,
    wrapped: bool,

    pub fn init(width: u32, wrap: bool, gpa: std.mem.Allocator) !terminal_line {
        const ch_ptr = try gpa.create(std.ArrayList(character_cell));
        ch_ptr.* = try std.ArrayList(character_cell).initCapacity(gpa, width);
        // if(!wrap) {
        //     try ch_ptr.append(gpa, try character_cell.init('$'));
        //     try ch_ptr.append(gpa, try character_cell.init(' '));
        // }
        return terminal_line{ .characters = ch_ptr, .width = width, .wrapped = wrap };
    }

    pub fn deinit(self: *terminal_line, gpa: std.mem.Allocator) void {
        self.characters.deinit(gpa);
        // gpa.free(self);
        gpa.destroy(self.characters);
    }
};

/// A struct implementing a Terminal text buffer for holding the text currently on the screen and that has been scrolled past
/// Stores two buffers for the screen and scrollback content, alongside the current cursor position
/// It also the foreground and background colours the screen should default to.
pub const text_buffer = struct {
    width: u32,
    height: u32,
    cursorX: u32,
    cursorY: u32,
    bottomIndex: u32,
    backgroundColour: *mu.vec4,
    foregroundColour: *mu.vec4,
    scrollback: *std.ArrayList(*std.ArrayList(character_cell)),
    screen: *ca.CircularArray(*terminal_line, null),

    pub fn init(w: u32, h: u32, gpa: std.mem.Allocator) !text_buffer {
        const sb_ptr = try gpa.create(std.ArrayList(*std.ArrayList(character_cell)));
        sb_ptr.* = try std.ArrayList(*std.ArrayList(character_cell)).initCapacity(gpa, h * 2);

        const init_line = try gpa.create(std.ArrayList(character_cell));
        init_line.* = try std.ArrayList(character_cell).initCapacity(gpa, w);

        try sb_ptr.*.append(gpa, init_line);

        const s_ptr = try gpa.create(ca.CircularArray(*terminal_line, null));
        s_ptr.* = try ca.CircularArray(*terminal_line, null).init(gpa, h);

        const init_tline = try gpa.create(terminal_line);
        init_tline.* = try terminal_line.init(w, false, gpa);

        try s_ptr.addToFront(init_tline, gpa);

        const bc_ptr = try gpa.create(mu.vec4);
        bc_ptr.* = mu.vec4.init(1.0, 1.0, 1.0, 1.0);

        const fc_ptr = try gpa.create(mu.vec4);
        fc_ptr.* = mu.vec4.init(0.0, 0.0, 0.0, 1.0);

        return text_buffer{ .width = w, .height = h, .cursorX = 0, .cursorY = 0, .bottomIndex = 0, .backgroundColour = bc_ptr, .foregroundColour = fc_ptr, .scrollback = sb_ptr, .screen = s_ptr };
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
        var screenY: u32 = self.screen.size - 1; //Need it to be number of actual lines in the screen rather than height to avoid errors when not enough lines to fill the whole screen
        var logicalY: u32 = self.bottomIndex;

        //See how far up in the screen the cursor's logical line is
        while (logicalY >= self.cursorY) {
            screenY -= self.logicalToTerminal(logicalY)-1;
            // if(logicalY <= self.cursorY or logicalY <= 0) break;
            if(logicalY <= 0) break;
            logicalY -= 1;
        }

        // Add how far into the cursor line's wrapped segments we are
        const lineLen = self.scrollback.items[self.cursorY].items.len;
        const wrappedRow = if (lineLen > 0 and self.cursorX == lineLen and self.cursorX % self.width == 0)
            self.cursorX / self.width - 1  // exactly at a boundary, still on the row above
        else
            self.cursorX / self.width;

        screenY += wrappedRow;
        // Add how far into the cursor line's wrapped segments we are
        // screenY += self.cursorX / self.width;

        return @max(0, @min(screenY, self.height - 1)); //Clamp the value
    }

    /// Sets the height of the screen and rebuilds the layout
    /// @param val the new screen height
    pub fn setHeight(self: *text_buffer, h: u32, gpa: std.mem.Allocator) !void {
        self.height = h;
        try self.rebuildScreen(gpa);
    }

    /// Sets the width of the screen and rebuilds the layout
    /// @param val the new screen width
    pub fn setWidth(self: *text_buffer, w: u32, gpa: std.mem.Allocator) !void {
        self.width = w;
        try self.rebuildScreen(gpa);
    }

    // =============== CURSOR OPERATIONS ==================

    /// Sets a cursor's x position to the specified position, clamped between [0, logical line width)
    /// If the cursor ends at a cell with {@link TrailFlag} WIDE_END, move one cell to the left
    /// @param val the new x position to move the cursor to
    pub fn setCursorX(self: *text_buffer, val: u32, gpa: std.mem.Allocator) !void {
        self.cursorX = @max(0, @min(val, self.scrollback.items[self.cursorY].items.len));
        // std.debug.print("CursorX: {}\n", .{self.cursorX});
        // std.debug.print("Screen CursorX: {}\n", .{self.getScreenCursorX()});
        // std.debug.print("Screen CursorY: {}\n", .{self.getScreenCursorY()});
        if(self.cursorY == self.scrollback.items.len-1 and self.bottomIndex == self.scrollback.items.len-1 and
            self.screen.get(@intCast(self.screen.size-1)).characters.items.len == self.width and
            self.cursorX != 0 and self.cursorX % self.width == 0) {
            if(self.screen.size == self.height) {
                try self.scroll(1, gpa);
            }
            const tline_ptr = try gpa.create(terminal_line);
            tline_ptr.* = try terminal_line.init(self.width, true, gpa);
            try self.screen.addToBack(tline_ptr, gpa);
        }

        if (self.cursorX > 0 and self.cursorX < self.scrollback.items[self.cursorY].items.len and self.scrollback.items[self.cursorY].items[self.cursorX].trailFlag == TrailFlag.WIDE_END) //Cursor can never land on the end of a wide character
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
        try self.setCursorX(@min(self.cursorX, self.scrollback.items[self.cursorY].items.len), gpa); //Setting the x position so that its at not off the end of the line we moved to
    }

    /// Moves the cursor's x position by some amount of steps. Negative values move to the left, positive values move to the right.
    /// The cursor's end position is clamped between [0, line_width), where line_width is the number of characters in the unwrapped line the cursor is on
    /// If the cursor ends at a cell with TrailFlag WIDE_END, move one cell in the direction you want to move to
    /// @param val the number of steps to move
    pub fn moveCursorX(self: *text_buffer, val: i32, gpa: std.mem.Allocator) !void {
        var pos: u32 = @intCast(@max(0, val + @as(i32, @intCast(self.cursorX))));

        const line: *std.ArrayList(character_cell) = self.scrollback.items[self.cursorY];
        //If we are moving to an empty flag, skip it
        if (pos > 0 and pos < line.items.len and line.items[pos].trailFlag == TrailFlag.WIDE_END) {
            if (pos < line.items.len and val > 0) {
                pos += 1;
            } //If moving right
            else if (pos > 0 and val < 0) {
                pos -= 1;
            } //If moving left
        }
        try self.setCursorX(pos, gpa);
    }

    /// Moves the cursor's y position by some amount of steps. If the movement would cause the cursor to move off the screen, scroll
    /// The cursor's end position is clamped between [0, number of lines)
    /// @param val the number of steps to move
    pub fn moveCursorY(self: *text_buffer, val: i32, gpa: std.mem.Allocator) !void {
        try self.setCursorY(@as(u32, @intCast(val + @as(i32, @intCast(self.cursorY)))), gpa);
    }

    // =============== BUFFER MANIPULATION ==================

    /// Moves the bottom index of the screen by some number of spaces
    /// Clears the current screen buffer and rebuilds it using the new bottom of the screen as a reference into the scrollback
    /// @param spaces the number of spaces to scroll by. negative means down, positive means up
    pub fn scroll(self: *text_buffer, spaces: i32, gpa: std.mem.Allocator) !void {
        self.bottomIndex = @as(u32, @intCast(@max(0, @min(@as(i32, @intCast(self.bottomIndex)) + spaces, @as(i32, @intCast(self.scrollback.items.len)) - 1)))); //Calculate the new screen bottom

        try self.rebuildScreen(gpa);
    }

    /// Adds an empty line to the bottom of the screen and removes extra lines if we are over the scrollback buffer.
    /// Moves the cursor down one line, scrolling if necessary
    pub fn createNewLine(self: *text_buffer, gpa: std.mem.Allocator) !bool {
        if (self.cursorY != self.scrollback.items.len - 1 or self.bottomIndex != self.scrollback.items.len - 1) return false; //Early exit when not at the bottom of the screen

        try self.addNewLine(gpa);
        return true;
    }

    /// Clears the lines from the screen. Does not remove anything from the scrollback
    pub fn clearScreen(self: *text_buffer, gpa: std.mem.Allocator) !void {
        try self.addNewLine(gpa);
        try self.screen.clear();
        const nline_ptr = try gpa.create(terminal_line);
        nline_ptr.* = try terminal_line.init(self.width, false, gpa);
        try self.screen.addToFront(nline_ptr);

        self.cursorX = 0;
        self.cursorY = 0;
    }

    /// Clears all data in screen and scrollback buffers and resets the cursor position
    pub fn clearScreenAndScrollBack(self: *text_buffer, gpa: std.mem.Allocator) void {
        self.scrollback.clearRetainingCapacity();
        self.screen.clear(gpa);
        self.addLine();

        //Resetting cursor position
        self.cursorX = 0;
        self.cursorY = 0;
    }

    // =============== TEXT EDITING ==================

    /// Inserts text at the mouse cursor's position only if the cursor is at the bottom of the screen and scrollback
    /// Moves the cursor to the right w times, where w is the width of the input character
    /// If the cursor starts at the end of a wide character, moves one space to the left before writing
    /// If inserting the input at the current position would overlap with other wide characters, erase them first
    /// @param text the new character to add
    /// @return true if the text was inserted, false if the cursor is not at the bottom line
    pub fn insertText(self: *text_buffer, text: u8, gpa: std.mem.Allocator) !bool {
        if (self.cursorY != self.scrollback.items.len - 1 or self.bottomIndex != self.scrollback.items.len - 1) return false;

        const line: *std.ArrayList(character_cell) = self.scrollback.items[self.cursorY];
        const oldLines: u32 = self.logicalToTerminal(self.cursorY);

        const ch_ptr = try character_cell.init(text);
        try line.insert(gpa, self.cursorX, ch_ptr);

        if (oldLines < self.logicalToTerminal(self.cursorY)) {
            try self.rebuildScreen(gpa);
        } //Need to shift the screen down
        else { //Otherwise just write to the screen as well
            try self.screen.get(self.getScreenCursorY()).characters.insert(gpa, self.getScreenCursorX(), ch_ptr);
        }

        try self.moveCursorX(1, gpa);
        return true;
    }

    /// Moves the cursor left one position and removes the character at the cursor's new position
    /// If the cursor lands on a wide char, removes both characters in the char
    /// @param gpa the allocator to use to allocate new screen data if necessary
    /// @return true on successful removal, false if it is not at the bottom line in the scrollback or if there is no char to erase
    pub fn deleteText(self: *text_buffer, gpa: std.mem.Allocator) !bool {
        if(self.cursorY != self.scrollback.items.len-1 or self.bottomIndex != self.scrollback.items.len-1 or self.cursorX <= 0) return false;

        const line: *std.ArrayList(character_cell)= self.scrollback.items[self.cursorY];
        var oldLines: u32 = self.logicalToTerminal(self.cursorY);
        if(self.cursorX != 0 and self.cursorX % self.width == 0) oldLines += 1; //Technically if the cursor wraps around to a new line the line takes up an extra screen line

        self.cursorX-=1; //Move the cursor back one space

        // const deleted: character_cell = line.items[self.cursorX]; //Get the char to be deleted

        // if(deleted.getTrailFlag() == TrailFlag.WIDE_END) { //If on second half of a wide char need to delete both halves
        //     line.remove(cursorX-1);
        //     line.remove(cursorX-1); //Calling it twice moves the second half back to the cursor's position
        // }
        // else if(deleted.getTrailFlag() == TrailFlag.WIDE_START) {
        //     line.remove(cursorX);
        //     line.remove(cursorX); //Calling it twice moves the second half back to the cursor's position
        // }
        // else {
            _ = line.orderedRemove(self.cursorX);
        // }

        if(oldLines != self.logicalToTerminal(self.cursorY)) {try self.rebuildScreen(gpa);} //Need to shift the screen down
        else {
            const screenLine: *terminal_line = self.screen.get(self.getScreenCursorY());
            // if(deleted.getTrailFlag() == TrailFlag.WIDE_END) { //If on second half of a wide char need to delete both halves
            //     cursorX--;
            //     screenLine.remove(getScreenCursorX());
            //     screenLine.remove(getScreenCursorX()); //Calling it twice moves the second half back to the cursor's position
            // }
            // else if(deleted.getTrailFlag() == TrailFlag.WIDE_START) {
            //     screenLine.remove(getScreenCursorX());
            //     screenLine.remove(getScreenCursorX()); //Calling it twice moves the second half back to the cursor's position
            // }
            // else {
                _ = screenLine.characters.orderedRemove(self.getScreenCursorX());
            // }
        }

        return true;
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
    fn rebuildScreen(self: *text_buffer, gpa: std.mem.Allocator) !void {
        for(0..self.screen.size) |i| {
            const line = self.screen.get(@intCast(i));
            line.deinit(gpa);
            gpa.destroy(line);
        }
        try self.screen.clear(gpa);

        const start: u32 = @max(0, @as(i32, @intCast(self.bottomIndex)) - @as(i32, @intCast(self.height)) + 1); //Get the top of the new screen

        for (start..self.bottomIndex + 1) |i| {
            try self.wrapLogicalLine(self.scrollback.items[i], gpa); //Wrap the line so it fits the current screen width
        }
    }

    /// Wraps logical lines so they fit the screen width
    /// If the character at the end of a screen line would be the first half of a 2-wide character, wraps onto a new line
    /// @param logical the full logical line
    fn wrapLogicalLine(self: *text_buffer, logical: *std.ArrayList(character_cell), gpa: std.mem.Allocator) !void {
        var index: u32 = 0;

        while (true) {
            const screenLine: *terminal_line = try gpa.create(terminal_line); //Creating a new screen line
            screenLine.* = try terminal_line.init(self.width, index != 0, gpa);

            var x: u32 = 0; //Tracks the x position in the screen line
            while (x < self.width and index < logical.items.len) {
                const cell: character_cell = logical.items[index];
                const charWidth: u4 = if (cell.trailFlag == TrailFlag.WIDE_START) 2 else 1;

                if (x + charWidth > self.width) break; //Wide characters at the end of a line must go onto a newline

                try screenLine.characters.append(gpa, cell);
                x += charWidth;
                index += 1;
            }

            try self.screen.addToBack(screenLine, gpa); //Adding it to the bottom of the screen

            //Removing excess screen lines
            if (self.screen.size > self.height) {
                _ = try self.screen.removeFromFront(gpa);
            }

            if (index >= logical.items.len) break;
        }
    }

    /// Adds an empty line to the bottom of the screen and removes extra lines if we are over the scrollback buffer
    /// Does not move the screen contents
    fn addNewLine(self: *text_buffer, gpa: std.mem.Allocator) !void {
        const nline_ptr = try gpa.create(std.ArrayList(character_cell));
        nline_ptr.* = try std.ArrayList(character_cell).initCapacity(gpa, self.width);
        try self.scrollback.append(gpa, nline_ptr);
        try self.moveCursorY(1, gpa);
        self.cursorX = 0;
    }

    /// Helper function to see how many Terminal screen lines the logical line at the given index takes up
    /// @param index the index of the logical line whose size in terminal lines we want to know
    /// @return the number of lines this logical line takes up
    fn logicalToTerminal(self: *text_buffer, index: usize) u32 {
        return @max(1, (@as(u32, @intCast(self.scrollback.items[index].items.len + self.width-1))) / self.width);
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
