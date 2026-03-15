const std = @import("std");
const fu = @import("fileUtils.zig");
const glad = @import("imports.zig").glad;

pub fn loadShader(fragment_path: []const u8, vertex_path: []const u8, allocator: std.mem.Allocator) !u32 {
    var frag_buf: []const u8 = undefined;
    var vert_buf: []const u8 = undefined;
    var result: i32 = undefined;

    //Read the vertex shader into the buffer:
    fu.readToEnd(vertex_path, &vert_buf, allocator) catch |err| {
        std.debug.print("ERROR::VERTEX_SHADER::FILE NOT SUCCESSFULLY READ", .{});
        return err;
    };
    defer allocator.free(vert_buf);

    //Read the fragment shader into the buffer:
    fu.readToEnd(fragment_path, &frag_buf, allocator) catch |err| {
        std.debug.print("ERROR::FRAGMENT_SHADER::FILE NOT SUCCESSFULLY READ", .{});
        return err;
    };
    defer allocator.free(frag_buf);

    var info_log: [512]u8 = undefined;

    const vertex: c_uint = glad.glCreateShader(glad.GL_VERTEX_SHADER);
    const vert_len :i32 = @intCast(vert_buf.len);
    glad.glShaderSource(vertex, 1, &@ptrCast(vert_buf.ptr), &vert_len);
    glad.glCompileShader(vertex);

    //Print compile errors if any:
    glad.glGetShaderiv(vertex, glad.GL_COMPILE_STATUS, &result);
    if(result == 0) {
        glad.glGetShaderInfoLog(vertex, 512, 0, @ptrCast(&info_log[0]));
        std.debug.print("ERROR::SHADER::VERTEX::COMPILATION_FAILED\n", .{});
        for(0..512) |i| {
            std.debug.print("{c}", .{info_log[i]});
        }
        std.debug.print("\n", .{});
    }

    //Create the fragment shader from the code in the glsl and compile it
    const fragment: c_uint = glad.glCreateShader(glad.GL_FRAGMENT_SHADER);
    const frag_len :i32 = @intCast(frag_buf.len);
    glad.glShaderSource(fragment, 1, &@ptrCast(frag_buf.ptr), &frag_len);
    glad.glCompileShader(fragment);

    //Print compile errors if any:
    glad.glGetShaderiv(fragment, glad.GL_COMPILE_STATUS, &result);
    if(result == 0) {
        glad.glGetShaderInfoLog(fragment, 512, 0, @ptrCast(&info_log[0]));
        std.debug.print("ERROR::SHADER::FRAGMENT::COMPILATION_FAILED\n", .{});
        for(0..512) |i| {
            std.debug.print("{c}", .{info_log[i]});
        }
        std.debug.print("\n", .{});
    }

    //Create the shader and attach the created vertex and fragment shader
    const s: c_uint = glad.glCreateProgram();
    glad.glAttachShader(s, vertex);
    glad.glAttachShader(s, fragment);
    glad.glLinkProgram(s);

    //Print errors if any:
    glad.glGetProgramiv(s, glad.GL_LINK_STATUS, &result);
    if(result == 0) {
        glad.glGetProgramInfoLog(s, 512, 0, @ptrCast(&info_log[0]));
        std.debug.print("ERROR::SHADER::VERTEX::COMPILATION_FAILED\n", .{});
        for(0..512) |i| {
            std.debug.print("{c}", .{info_log[i]});
        }
        std.debug.print("\n", .{});
    }

    //Cleanup
    glad.glDeleteShader(vertex);
    glad.glDeleteShader(fragment);

    return @intCast(s);
}

var currentProgram: u32 = 0;

pub fn use(shader: u32) void {
    if(currentProgram != shader) {
        glad.glUseProgram(@intCast(shader));
        currentProgram = shader;
    }
}
