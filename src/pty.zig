const std = @import("std");
const imports = @import("imports.zig");
const termz_c = imports.termz_c;

const SHELL = "/bin/dash";
extern fn posix_openpt(flags: c_int) c_int;
extern fn grantpt(fd: c_int) c_int;
extern fn unlockpt(fd: c_int) c_int;
extern fn ptsname(fd: c_int) ?*c_char;

pub const PTY = struct {
    master: i32,
    slave: i32,

    pub fn init() PTY {
        return PTY{
            .master = -1,
            .slave = -1,
        };
    }

    pub fn set_term_size(self: *PTY, width: u16, height: u16, pixelW: u16, pixelH: u16) bool {
        const ws: termz_c.winsize = .{.ws_row = height, .ws_col = width, .ws_xpixel = pixelW, .ws_ypixel = pixelH};

        if(std.os.linux.ioctl(self.master, termz_c.TIOCSWINSZ, @intFromPtr(&ws)) == -1) {
            std.debug.print("error: ioctl(TIOCSWINSZ)", .{});
            return false;
        }

        return true;
    }

    pub fn pt_pair(self: *PTY) bool {
        var slave_name: [*:0]const u8 = undefined;
        self.master = posix_openpt(@intCast(termz_c.O_RDWR | termz_c.O_NOCTTY));
        if(self.master == -1) {
            std.debug.print("error: posix_openpt", .{});
            return false;
        }

        if(grantpt(self.master) == -1) {
            std.debug.print("error: grantpt", .{});
            return false;
        }

        if(unlockpt(self.master) == -1) {
            std.debug.print("error: unlockpt", .{});
            return false;
        }

        slave_name = @as([*:0]const u8, @ptrCast(ptsname(self.master) orelse return false));

        self.slave = termz_c.open(slave_name, termz_c.O_RDWR | termz_c.O_NOCTTY);
        if(self.slave == -1) {
            std.debug.print("error: open({s})", .{slave_name});
            return false;
        }

        var termios: termz_c.struct_termios = undefined;
        if(termz_c.tcgetattr(self.slave, &termios) != 0) {
            std.debug.print("tcgetattr failed\n", .{});
            return false;
        }

        // Disable canonical mode and enable echo if you want
        termios.c_lflag &= ~(@as(c_uint, termz_c.ICANON | termz_c.ECHO)); // raw input
        _ = termz_c.tcsetattr(self.slave, termz_c.TCSANOW, &termios);

        return true;
    }

    pub fn spawn(self: *PTY) bool {
        const p_id: i32 = termz_c.fork();

        if(p_id == 0) {
            _ = std.os.linux.close(self.master);
            _ = std.os.linux.setsid();
            _ = std.os.linux.ioctl(self.slave, termz_c.TIOCSCTTY, @as(c_int, 0));
            _ = std.os.linux.dup2(self.slave, 0);
            _ = std.os.linux.dup2(self.slave, 1);
            _ = std.os.linux.dup2(self.slave, 2);
            if (self.slave > 2) _ = std.os.linux.close(self.slave);

            const args = [_:null][*c]const u8{ "-" ++ SHELL, null };
            const env = [_:null][*c]const u8{ "TERM=dumb", "PATH=/usr/local/bin:/usr/bin:/bin", "HOME=/root", null };
            _ = std.os.linux.execve(SHELL, @ptrCast(&args), @ptrCast(&env));

            // If we get here execve failed
            const fail_msg = "execve failed\n";
            _ = std.os.linux.write(2, fail_msg, fail_msg.len);
            std.os.linux.exit(1);
        }
        else if(p_id > 0) {
            _ = std.os.linux.close(self.slave);
            return true;
        }

        std.debug.print("error: fork()", .{});
        return false;
    }
};
