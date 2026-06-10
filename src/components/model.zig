pub const Model = struct {
    type: Type = .cube,

    // I know, I know, this is just for debug ... and def wont be final ...
    outline: struct {
        enabled: bool = false,
        color: struct { r: f32 = 1, b: f32 = 1, g: f32 = 1, a: f32 = 1 } = .{},
    } = .{},

    pub const Type = enum(u8) {
        cube = 0,
        _,
    };
};
