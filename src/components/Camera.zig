const math = @import("math");

const Self = @This();

view: math.f32.Mat4,

rotation: struct {
    pitch: f32,
    yaw: f32,
},

projection: struct {
    fov: f32,
    near: f32,
    far: f32,
},

pub inline fn updateView(self: *Self, aspect: f32) void {
    self.view = .initPerspective(self.projection.fov, aspect, self.projection.near, self.projection.far);
}
