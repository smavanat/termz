const std = @import("std");

/// Function to fetch a C library from github and compile it with CMake, linking it to the build at the end.
/// Tries to replicate the functionality of CMake's FetchContentDeclare
/// @param b the build system being used
/// @param exe the executable of the program
/// @param name the name of the library. Must match the name of the static/dynamic library file produced.
/// e.g., if using this to link glfw, the paramter for name would be "glfw3", since the library file produced is called libglfw3.a
/// @param git_url the url to clone the library from
/// @param tag the version of the library you want to clone
/// @param cmake_params any specific parameters to pass to CMake about building the library
pub fn fetchMakeAvailableCMake(b: *std.Build, exe: *std.Build.Step.Compile, name: []const u8, git_url: []const u8, tag: []const u8, cmake_params: []const []const u8) !void {
    const allocator = b.allocator;

    const dep_dir = try std.fs.path.join(allocator, &.{ "zig-cache", "deps", name }); //Where the library is cloned to

    const build_dir = try std.fs.path.join(allocator, &.{ "zig-cache", "build", name }); //Where the library is built

    //Concatenating the default and user arguments for building a CMake library
    var args = try std.ArrayList([]const u8).initCapacity(allocator, 10);
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{"cmake", "-S", dep_dir, "-B", build_dir, "-DCMAKE_BUILD_TYPE=Release"}); //Adding default arguments
    try args.appendSlice(allocator, cmake_params); //Adding any user arguments

    // Configure CMake
    const configure = b.addSystemCommand(args.items);

    // Clone dependency if it does not already exist
    std.fs.cwd().access(dep_dir, .{}) catch {
         const clone = b.addSystemCommand(&.{"git", "clone", "--depth", "1", "--branch", tag, git_url, dep_dir,});
         configure.step.dependOn(&clone.step);
    };

    // Build library
    const cmake_build = b.addSystemCommand(&.{"cmake", "--build", build_dir});
    cmake_build.step.dependOn(&configure.step);

    // Ensure Zig waits for build
    exe.step.dependOn(&cmake_build.step);

    //Searching possible directories where the output library could be:
    const dirs = [_][]const u8{
        build_dir,
        try std.fs.path.join(allocator, &.{build_dir, "src"}),
        try std.fs.path.join(allocator, &.{build_dir, "lib"})
    };

    // Link library
    for(dirs) |dir| {
        std.fs.cwd().access(dir, .{}) catch continue; //Ignore if the library does not generate this filepath
        exe.addLibraryPath(b.path(dir));
    }

    exe.linkSystemLibrary(name);
}

