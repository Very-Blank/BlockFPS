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
const Damage = @import("components/Damage.zig");
const LifeTime = @import("components/LifeTime.zig");

pub const Ecs = ecs.Ecs(&.{
    ecs.Template{ .components = &.{ LifeTime, Damage, Position, Scale, Rotation, ModelInstance, Collider, Rigidbody } },
    ecs.Template{ .components = &.{ Position, Scale, Rotation, ModelInstance, Collider, Rigidbody } },

    ecs.Template{ .components = &.{ Health, Position, Scale, Rotation, Model, Collider, Rigidbody } },
    ecs.Template{ .components = &.{ Position, Scale, Rotation, Model, Collider, Rigidbody } },
    ecs.Template{ .components = &.{ Position, Scale, Rotation, Model, Collider } },
    ecs.Template{ .components = &.{ Position, Scale, Rotation, Model } },
    ecs.Template{ .components = &.{ Position, Collider, Rigidbody, Grounded, Camera } }, // NOTE: Player
});
