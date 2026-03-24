const std = @import("std");
const imports = @import("imports.zig");

const s = imports.termz_core.sh;
const mu = imports.termz_core.mu;
const tb = imports.termz_core.tb;

const glad = imports.termz_c_externals.glad;
const freetype = imports.termz_c_externals.freetype;
const cglm = imports.termz_c_externals.cglm;

pub const atlas = struct {
    cols: u32,
    rows: u32,
    cell_w: u32,
    cell_h: u32,
    textureID: u32,
    uvs: []mu.vec4,

    pub fn deinit(self: *atlas, gpa: std.mem.Allocator) void {
        gpa.free(self.uvs);
        // gpa.free(self);
    }
};

fn initialiseCharRendering(face: freetype.FT_Face, allocator: std.mem.Allocator, at: *?*atlas) !void {
    //If the atlas isn't null, free the old memory
    if(at.* != null) {
        allocator.free(at.*.?.uvs[0..at.*.?.cols * at.*.?.rows]);
        allocator.destroy(at.*.?);
    }

    //Initialise the new atlas values
    at.* = try allocator.create(atlas);
    at.*.?.cols = 16;
    at.*.?.rows = 16;
    at.*.?.cell_w = @intCast(face.*.size.*.metrics.max_advance >> 6);
    const ascender: u32 = @intCast(face.*.size.*.metrics.ascender >> 6);
    const descender: u32 = @intCast(-(face.*.size.*.metrics.descender >> 6)); // descender is negative
    at.*.?.cell_h = ascender + descender;
    at.*.?.uvs = try allocator.alignedAlloc(mu.vec4, null, at.*.?.cols * at.*.?.rows);

    const atlas_w = at.*.?.cell_w * at.*.?.cols;
    const atlas_h = at.*.?.cell_h * at.*.?.rows;

    //Need to create the texture for the atlas
    glad.glGenTextures(1, &at.*.?.textureID);
    glad.glBindTexture(glad.GL_TEXTURE_2D, at.*.?.textureID);
    // glad.glTexImage2D(glad.GL_TEXTURE_2D, 0, glad.GL_RGBA8, @intCast(atlas_w), @intCast(atlas_h), 0, glad.GL_RGBA, glad.GL_UNSIGNED_BYTE, null); //Setting it to use rgba colours
    glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MIN_FILTER, glad.GL_NEAREST);
    glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MAG_FILTER, glad.GL_NEAREST);

    //Getting the pixel data
    var pixels = try allocator.alloc(u8, atlas_h * atlas_w);
    defer allocator.free(pixels);
    @memset(pixels, 0);

    const baseline :u32 = @intCast(face.*.size.*.metrics.ascender >> 6);
    glad.glPixelStorei(glad.GL_UNPACK_ALIGNMENT, 1); //Disable byte-alignment restriction

    //Iterate over all chars
    for(32..128) |c| {
        //Load character glyph
        if(freetype.FT_Load_Char(face, c, freetype.FT_LOAD_RENDER) != 0) {
            std.debug.print("ERROR::FREETYPE: Failed to load glyph {}\n", .{c});
            continue;
        }

        const col = (c - 32) % at.*.?.cols;
        const row = (c - 32) / at.*.?.cols;

        //Top left of this cell in the atlas
        const ox = col * at.*.?.cell_w;
        const oy = row * at.*.?.cell_h;

        //Offset the glyph within the cell using bearing so it sits on the baseline
        const glyph_x = ox + @as(u32, @intCast(face.*.glyph.*.bitmap_left));

        // const glyph_x: u32 = @intCast(@as(i32, @intCast(ox)) - face.*.glyph.*.bitmap_top);
        // const glyph_y = oy + baseline - @as(u32, @intCast(face.*.glyph.*.bitmap_top));
        const glyph_y: u32 = @intCast(@as(i32, @intCast(oy)) + @as(i32, @intCast(baseline)) - face.*.glyph.*.bitmap_top);

        const bmp = face.*.glyph.*.bitmap;
        for(0..bmp.rows) |y| {
            for(0..bmp.width) |x| {
                pixels[(glyph_y + y) * atlas_w + (glyph_x + x)] = bmp.buffer[y * bmp.width + x];
            }
        }

        at.*.?.uvs[c-32] = .{
            .x = @as(f32, @floatFromInt(ox))                 / @as(f32, @floatFromInt(atlas_w)),
            .y = @as(f32, @floatFromInt(oy))                 / @as(f32, @floatFromInt(atlas_h)),
            .z = @as(f32, @floatFromInt(ox + at.*.?.cell_w)) / @as(f32, @floatFromInt(atlas_w)),
            .w = @as(f32, @floatFromInt(oy + at.*.?.cell_h)) / @as(f32, @floatFromInt(atlas_h))
        };
    }

    glad.glTexImage2D(glad.GL_TEXTURE_2D, 0, glad.GL_RED, @intCast(atlas_w), @intCast(atlas_h), 0, glad.GL_RED, glad.GL_UNSIGNED_BYTE, pixels.ptr);
}

