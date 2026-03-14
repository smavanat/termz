const std = @import("std");
const termz = @import("termz");
const glfw = @cImport({@cInclude("glfw/glfw3.h");});
const glad = @cImport({@cInclude("glad/glad.h");});

var gw: ?*glfw.GLFWwindow = null;

fn framebufferSizeCallback(window: ?*glfw.GLFWwindow, width: i32, height: i32) callconv(.c) void {
    if(glad.glad_glViewport) |glViewport|{
        glViewport(0, 0, width, height);
    }

    _ = window; //To prevent the stupid unused function parameter errors
}

fn init(window: *?*glfw.GLFWwindow) bool {
    //Initialising GLFW
    _ = glfw.glfwInit();
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);
    // #ifdef __APPLE__
    // glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE); //For MacOS
    // #endif

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

    return true;
}

pub fn main() !void {
    if(init(&gw)) {
        std.debug.print("Initialised\n", .{});
        while(glfw.glfwWindowShouldClose(gw) == 0) {
            glad.glClearColor(0.0, 0.0, 0.0, 0.0);
            glad.glClear(glad.GL_COLOR_BUFFER_BIT);

            //check and call events and swap the buffers
            glfw.glfwSwapBuffers(gw);
            glfw.glfwPollEvents();
        }

        glfw.glfwTerminate();
    }
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try termz.bufferedPrint();
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
