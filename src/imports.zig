/// This file is the central point for imports in this project
/// It defines two structs, one for handling internal imports (other files in this project)
/// the other for handling all of the external libraries we are using

const ltr = @import("textRenderer.zig");
const ltb = @import("textBuffer.zig");
const lca = @import("CircularArray.zig");
const lsh = @import("shader.zig");
const lfu = @import("fileUtils.zig");
const lmu = @import("mathsUtils.zig");

pub const termz_core = struct {
    /// Import for textRenderer.zig
    pub const tr = ltr;
    /// Import for textBuffer.zig
    pub const tb = ltb;
    /// Import for CircularArray.zig
    pub const ca = lca;
    /// Import for shader.zig
    pub const sh = lsh;
    /// Import for fileUtils.zig
    pub const fu = lfu;
    /// Import for mathsUtils.zig
    pub const mu = lmu;
};

const lglad = @cImport({@cInclude("glad/glad.h");});
const lcglm = @cImport({@cInclude("cglm/cglm.h");});
const lfreetype = @cImport({@cInclude("freetype/ft2build.h"); @cInclude("freetype/freetype.h");});
const lglfw = @cImport({@cInclude("glfw/glfw3.h");});

pub const termz_c_externals = struct {
    /// Import for glad
    pub const glad = lglad;
    /// Import for cglm
    pub const cglm = lcglm;
    /// Import for freetype
    pub const freetype = lfreetype;
    /// Import for glfw
    pub const glfw = lglfw;
};