pub const renderer = struct {
    vao: u32,
    vbo: u32,
    ebo: u32,
    shader: u32,
    projection: cglm.mat4 align(32),

    pub fn init(allocator: std.mem.Allocator, face: freetype.FT_Face, at: *?*atlas) !renderer {
        //Generating the buffers
        var vao: c_uint = undefined;
        var vbo: c_uint = undefined;

        glad.glGenVertexArrays(1, &vao);
        glad.glGenBuffers(1, &vbo);
        glad.glBindVertexArray(vao);
        glad.glBindBuffer(glad.GL_ARRAY_BUFFER, vbo);
        glad.glBufferData(glad.GL_ARRAY_BUFFER, @sizeOf(f32) * 6 * 4, null, glad.GL_DYNAMIC_DRAW);
        glad.glEnableVertexAttribArray(0);
        glad.glVertexAttribPointer(0, 4, glad.GL_FLOAT, glad.GL_FALSE, 4 * @sizeOf(f32), null);
        glad.glBindBuffer(glad.GL_ARRAY_BUFFER, 0);
        glad.glBindVertexArray(0);

        const fg_shader = try s.loadShader("data/shaders/glyph.frag", "data/shaders/glyph.vert", allocator);
        glad.glUseProgram(fg_shader);
        const loc = glad.glGetUniformLocation(fg_shader, "text");
        glad.glUniform1i(loc, 0);

        var r = renderer{.vao = vao, .vbo = vbo, .ebo = 0, .shader = fg_shader, .projection = undefined};

        cglm.glm_ortho(0.0, 800.0, 600.0, 0.0, -1.0, 1.0, &r.projection);

        glad.glEnable(glad.GL_BLEND);
        glad.glBlendFunc(glad.GL_SRC_ALPHA, glad.GL_ONE_MINUS_SRC_ALPHA);

        try initialiseCharRendering(face, allocator, at);

        return r;
    }

    pub fn renderTextBuffer(self: *renderer, tex_buf: *tb.text_buffer, at: *atlas) void {
        s.use(self.shader);
        glad.glActiveTexture(glad.GL_TEXTURE0);
        glad.glBindTexture(glad.GL_TEXTURE_2D, at.textureID);  // not self.screen_tex
        glad.glBindVertexArray(self.vao);
        glad.glBindBuffer(glad.GL_ARRAY_BUFFER, self.vbo);
        const proj_loc = glad.glGetUniformLocation(self.shader, "projection");
        glad.glUniformMatrix4fv(proj_loc, 1, glad.GL_FALSE, @ptrCast(&self.projection));

        var x_cursor_pos: u16 = 0;
        var y_cursor_pos: u16 = 0;

        for(0..tex_buf.screen.size+1) |i| {
            if(i >= tex_buf.height) continue;
            x_cursor_pos = 0;
            const line = tex_buf.screen.get(@intCast(i));
            const line_len = if(i < tex_buf.screen.size) line.characters.items.len else 0;
            for(0..line_len+1) |j| {
                // std.debug.print("Screen Cursor pos: ({}, {})", .{tex_buf.getScreenCursorX(), tex_buf.getScreenCursorY()});

                if(j >= tex_buf.width) continue;
                const ch :u8 = if(j < line_len) line.characters.items[j].char else 32;

                const xpos: f32 = @as(f32, @floatFromInt(x_cursor_pos * at.cell_w));
                const ypos: f32 = @as(f32, @floatFromInt(y_cursor_pos * at.cell_h));
                const w: f32 = @as(f32, @floatFromInt(at.cell_w));
                const h: f32 = @as(f32, @floatFromInt(at.cell_h));

                const is_cursor = (i == tex_buf.getScreenCursorY() and j == tex_buf.getScreenCursorX());
                const fg = if(is_cursor) tex_buf.backgroundColour else tex_buf.foregroundColour;
                const bg = if(is_cursor) tex_buf.foregroundColour else tex_buf.backgroundColour;

                glad.glUniform4f(glad.glGetUniformLocation(@intCast(self.shader), "bgColor"), bg.x, bg.y, bg.z, bg.w);
                glad.glUniform4f(glad.glGetUniformLocation(@intCast(self.shader), "textColor"), fg.x, fg.y, fg.z, fg.w);

                //Update vbo for each character
                const uv = at.uvs[ch-32];
                const vertices = [6][4]f32{
                    .{xpos,     ypos,     uv.x, uv.y},
                    .{xpos,     ypos + h, uv.x, uv.w},
                    .{xpos + w, ypos + h, uv.z, uv.w},
                    .{xpos,     ypos,     uv.x, uv.y},
                    .{xpos + w, ypos + h, uv.z, uv.w},
                    .{xpos + w, ypos,     uv.z, uv.y},
                };

                glad.glBufferSubData(glad.GL_ARRAY_BUFFER, 0, @sizeOf(@TypeOf(vertices)), @ptrCast(&vertices));
                glad.glDrawArrays(glad.GL_TRIANGLES, 0, 6);
                x_cursor_pos += 1;
            }
            y_cursor_pos += 1;
        }
    }

    pub fn deinit(self: renderer) void {
        _ = self;
    }
};
