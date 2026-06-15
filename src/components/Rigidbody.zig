const math = @import("math");

velocity: math.f32.Vector3 = .zero,
gravity: f32 = -9.81,
mass: f32 = 1.0,
restitution: f32 = 0.5,
friction: f32 = 0.02,
