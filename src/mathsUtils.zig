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

pub const mat4 = [4][4]f32;

fn glm_mat4_zero(mat: *mat4) void {
    for(0..4) |i| {
        mat[i] = .{0, 0, 0, 0};
    }
}

/// @brief set up orthographic projection matrix
///        with a right-hand coordinate system and a
///        clip-space of [-1, 1].
///
/// @param[in]  left    viewport.left
/// @param[in]  right   viewport.right
/// @param[in]  bottom  viewport.bottom
/// @param[in]  top     viewport.top
/// @param[in]  nearZ   near clipping plane
/// @param[in]  farZ    far clipping plane
/// @param[out] dest    result matrix
pub fn ortho(left: f32, right: f32, bottom: f32, top: f32, nearZ: f32, farZ: f32, dest: *mat4) void {
  glm_mat4_zero(dest);

  const rl: f32 = 1.0 / (right  - left);
  const tb: f32 = 1.0 / (top    - bottom);
  const mfn: f32 =-1.0 / (farZ - nearZ);

  dest[0][0] = 2.0 * rl;
  dest[1][1] = 2.0 * tb;
  dest[2][2] = 2.0 * mfn;
  dest[3][0] =-(right  + left)    * rl;
  dest[3][1] =-(top    + bottom)  * tb;
  dest[3][2] = (farZ + nearZ) * mfn;
  dest[3][3] = 1.0;
}

