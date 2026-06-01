pub const Collider = struct {
    layer: Layer = .default,
    mask: Mask = .all,

    type: union(enum) {
        sphere: Sphere,
        capsule: Capsule,
        box: Box,
    },

    pub const T = u16;

    pub const Layer = enum(T) {
        default = 1,
        enemy = 1 << 2,
        player = 1 << 3,
    };

    pub const Mask = enum(T) {
        none = 0,
        all = ~@as(T, 0),
        _,

        pub inline fn contains(mask: Mask, layer: Layer) bool {
            return (@intFromEnum(mask) & @intFromEnum(layer)) == @intFromEnum(layer);
        }

        pub inline fn add(self: Mask, layers: []const Layer) Mask {
            var mask: T = @intFromEnum(self);

            for (layers) |layer| {
                mask |= @intFromEnum(layer);
            }

            return @enumFromInt(mask);
        }

        pub inline fn remove(self: Mask, layers: []const Layer) Mask {
            var mask: T = @intFromEnum(self);

            for (layers) |layer| {
                mask -= @intFromEnum(layer);
            }

            return @enumFromInt(mask);
        }

        pub inline fn make(layers: []const Layer) Mask {
            var mask: T = 0;

            for (layers) |layer| {
                mask |= @intFromEnum(layer);
            }

            return @enumFromInt(mask);
        }
    };

    pub const Sphere = struct { radius: f32 };
    pub const Capsule = struct { radius: f32, half_height: f32 };
    pub const Box = @import("math").f32.Vector3;
};
