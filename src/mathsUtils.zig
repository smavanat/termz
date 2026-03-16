const std = @import("std");

pub const ivec2 = struct {
    x: i32,
    y: i32
};

pub const vec2 = struct {
    x: f32,
    y: f32
};

pub const vec4 = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn init(x: f32, y: f32, z: f32, w: f32) vec4 {
        return vec4{.x = x, .y = y, .z = z, .w = w};
    }
};
