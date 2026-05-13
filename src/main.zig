const std = @import("std");
const builtin = @import("builtin");
const imports = @import("imports.zig");

const tr = imports.termz_core.tr;
const tb = imports.termz_core.tb;
const in = imports.termz_core.in;
const pty = imports.termz_core.pty;
const m = imports.termz_core.mu;
const ap = imports.termz_core.ap;

const glfw = imports.termz_c_externals.glfw;
const glad = imports.termz_c_externals.glad;
const freetype = imports.termz_c_externals.freetype;

const termz_c = imports.termz_c;

const screen_width: u32 = 800;
const screen_height: u32 = 600;

var gw: ?*glfw.GLFWwindow = null;
var tRenderer: tr.renderer = undefined;
var text_buf: *tb.text_buffer = undefined;
var atls: ?*tr.atlas = null;
var pts: *pty.PTY = undefined;
var ansi_p : *ap.ansi_parser = undefined;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

fn framebufferSizeCallback(window: ?*glfw.GLFWwindow, width: i32, height: i32) callconv(.c) void {
    if(glad.glad_glViewport) |glViewport|{
        glViewport(0, 0, width, height);
        var proj: m.mat4 = undefined;
        m.ortho(0.0, @max(20.0, @as(f32, @floatFromInt(width))), @max(10, @as(f32, @floatFromInt(height))), 0.0, -1.0, 1.0, &proj);
        tRenderer.projection = proj;

        const cell_width: u32 = @max(1, @as(u32, @intCast(width))/atls.?.*.cell_w);
        const cell_height: u32 = @max(1, @as(u32, @intCast(height))/atls.?.*.cell_h);
        text_buf.setWidth(cell_width, gpa.allocator()) catch return;
        text_buf.setHeight(cell_height, gpa.allocator()) catch return;

        _=pts.set_term_size(@intCast(cell_width), @intCast(cell_height), @intCast(width), @intCast(height));
    }

    _ = window; //To prevent the stupid unused function parameter errors
}

fn charCallback(window: ?*glfw.GLFWwindow, codepoint: u32) callconv(.c) void {
    in.onCharInput(text_buf, codepoint, gpa.allocator());

    _ = window;
}

fn keyCallback(window: ?*glfw.GLFWwindow, key: i32, scancode: i32, action: i32, mods: i32) callconv(.c) void {
    if(action == glfw.GLFW_PRESS or action == glfw.GLFW_REPEAT)
        in.keyCallback(text_buf, pts, key, gpa.allocator());

    _ = window;
    _ = scancode;
    _ = mods;
}

