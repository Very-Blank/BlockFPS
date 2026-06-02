const math = @import("math");

const Self = @This();

offset: f32,

rotation: struct {
    pitch: f32,
    yaw: f32,
},

projection: struct {
    mat: math.f32.Mat4,
    fov: f32,
    near: f32,
    far: f32,
},

pub inline fn updateView(self: *Self, aspect: f32) void {
    self.projection.mat = .initPerspective(self.projection.fov, aspect, self.projection.near, self.projection.far);
}
