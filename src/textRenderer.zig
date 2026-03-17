const std = @import("std");
const imports = @import("imports.zig");

const s = imports.termz_core.sh;
const mu = imports.termz_core.mu;
const tb = imports.termz_core.tb;

const glad = imports.termz_c_externals.glad;
const freetype = imports.termz_c_externals.freetype;
const cglm = imports.termz_c_externals.cglm;

//TODO: NEED TO ACTUALLY MAKE THE ATLAS TEXTURE AND RENDER FROM IT IN THE TEXT RENDERER

const character = struct {
    textureID: u32,
    size: mu.ivec2,
    bearing: mu.ivec2,
    advance: u32
};

pub const atlas = struct {
    cols: u32,
    rows: u32,
    cell_w: u32,
    cell_h: u32,
    textureID: u32, 
    uvs: []mu.vec4,
};

var characters: std.AutoArrayHashMap(u8, character) = undefined;

fn initialiseCharRendering_new(face: freetype.FT_Face, allocator: std.mem.Allocator, at: *?*atlas) !void {
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
    at.*.?.cell_h = @intCast(face.*.size.*.metrics.height >> 6);
    at.*.?.uvs = try allocator.alignedAlloc(mu.vec4, null, at.*.?.cols * at.*.?.rows);

    const atlas_w = at.*.?.cell_w * at.*.?.cols;
    const atlas_h = at.*.?.cell_h * at.*.?.rows;

    //Need to create the texture for the atlas
    glad.glGenTextures(1, &at.*.?.textureID);
    glad.glBindTexture(glad.GL_TEXTURE_2D, at.*.?.textureID);
    glad.glTexImage2D(glad.GL_TEXTURE_2D, 0, glad.GL_RGBA8, @intCast(atlas_w), @intCast(atlas_h), 0, glad.GL_RGBA, glad.GL_UNSIGNED_BYTE, null); //Setting it to use rgba colours
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
            .x = @as(f32, @floatFromInt(ox))             / @as(f32, @floatFromInt(atlas_w)),
            .y = @as(f32, @floatFromInt(oy))             / @as(f32, @floatFromInt(atlas_h)),
            .z = @as(f32, @floatFromInt(ox + at.*.?.cell_w)) / @as(f32, @floatFromInt(atlas_w)),
            .w = @as(f32, @floatFromInt(oy + at.*.?.cell_h)) / @as(f32, @floatFromInt(atlas_h))
        };
    }

    glad.glTexImage2D(glad.GL_TEXTURE_2D, 0, glad.GL_RED, @intCast(atlas_w), @intCast(atlas_h), 0, glad.GL_RED, glad.GL_UNSIGNED_BYTE, pixels.ptr);
}

