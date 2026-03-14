const std = @import("std");
const termz = @import("termz");
const builtin = @import("builtin");
const glfw = @cImport({@cInclude("glfw/glfw3.h");});
const glad = @cImport({@cInclude("glad/glad.h");});
const freetype = @cImport({@cInclude("freetype/ft2build.h"); @cInclude("freetype/freetype.h");});

const ivec2 = struct {
    x: i32,
    y: i32
};

const character = struct {
    textureID: u32,
    size: ivec2,
    bearing: ivec2,
    advance: u32
};

var gw: ?*glfw.GLFWwindow = null;
var characters: std.AutoArrayHashMap(u8, character) = undefined;

fn framebufferSizeCallback(window: ?*glfw.GLFWwindow, width: i32, height: i32) callconv(.c) void {
    if(glad.glad_glViewport) |glViewport|{
        glViewport(0, 0, width, height);
    }

    _ = window; //To prevent the stupid unused function parameter errors
}

fn initialiseCharRendering(face: freetype.FT_Face) !void {
    //Initialising the character map
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    characters = std.AutoArrayHashMap(u8, character).init(gpa.allocator());

    glad.glPixelStorei(glad.GL_UNPACK_ALIGNMENT, 1); //Disable byte-alignment restriction

    for(0..128) |c| {
        //Load character glyph
        if(freetype.FT_Load_Char(face, c, freetype.FT_LOAD_RENDER) == 0) {
            std.debug.print("ERROR::FREETYPE: Failed to load glyph {}", .{c});
            continue;
        }

        //Generate texture
        var texture: u32 = undefined;
        glad.glGenTextures(1, &texture);
        glad.glBindTexture(glad.GL_TEXTURE_2D, texture);
        glad.glTexImage2D(glad.GL_TEXTURE_2D, 0, glad.GL_RED, @intCast(face.*.glyph.*.bitmap.width),
                          @intCast(face.*.glyph.*.bitmap.rows), 0, glad.GL_RED, glad.GL_UNSIGNED_BYTE, face.*.glyph.*.bitmap.buffer);

        //Set texture options
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_S, glad.GL_CLAMP_TO_EDGE);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_T, glad.GL_CLAMP_TO_EDGE);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MIN_FILTER, glad.GL_LINEAR);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MAG_FILTER, glad.GL_LINEAR);

        //Store character for later use
        const ch: character = .{.textureID = texture, .size = .{.x = @intCast(face.*.glyph.*.bitmap.width), .y = @intCast(face.*.glyph.*.bitmap.rows)},
                        .bearing = .{.x = face.*.glyph.*.bitmap_left, .y = face.*.glyph.*.bitmap_top}, .advance = @intCast(face.*.glyph.*.advance.x)};
        _ = try characters.fetchPut(@intCast(c), ch);
    }
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
    if(freetype.FT_New_Face(ft, "../data/fonts/NotoSansCarian-Regular.ttf", 0, &face) != 0) {
        std.debug.print("ERROR::FREETYPE: Failed to load font\n", .{});
        return false;
    }

    _ = freetype.FT_Set_Pixel_Sizes(face, 0, 48); //Setting the pixel font size we would like to get from the face

    initialiseCharRendering(face) catch return false;

    //Freeing freetype's resources
    _ = freetype.FT_Done_Face(face);
    _ = freetype.FT_Done_FreeType(ft);

    return true;
}

pub fn main() !void {
    if(init(&gw)) {
        std.debug.print("Initialised\n", .{});
        while(glfw.glfwWindowShouldClose(gw) == 0) {
            //Setting the background colour to be black
            glad.glClearColor(0.0, 0.0, 0.0, 0.0);
            glad.glClear(glad.GL_COLOR_BUFFER_BIT);

            //check and call events and swap the buffers
            glfw.glfwSwapBuffers(gw);
            glfw.glfwPollEvents();
        }

        glfw.glfwTerminate();
    }
    characters.deinit();
}
