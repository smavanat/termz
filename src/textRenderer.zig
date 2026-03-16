const std = @import("std");
const imports = @import("imports.zig");

const s = imports.termz_core.sh;
const mu = imports.termz_core.mu;

const glad = imports.termz_c_externals.glad;
const freetype = imports.termz_c_externals.freetype;
const cglm = imports.termz_c_externals.cglm;

const character = struct {
    textureID: u32,
    size: mu.ivec2,
    bearing: mu.ivec2,
    advance: u32
};

const render_vertex = struct {
    pos: mu.vec2,
    colour: mu.vec4,
    uv: mu.vec2,
    tex_index: f32
};

var characters: std.AutoArrayHashMap(u8, character) = undefined;

fn initialiseCharRendering(face: freetype.FT_Face, allocator: std.mem.Allocator) !void {
    //Initialising the character map
    characters = std.AutoArrayHashMap(u8, character).init(allocator);

    glad.glPixelStorei(glad.GL_UNPACK_ALIGNMENT, 1); //Disable byte-alignment restriction

    for(0..128) |c| {
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
    projection: cglm.mat4 align(32),

    pub fn init(fragment_path: []const u8, vertex_path: []const u8, allocator: std.mem.Allocator, face: freetype.FT_Face) !renderer {
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

        const shader = try s.loadShader(fragment_path, vertex_path, allocator);
        glad.glUseProgram(shader);
        const loc = glad.glGetUniformLocation(shader, "text");
        glad.glUniform1i(loc, 0);

        var r = renderer{.vao = vao, .vbo = vbo, .ebo = 0, .shader = shader, .projection = undefined};

        cglm.glm_ortho(0.0, 800.0, 600.0, 0.0, -1.0, 1.0, &r.projection);

        glad.glEnable(glad.GL_BLEND);
        glad.glBlendFunc(glad.GL_SRC_ALPHA, glad.GL_ONE_MINUS_SRC_ALPHA);

        try initialiseCharRendering(face, allocator);

        return r;
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

            //Render glyph textuer over quad
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
