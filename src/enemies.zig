const std = @import("std");
const ecs = @import("ecs");
const math = @import("math");

const Vector3 = math.f32.Vector3;

const Physics = @import("Physics.zig");

const Model = @import("components/model.zig").Model;
const Position = @import("components/position.zig").Position;
const Rotation = @import("components/rotation.zig").Rotation;
const Scale = @import("components/scale.zig").Scale;
const Camera = @import("components/Camera.zig");
const Collider = @import("components/collider.zig").Collider;
const Mask = Collider.Mask;
const Rigidbody = @import("components/Rigidbody.zig");

const Enemy = @import("components/Enemy.zig");
const Health = @import("components/Health.zig");
const Bullet = @import("components/Bullet.zig");
const Grounded = @import("components/Grounded.zig");

const Ecs = @import("ecs.zig").Ecs;
const SingletonType = ecs.SingletonType;
const Template = ecs.Template;

pub fn update(ecs_engine: *Ecs, player_singleton: SingletonType, random: std.Random, delta_time: f32) void {
    const player_id = ecs_engine.getSingletonsEntity(player_singleton) orelse return;
    const player_pos = ecs_engine.getEntityComponent(player_id, Position) catch unreachable;

    var iterator = ecs_engine.getTupleIterator(.{
        .include = ecs.Template{ .components = &.{ Enemy, Position, Rotation, Rigidbody, Grounded } },
    }) orelse return;

    while (iterator.next()) |tuple| {
        const enemy: *Enemy = tuple[0];
        const enemy_position: *Position = tuple[1];
        const enemy_rot: *Rotation = tuple[2];
        const enemy_rb: *Rigidbody = tuple[3];
        const grounded: *Grounded = tuple[4];

        const to_player = player_pos.subtract(enemy_position.*);
        const player_distance = to_player.length();
        if (player_distance < 0.001) continue;

        const player_direction = to_player.normalize();

        const enemy_forward: Vector3 = .rotate(.forward, enemy_rot.*);

        const player_visible =
            @cos(enemy.vision.angle) <= enemy_forward.dot(player_direction) and
            player_distance <= enemy.vision.distance and
            blk: {
                const hit = Physics.raycast(
                    ecs_engine,
                    enemy_position.coerce(Vector3),
                    player_pos.add(Position{ .y = 0.5 }).subtract(enemy_position.*).normalize().coerce(Vector3),
                    enemy.vision.distance,
                    Mask.all.remove(&.{.enemy}),
                ) orelse break :blk false;
                break :blk hit.body.eql(player_id);
            };

        if (player_visible) {
            enemy.vision.memory.reset();
        } else {
            _ = enemy.vision.memory.pass(delta_time);
        }

        const player_detected = player_visible or !enemy.vision.memory.up();

        enemy.state = next_state: switch (enemy.state) {
            .patrol => if (player_detected) .follow else .patrol,
            .follow => if (!player_detected) {
                break :next_state .patrol;
            } else if (player_distance <= enemy.attack.range and player_visible) {
                break :next_state .attack;
            } else {
                break :next_state .follow;
            },
            .attack => if (!player_detected) {
                break :next_state .patrol;
            } else if (!player_visible and enemy.attack.range < player_distance) {
                break :next_state .follow;
            } else {
                break :next_state .attack;
            },
        };

        var face_direction = enemy_forward;

        switch (enemy.state) {
            .patrol => {
                if (!enemy.patrol.wait.pass(delta_time)) {
                    enemy_rb.velocity.x = 0;
                    enemy_rb.velocity.z = 0;
                } else {
                    const current_waypoint: Vector3 = enemy.patrol.path.current();

                    if (enemy_position.distance(current_waypoint) <= enemy.patrol.accuracy) {
                        enemy.patrol.path.next(random.int(usize));
                        enemy.patrol.wait.reset();

                        enemy_rb.velocity.x = 0;
                        enemy_rb.velocity.z = 0;
                    } else {
                        const movement_direction = current_waypoint.subtract(enemy_position.*).normalize();
                        const movement = movement_direction.scale(enemy.patrol.speed);

                        enemy_rb.velocity.x = movement.x;
                        enemy_rb.velocity.z = movement.z;

                        face_direction = movement_direction;
                    }
                }
            },
            .follow => {
                const adjusted = player_direction.scale(player_distance - enemy.follow.distance);

                if (enemy.follow.accuracy < adjusted.length()) {
                    const move = adjusted.normalize().scale(enemy.follow.speed);
                    enemy_rb.velocity.x = move.x;
                    enemy_rb.velocity.z = move.z;
                } else {
                    enemy_rb.velocity.x = 0;
                    enemy_rb.velocity.z = 0;
                }

                face_direction = player_direction.coerce(Vector3);
            },
            .attack => {
                face_direction = player_direction.coerce(Vector3);

                const right = Position{ .x = -player_direction.z, .y = 0.0, .z = player_direction.x };

                if (enemy.attack.strafe.change.pass(delta_time)) {
                    enemy.attack.strafe.direction = -1.0 + random.float(f32) * 2;
                    enemy.attack.strafe.change.reset();
                }

                if (enemy.attack.move.distance.change.pass(delta_time)) {
                    enemy.attack.move.distance.current = enemy.attack.move.distance.min + (enemy.attack.move.distance.max - enemy.attack.move.distance.min) * random.float(f32);
                    enemy.attack.move.distance.change.reset();
                }

                const strafe = right.scale(enemy.attack.strafe.direction * enemy.attack.strafe.speed);
                const approach = player_direction.scale(
                    std.math.clamp((player_distance - enemy.attack.move.distance.current) / enemy.attack.move.distance.current, -1.0, 1.0) * enemy.attack.move.speed,
                );

                enemy_rb.velocity.x = strafe.x + approach.x;
                enemy_rb.velocity.z = strafe.z + approach.z;

                if (enemy.attack.jump.cooldown.pass(delta_time) and grounded.grounded) {
                    enemy.attack.jump.cooldown.reset();
                    enemy_rb.velocity.y = enemy.attack.jump.force;
                }

                if (enemy.attack.weapon.cooldown.pass(delta_time)) {
                    switch (enemy.attack.weapon.type) {
                        .burst => |*burst| {
                            if (burst.length.pass(delta_time)) {
                                burst.length.reset();
                                burst.rpm.reset();
                                enemy.attack.weapon.cooldown.reset();
                            } else {
                                if (burst.rpm.pass(delta_time)) {
                                    _ = ecs_engine.createEntity(.{
                                        Bullet{
                                            .damage = enemy.attack.weapon.bullet.damage,
                                            .duration = 3.0,
                                            .max_deflection_angle = 0.85,
                                        },
                                        Position{
                                            .x = enemy_position.x + enemy_forward.x * 0.9,
                                            .y = enemy_position.y + enemy_forward.y * 0.9,
                                            .z = enemy_position.z + enemy_forward.z * 0.9,
                                        },
                                        Scale{ .x = 0.1, .y = 0.1, .z = 0.1 },
                                        Rotation.identity,
                                        Model{},
                                        Collider{ .type = .{ .sphere = .{ .radius = 0.5 } } },
                                        Rigidbody{
                                            .velocity = player_direction.scale(enemy.attack.weapon.bullet.speed).coerce(Vector3),
                                            .gravity = 0.0,
                                            .restitution = 0.0,
                                            .mass = 0.1,
                                        },
                                    }, &.{});

                                    burst.rpm.reset();
                                }
                            }
                        },
                        .single => {
                            _ = ecs_engine.createEntity(.{
                                Bullet{
                                    .damage = enemy.attack.weapon.bullet.damage,
                                    .duration = 3.0,
                                    .max_deflection_angle = 0.85,
                                },
                                Position{
                                    .x = enemy_position.x + enemy_forward.x * 0.9,
                                    .y = enemy_position.y + enemy_forward.y * 0.9,
                                    .z = enemy_position.z + enemy_forward.z * 0.9,
                                },
                                Scale{ .x = 0.1, .y = 0.1, .z = 0.1 },
                                Rotation.identity,
                                Model{},
                                Collider{ .type = .{ .sphere = .{ .radius = 0.5 } } },
                                Rigidbody{
                                    .velocity = player_direction.scale(enemy.attack.weapon.bullet.speed).coerce(Vector3),
                                    .gravity = 0.0,
                                    .restitution = 0.0,
                                    .mass = 0.1,
                                },
                            }, &.{});

                            enemy.attack.weapon.cooldown.reset();
                        },
                    }
                }
            },
        }

        face_direction.y = 0.0;
        if (0.0001 < face_direction.magnitude()) {
            const yaw = std.math.atan2(face_direction.x, face_direction.z);
            enemy_rot.* = Rotation.initFromRadians(.y, yaw);
        }
    }
}
