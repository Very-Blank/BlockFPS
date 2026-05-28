pub const Collider = union(enum) {
    pub const Sphere = struct { radius: f32 };
    pub const Capsule = struct { radius: f32, length: f32 };
    pub const Box = @import("math").f32.Vector3;

    sphere: Sphere,
    capsule: Capsule,
    box: Box,
};