fn initialiseCharRendering(face: freetype.FT_Face, allocator: std.mem.Allocator) !void {
    //Initialising the character map
    characters = std.AutoArrayHashMap(u8, character).init(allocator);

    glad.glPixelStorei(glad.GL_UNPACK_ALIGNMENT, 1); //Disable byte-alignment restriction

    for(32..128) |c| {
        //Load character glyph
        if(freetype.FT_Load_Char(face, c, freetype.FT_LOAD_RENDER) != 0) {
            std.debug.print("ERROR::FREETYPE: Failed to load glyph {}\n", .{c});
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

pub const renderer = struct {
    vao: u32,
    vbo: u32,
    ebo: u32,
    shader: u32,
    screen_tex: u32,
    projection: cglm.mat4 align(32),

    pub fn init(fragment_path: []const u8, vertex_path: []const u8, allocator: std.mem.Allocator, face: freetype.FT_Face, at: *?*atlas) !renderer {
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

        //Generating the texture
        var tex: c_uint = undefined;
        glad.glGenTextures(1, &tex);
        glad.glBindTexture(glad.GL_TEXTURE_2D, tex);
        glad.glTexImage2D(glad.GL_TEXTURE_2D, 0, glad.GL_RGBA8, 800, 600, 0, glad.GL_RGBA, glad.GL_UNSIGNED_BYTE, null); //Setting it to use rgba colours
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MIN_FILTER, glad.GL_NEAREST);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MAG_FILTER, glad.GL_NEAREST);

        const shader = try s.loadShader(fragment_path, vertex_path, allocator);
        glad.glUseProgram(shader);
        const loc = glad.glGetUniformLocation(shader, "text");
        glad.glUniform1i(loc, 0);

        var r = renderer{.vao = vao, .vbo = vbo, .ebo = 0, .shader = shader, .screen_tex = tex, .projection = undefined};

        cglm.glm_ortho(0.0, 800.0, 600.0, 0.0, -1.0, 1.0, &r.projection);

        glad.glEnable(glad.GL_BLEND);
        glad.glBlendFunc(glad.GL_SRC_ALPHA, glad.GL_ONE_MINUS_SRC_ALPHA);

        try initialiseCharRendering_new(face, allocator, at);

        return r;
    }

    pub fn renderTextBuffer(self: *renderer, tex_buf: *tb.text_buffer, at: *atlas) void {
        s.use(self.shader);
        glad.glUniform3f(glad.glGetUniformLocation(@intCast(self.shader), "textColor"), tex_buf.foregroundColour.x, tex_buf.foregroundColour.y, tex_buf.foregroundColour.z);
        glad.glActiveTexture(glad.GL_TEXTURE0);
        glad.glBindTexture(glad.GL_TEXTURE_2D, self.screen_tex); //Binding our texture
        glad.glBindVertexArray(self.vao);
        const proj_loc = glad.glGetUniformLocation(self.shader, "projection");
        glad.glUniformMatrix4fv(proj_loc, 1, glad.GL_FALSE, @ptrCast(&self.projection));

        var x_cursor_pos: u16 = 0;
        var y_cursor_pos: u16 = 0;

        for(0..tex_buf.screen.size) |i| {
            x_cursor_pos = 0;
            const line = tex_buf.screen.get(@intCast(i));
            for(0..line.characters.items.len) |j| {
                const ch :u8 = line.characters.items[j].char;

                const xpos: f32 = @as(f32, @floatFromInt(x_cursor_pos * at.cell_w));
                const ypos: f32 = @as(f32, @floatFromInt(y_cursor_pos * at.cell_h));
                const w: f32 = @as(f32, @floatFromInt(at.cell_w));
                const h: f32 = @as(f32, @floatFromInt(at.cell_h));

                //Update vbo for each character
                const uv = at.uvs[ch-32];
                const vertices = [6][4]f32{
                    .{xpos,     ypos,     uv.x, uv.y},
                    .{xpos,     ypos - h, uv.x, uv.w},
                    .{xpos + w, ypos - h, uv.z, uv.w},
                    .{xpos,     ypos,     uv.x, uv.w},
                    .{xpos + w, ypos - h, uv.z, uv.w},
                    .{xpos + w, ypos,     uv.z, uv.y},
                };

                glad.glBufferSubData(glad.GL_ARRAY_BUFFER, 0, @sizeOf(@TypeOf(vertices)), @ptrCast(&vertices));
                glad.glDrawArrays(glad.GL_TRIANGLES, 0, 6);
                x_cursor_pos += 1;
            }
            y_cursor_pos += 1;
        }
    }

    pub fn renderText(self: *renderer, text: []const u8, x: f32, y: f32, scale: f32, colour: mu.vec4) void {
        s.use(self.shader);
        glad.glUniform3f(glad.glGetUniformLocation(@intCast(self.shader), "textColor"), colour.x, colour.y, colour.z);
        glad.glActiveTexture(glad.GL_TEXTURE0);
        glad.glBindVertexArray(self.vao);
        const proj_loc = glad.glGetUniformLocation(self.shader, "projection");
        glad.glUniformMatrix4fv(proj_loc, 1, glad.GL_FALSE, @ptrCast(&self.projection));

        var x_cursor_pos = x;

        for(text) |char| {
            const ch: character = characters.get(char).?;

            const xpos: f32 = x_cursor_pos + @as(f32, @floatFromInt(ch.bearing.x)) * scale;
            const ypos : f32 = y + @as(f32, @floatFromInt((ch.size.y - ch.bearing.y))) * scale;

            const w: f32 = @as(f32, @floatFromInt(ch.size.x)) * scale;
            const h: f32 = @as(f32, @floatFromInt(ch.size.y)) * scale;

            //Update vbo for each character
            const vertices = [6][4]f32{
                [_]f32{xpos,     ypos,     0.0, 1.0},  // top-left
                [_]f32{xpos,     ypos - h, 0.0, 0.0},  // bottom-left
                [_]f32{xpos + w, ypos - h, 1.0, 0.0},  // bottom-right
                [_]f32{xpos,     ypos,     0.0, 1.0},  // top-left
                [_]f32{xpos + w, ypos - h, 1.0, 0.0},  // bottom-right
                [_]f32{xpos + w, ypos,     1.0, 1.0},  // top-right
            };

            //Render glyph texture over quad
            glad.glBindTexture(glad.GL_TEXTURE_2D, @intCast(ch.textureID));
            //Update content of VBO memory
            glad.glBindBuffer(glad.GL_ARRAY_BUFFER, self.vbo);
            glad.glBufferSubData(glad.GL_ARRAY_BUFFER, 0, @sizeOf(@TypeOf(vertices)), @ptrCast( &vertices));
            glad.glBindBuffer(glad.GL_ARRAY_BUFFER, 0);
            //Render quad
            glad.glDrawArrays(glad.GL_TRIANGLES, 0, 6);
            //Advance cursors for next glyph (advance is number of 1/64 pixels)
            x_cursor_pos += @as(f32, @floatFromInt(ch.advance >> 6)) * scale; //bitshift by 6 to get value in pixels
        }
    }

    pub fn deinit(self: renderer) void {
        _ = self;
        characters.deinit();
    }
};
