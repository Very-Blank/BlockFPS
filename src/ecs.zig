const ecs = @import("ecs");

const Model = @import("components/Model.zig");
const ModelInstance = @import("components/model_instance.zig").ModelInstance;
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

pub const Ecs = ecs.Ecs(&.{
    ecs.Template{ .components = &.{ Position, Scale, Rotation, Model, Collider, Rigidbody } },
    ecs.Template{ .components = &.{ Position, Scale, Rotation, Model, Collider } },
    ecs.Template{ .components = &.{ Position, Scale, Rotation, Model } },
    //
    ecs.Template{ .components = &.{ Bullet, Position, Scale, Rotation, ModelInstance, Collider, Rigidbody } }, // NOTE: Bullet
    ecs.Template{ .components = &.{ Enemy, Health, Position, Scale, Rotation, Model, Collider, Rigidbody } }, // NOTE: Enemy
    ecs.Template{ .components = &.{ Position, Collider, Rigidbody, Grounded, Camera } }, // NOTE: Player
});
