const std = @import("std");
const termz = @import("termz");
const builtin = @import("builtin");
const imports = @import("imports.zig");

const tr = imports.termz_core.tr;
const tb = imports.termz_core.tb;
const in = imports.termz_core.in;
const pty = imports.termz_core.pty;

const glfw = imports.termz_c_externals.glfw;
const glad = imports.termz_c_externals.glad;
const freetype = imports.termz_c_externals.freetype;
const cglm = imports.termz_c_externals.cglm;

var gw: ?*glfw.GLFWwindow = null;
var tRenderer: tr.renderer = undefined;
var text_buf: *tb.text_buffer = undefined;
var atls: ?*tr.atlas = null;
var pts: *pty.PTY = undefined;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

//TODO: TALK TO PSEUDOTERMINAL

//BUG: WHEN DELETING A CHARACTER FROM A LINE THAT WRAPS OFF OF THE BOTTOM OF THE SCREEN, FRESH CHARACTERS WILL NOT BE PULLED IN

fn framebufferSizeCallback(window: ?*glfw.GLFWwindow, width: i32, height: i32) callconv(.c) void {
    if(glad.glad_glViewport) |glViewport|{
        glViewport(0, 0, width, height);
        var proj: cglm.mat4 align(32) = undefined;
        cglm.glm_ortho(0.0, @floatFromInt(width), @floatFromInt(height), 0.0, -1.0, 1.0, &proj);
        tRenderer.projection = proj;
    }

    _ = window; //To prevent the stupid unused function parameter errors
}

fn charCallback(window: ?*glfw.GLFWwindow, codepoint: u32) callconv(.c) void {
    in.onCharInput(text_buf, codepoint, gpa.allocator());

    _ = window;
}

fn keyCallback(window: ?*glfw.GLFWwindow, key: i32, scancode: i32, action: i32, mods: i32) callconv(.c) void {
    if(action == glfw.GLFW_PRESS or action == glfw.GLFW_REPEAT)
        in.keyCallback(text_buf, key, gpa.allocator());

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
    window.* = glfw.glfwCreateWindow(800, 600, "termz", null, null);
    if(window.* == null) {
        std.debug.print("Failed to create a GLFW window", .{});
        termz.bufferedPrint() catch return false;
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

    //Loading the font as a FreeType 'face'
    var face: freetype.FT_Face = undefined;
    if(freetype.FT_New_Face(ft, "data/fonts/DejaVuSansMono.ttf", 0, @ptrCast(&face)) != 0) {
        std.debug.print("ERROR::FREETYPE: Failed to load font\n", .{});
        return false;
    }

    _ = freetype.FT_Set_Pixel_Sizes(face, 0, 24); //Setting the pixel font size we would like to get from the face

    //Initialising the text renderer
    tRenderer = tr.renderer.init(gpa.allocator(), face, &atls) catch return false;

    //Setting up the pseudoterminal
    pts = gpa.allocator().create(pty.PTY) catch return false;
    pts.* = pty.PTY.init();
    if(!pts.pt_pair()) return false;
    if(!pts.set_term_size(@intCast(800/atls.?.*.cell_w), @intCast(600/atls.?.*.cell_h), 800, 600)) return false;
    if(!pts.spawn()) return false;

    //Setting up the text buffer
    text_buf = gpa.allocator().create(tb.text_buffer) catch return false;
    text_buf.* = tb.text_buffer.init(800/atls.?.*.cell_w, 600/atls.?.*.cell_h, gpa.allocator()) catch return false;

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
        while(glfw.glfwWindowShouldClose(gw) == 0) {
            //Setting the background colour to be black
            glad.glClearColor(1.0, 1.0, 1.0, 1.0);
            glad.glClear(glad.GL_COLOR_BUFFER_BIT);

            tRenderer.renderTextBuffer(text_buf, atls.?);

            //check and call events and swap the buffers
            glfw.glfwSwapBuffers(gw);
            glfw.glfwWaitEvents(); //Wait until something actually happens
        }

        glfw.glfwTerminate();
        tRenderer.deinit();

        text_buf.deinit(gpa.allocator());
        gpa.allocator().destroy(text_buf);

        atls.?.deinit(gpa.allocator());
        gpa.allocator().destroy(atls.?);

        gpa.allocator().destroy(pts);

        _ = gpa.deinit();
    }
}
