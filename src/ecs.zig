const ecs = @import("ecs");
const math = @import("math");

const Model = @import("components/model.zig").Model;
const Position = @import("components/position.zig").Position;
const Rotation = @import("components/rotation.zig").Rotation;
const Scale = @import("components/scale.zig").Scale;
const Camera = @import("components/Camera.zig");
const Collider = @import("components/collider.zig").Collider;
const Rigidbody = @import("components/Rigidbody.zig");
const Grounded = @import("components/Grounded.zig");
const Health = @import("components/Health.zig");
const Bullet = @import("components/Bullet.zig");
const Enemy = @import("components/Enemy.zig");
const Pickable = @import("components/pickable.zig").Pickable;

pub const Parent = struct { position: Position, rotation: Rotation };

pub const Ecs = ecs.Ecs(
    &.{
        ecs.Template{ .components = &.{Position} }, // NOTE: Spawnpoint,
        ecs.Template{ .components = &.{ Position, Scale, Rotation, Model, Collider, Rigidbody }, .tags = &.{Pickable} },
        ecs.Template{ .components = &.{ Position, Scale, Rotation, Model, Collider, Rigidbody } },
        ecs.Template{ .components = &.{ Position, Scale, Rotation, Model, Collider } },
        ecs.Template{ .components = &.{ Position, Scale, Rotation, Model } },
        ecs.Template{ .components = &.{ Bullet, Position, Scale, Rotation, Model, Collider, Rigidbody } }, // NOTE: Bullet
        ecs.Template{ .components = &.{ Enemy, Health, Position, Scale, Rotation, Model, Collider, Rigidbody, Grounded } }, // NOTE: Enemy
        ecs.Template{ .components = &.{ Health, Position, Collider, Rigidbody, Grounded } }, // NOTE: Player
        ecs.Template{ .components = &.{ Position, Rotation, Camera } }, // NOTE: Cam
    },
    &.{
        .{ .name = "parent", .T = Parent, .mode = .source, .requirments = .{ .components = &.{ Position, Rotation } } },
        .{ .name = "follow", .T = Position, .mode = .source, .requirments = .{ .components = &.{Position} } },
    },
);
