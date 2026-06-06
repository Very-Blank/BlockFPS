pub const Model = struct {
    type: Type = .cube,
    outline: bool = false, // I know, I know, this is just for debug ... and def wont be final ...

    pub const Type = enum(u8) {
        cube = 0,
        _,
    };
};
