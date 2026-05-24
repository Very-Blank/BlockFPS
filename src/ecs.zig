const ecs = @import("ecs");

const Model = @import("components/Model.zig");
const Position = @import("components/position.zig").Position;
const Rotation = @import("components/rotation.zig").Rotation;
const Scale = @import("components/scale.zig").Scale;
const Camera = @import("components/Camera.zig");

pub const Ecs = ecs.Ecs(&.{
    ecs.Template{ .components = &.{ Position, Scale, Rotation, Model } },
    ecs.Template{ .components = &.{ Position, Camera } },
});