fn init(window: *?*glfw.GLFWwindow) bool {
    //Initialising GLFW
    _ = glfw.glfwInit();
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);
    comptime if(builtin.target.os.tag == .macos) { //For MacOS
        glfw.glfwWindowHint(glfw.GLFW_OPENGL_FORWARD_COMPAT, glfw.GL_TRUE);
    };

    //Initialising the window
    window.* = glfw.glfwCreateWindow(screen_width, screen_height, "termz", null, null);
    if(window.* == null) {
        std.debug.print("Failed to create a GLFW window", .{});
        glfw.glfwTerminate();
        return false;
    }
    glfw.glfwMakeContextCurrent(window.*.?);
    _ = glfw.glfwSetFramebufferSizeCallback(window.*.?, framebufferSizeCallback);
    _ = glfw.glfwSetCharCallback(window.*.?, charCallback);
    _ = glfw.glfwSetKeyCallback(window.*.?, keyCallback);

    //Loading GLAD
    const loader: glad.GLADloadproc = @ptrCast(&glfw.glfwGetProcAddress);

    if(glad.gladLoadGLLoader(loader) == 0) {
        std.debug.print("Failed to initialise GLAD", .{});
        return false;
    }

    //Initialising freetype
    var ft: freetype.FT_Library = undefined;
    if(freetype.FT_Init_FreeType(&ft) != 0) {
        std.debug.print("ERROR::FREETYPE: Could not init FreeType Library\n", .{});
        return false;
    }

    //Getting the exe path
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = std.fs.selfExeDirPath(&buf) catch return false;

    //Getting the data folder relative to the exe path
    const font_path = std.fs.path.joinZ(gpa.allocator(), &.{
        exe_path, "../data/fonts/DejaVuSansMono.ttf"
    }) catch return false;
    defer gpa.allocator().free(font_path);

    //Loading the font as a FreeType 'face'
    var face: freetype.FT_Face = undefined;
    if(freetype.FT_New_Face(ft, font_path, 0, @ptrCast(&face)) != 0) {
        std.debug.print("ERROR::FREETYPE: Failed to load font\n", .{});
        return false;
    }

    _ = freetype.FT_Set_Pixel_Sizes(face, 0, 16); //Setting the pixel font size we would like to get from the face

    //Initialising the text renderer
    tRenderer = tr.renderer.init(gpa.allocator(), face, &atls) catch return false;

    //Setting up the pseudoterminal
    pts = gpa.allocator().create(pty.PTY) catch return false;
    pts.* = pty.PTY.init();
    if(!pts.pt_pair()) return false;
    if(!pts.set_term_size(@intCast(screen_width/atls.?.*.cell_w), @intCast(screen_height/atls.?.*.cell_h), screen_width, 600)) return false;
    if(!pts.spawn()) return false;

    //Setting up the text buffer
    text_buf = gpa.allocator().create(tb.text_buffer) catch return false;
    text_buf.* = tb.text_buffer.init(screen_width/atls.?.*.cell_w, screen_height/atls.?.*.cell_h, gpa.allocator()) catch return false;
    std.debug.print("Width: {}, Height: {}\n", .{text_buf.width, text_buf.height});

    //Loading the ansi parser:
    ansi_p = gpa.allocator().create(ap.ansi_parser) catch return false;
    ansi_p.* = ap.ansi_parser.init(text_buf);

    //Freeing freetype's resources
    _ = freetype.FT_Done_Face(face);
    _ = freetype.FT_Done_FreeType(ft);

    return true;
}

// Add this helper and call it after renderText:
fn checkGLError(label: []const u8) void {
    const err = glad.glGetError();
    if (err != glad.GL_NO_ERROR) {
        std.debug.print("GL Error at {s}: {}\n", .{label, err});
    }
}

pub fn main() !void {
    if(init(&gw)) {
        std.debug.print("Initialised\n", .{});

        _=try std.posix.fcntl(pts.master, termz_c.F_SETFL, termz_c.O_NONBLOCK);

        while(glfw.glfwWindowShouldClose(gw) == 0) {
            ansi_p.parse(pts, gpa.allocator()) catch break;

            //Setting the background colour to be black
            glad.glClearColor(@as(f32,@floatFromInt(text_buf.backgroundColour[0]))/256.0, @as(f32,@floatFromInt(text_buf.backgroundColour[1]))/256.0, @as(f32,@floatFromInt(text_buf.backgroundColour[2]))/256.0, 1.0);
            glad.glClear(glad.GL_COLOR_BUFFER_BIT);

            tRenderer.renderTextBuffer(text_buf, atls.?);

            //check and call events and swap the buffers
            glfw.glfwSwapBuffers(gw);
            // glfw.glfwWaitEvents(); //Wait until something actually happens
            glfw.glfwPollEvents();
        }

        glfw.glfwTerminate();
        tRenderer.deinit();

        text_buf.deinit(gpa.allocator());
        gpa.allocator().destroy(text_buf);

        atls.?.deinit(gpa.allocator());
        gpa.allocator().destroy(atls.?);

        gpa.allocator().destroy(pts);
        gpa.allocator().destroy(ansi_p);

        _ = gpa.deinit();
    }
}
