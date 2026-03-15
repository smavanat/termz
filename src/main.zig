const std = @import("std");
const termz = @import("termz");
const builtin = @import("builtin");
const tr = @import("textRenderer.zig");
const glfw = @import("imports.zig").glfw;
const glad = @import("imports.zig").glad;
const freetype = @import("imports.zig").freetype;
const cglm = @import("imports.zig").cglm;

var gw: ?*glfw.GLFWwindow = null;
var tRenderer: tr.renderer = undefined;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

fn framebufferSizeCallback(window: ?*glfw.GLFWwindow, width: i32, height: i32) callconv(.c) void {
    if(glad.glad_glViewport) |glViewport|{
        glViewport(0, 0, width, height);
        var proj: cglm.mat4 align(32) = undefined;
        cglm.glm_ortho(0.0, @floatFromInt(width), @floatFromInt(height), 0.0, -1.0, 1.0, &proj);
        tRenderer.projection = proj;
    }

    _ = window; //To prevent the stupid unused function parameter errors
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

    _ = freetype.FT_Set_Pixel_Sizes(face, 0, 48); //Setting the pixel font size we would like to get from the face

    tRenderer = tr.renderer.init("data/shaders/glyph.frag", "data/shaders/glyph.vert", gpa.allocator(), face) catch return false;

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

            tRenderer.renderText("This is sample text", 45.0, 45.0, 1.0, .{.x = 0.5, .y = 0.8, .z = 0.2, .w =1.0});
            tRenderer.renderText("(C) LearnOpenGL.com", 520.0, 540.0, 1.0, .{.x = 0.3, .y = 0.7, .z = 0.9, .w = 1.0});

            //check and call events and swap the buffers
            glfw.glfwSwapBuffers(gw);
            glfw.glfwPollEvents();
        }

        glfw.glfwTerminate();
        tRenderer.deinit();
        _ = gpa.deinit();
    }
}
