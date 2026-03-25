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
        const ws: std.posix.winsize = .{.row = height, .col = width, .xpixel = pixelW, .ypixel = pixelH};

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
        // if(slave_name == null) {
        //     std.debug.print("error: ptsname", .{});
        //     return false;
        // }

        self.slave = termz_c.open(slave_name, termz_c.O_RDWR | termz_c.O_NOCTTY);
        if(self.slave == -1) {
            std.debug.print("error: open({s})", .{slave_name});
            return false;
        }

        return true;
    }

    pub fn spawn(self: *PTY) bool {
        var p_id: i32 = undefined;
        const env = [_:null][*c]const u8{"TERM=dumb", null};

        p_id = std.posix.fork() catch return false;

        if(p_id == 0) {
            std.posix.close(self.master);

            _ = std.posix.setsid() catch return false;
            if(std.os.linux.ioctl(self.slave, termz_c.TIOCSCTTY, 0) == -1) {
                std.debug.print("ioctl(TIOCSCTTY)", .{});
                return false;
            }

            _=std.os.linux.dup2(self.slave, 0);
            _=std.os.linux.dup2(self.slave, 1);
            _=std.os.linux.dup2(self.slave, 2);
            _=std.os.linux.close(self.slave);

const args = [_:null][*c]const u8{ "-" ++ SHELL, null };
            _=termz_c.execve(SHELL, @ptrCast(&args), @ptrCast(&env));
            return false;
        }
        else if(p_id > 0) {
            _=std.os.linux.close(self.slave);
            return true;
        }

        std.debug.print("error: fork()", .{});
        return false;
    }
};
