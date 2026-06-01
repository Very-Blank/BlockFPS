const std = @import("std");
const glad = @import("glad");
const imgui = @import("imgui");
const ecs = @import("ecs");
const glfw = @import("glfw");
const math = @import("math");

const Io = std.Io;

const Vector3 = math.f32.Vector3;

const Window = @import("Window.zig");
const ImGui = @import("ImGui.zig");

const Shader = @import("Shader.zig");
const Program = @import("Program.zig");

const Rendering = @import("Rendering.zig");
const Physics = @import("Physics.zig");

const Model = @import("components/Model.zig");
const ModelInstance = @import("components/model_instance.zig").ModelInstance;
const Position = @import("components/position.zig").Position;
const Rotation = @import("components/rotation.zig").Rotation;
const Scale = @import("components/scale.zig").Scale;
const Camera = @import("components/Camera.zig");
const Collider = @import("components/collider.zig").Collider;
const Rigidbody = @import("components/Rigidbody.zig");

const Enemy = @import("components/Enemy.zig");
const Health = @import("components/Health.zig");
const Bullet = @import("components/Bullet.zig");
const Grounded = @import("components/Grounded.zig");

const Ecs = @import("ecs.zig").Ecs;
const Template = ecs.Template;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    var prng: std.Random.DefaultPrng = .init(blk: {
        var seed: u64 = undefined;
        io.random(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const rand = prng.random();

    var window = try Window.init("Game", 100, 100);
    defer window.deinit();

    window.setCallbacks();
    window.sync(); // NOTE: We missed some window callbacks so we need to sync.
    window.setMouseMode(.disabled);

    var gui = ImGui.init(window);
    defer gui.deinit();

    const DebugData: type = struct {
        spawn_pressed: bool = false,
        position: Position = .zero,
        scale: Scale = .one,
        rotation: Vector3 = .zero,
    };

    var debug_window: ImGui.GuiWindow(DebugData) = .{
        .name = "Debug",
        .open = false,
        .state = .closed,
        .data = .{},
        .draw_fn = struct {
            pub fn draw(data: *DebugData) void {
                if (imgui.ImGui_CollapsingHeader("Position", 0)) {
                    _ = imgui.ImGui_DragFloat3("X Y Z##pos", @ptrCast(&data.position));
                }

                if (imgui.ImGui_CollapsingHeader("Scale", 0)) {
                    _ = imgui.ImGui_DragFloat3("X Y Z##scale", @ptrCast(&data.scale));
                }

                if (imgui.ImGui_CollapsingHeader("Rotation", 0)) {
                    _ = imgui.ImGui_DragFloat3("X Y Z##rot", @ptrCast(&data.rotation));
                }

                imgui.ImGui_Separator();

                data.spawn_pressed = imgui.ImGui_Button("Spawn");
            }
        }.draw,
    };

    const rendering: Rendering = try .init(io, gpa);
    defer rendering.deinit();

    const buffer: []u8 = try gpa.alloc(u8, 4_000_000);
    defer gpa.free(buffer);
    var fba: std.heap.FixedBufferAllocator = .init(buffer);
    var ecs_engine: Ecs = try .init(fba.allocator());
    defer ecs_engine.deinit();

    var physics: Physics = .init(gpa);
    defer physics.deinit();

    const player_singleton = ecs_engine.createSingleton(.{ .components = &.{ Position, Rigidbody, Camera } });

    makeArena(&ecs_engine, 50.0);

    _ = ecs_engine.createEntity(.{
        Enemy{
            .state = .patrol,
            .vision = .{
                .memory = .{ .duration = 5.0, .elapsed = 5.0 },
                .distance = 15.0,
                .angle = std.math.pi,
            },
            .follow = .{ .accuracy = 0.3, .distance = 6.0, .speed = 4.5 },
            .patrol = .{
                .path = .{
                    .waypoints = .{
                        .{ .x = 0, .y = 1, .z = 5 },
                        .{ .x = 8, .y = 1, .z = 3 },
                        .{ .x = -8, .y = 1, .z = 8 },
                        .{ .x = 5, .y = 1, .z = 8 },
                    },
                },
                .wait = .{ .duration = 1.5 },
                .accuracy = 0.5,
                .speed = 2.0,
            },

            .attack = .{
                .range = 15.0,
                .speed = 6.0,
                .distance = 10.0,
                .weapon = .{
                    .type = .single,
                    .cooldown = .{ .duration = 1.5 },
                    .bullet = .{ .speed = 80.0, .damage = 25.0 },
                },
                .jump = .{
                    .force = 4.0,
                    .cooldown = .{ .duration = 5.0 },
                },
                .strafe = .{
                    .speed = 10.0,
                    .direction = .{},
                    .@"switch" = .{ .duration = 3.0 },
                },
            },
        },
        Health{ .current = 50.0, .max = 50.0 },
        Position{ .y = 1.5, .z = 3 },
        Scale{ .x = 1.0, .y = 2.0, .z = 1.0 },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .capsule = .{ .radius = 0.5, .half_height = 1 } },
        Rigidbody{ .restitution = 0.0, .mass = 5.0 },
        Grounded{ .grounded = false },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Enemy{
            .state = .patrol,
            .vision = .{
                .memory = .{ .duration = 5.0, .elapsed = 5.0 },
                .distance = 15.0,
                .angle = std.math.pi,
            },
            .follow = .{ .accuracy = 0.3, .distance = 6.0, .speed = 4.5 },
            .patrol = .{
                .path = .{
                    .waypoints = .{
                        .{ .x = 0, .y = 1, .z = 9 },
                        .{ .x = 8, .y = 1, .z = -4 },
                        .{ .x = -8, .y = 1, .z = -8 },
                        .{ .x = 5, .y = 1, .z = -8 },
                    },
                },
                .wait = .{ .duration = 1.5 },
                .accuracy = 0.5,
                .speed = 2.0,
            },

            .attack = .{
                .range = 15.0,
                .speed = 6.0,
                .distance = 10.0,
                .weapon = .{
                    .type = .{ .burst = .{ .length = .{ .duration = 0.5 }, .rpm = .{ .duration = 0.1 } } },
                    .cooldown = .{ .duration = 1.5 },
                    .bullet = .{ .speed = 50.0, .damage = 10.0 },
                },
                .jump = .{
                    .force = 4.0,
                    .cooldown = .{ .duration = 5.0 },
                },
                .strafe = .{
                    .speed = 10.0,
                    .direction = .{},
                    .@"switch" = .{ .duration = 1.2 },
                },
            },
        },
        Health{ .current = 50.0, .max = 50.0 },
        Position{ .y = 1.5, .z = 5, .x = 5 },
        Scale{ .x = 1.0, .y = 2.0, .z = 1.0 },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .capsule = .{ .radius = 0.5, .half_height = 1 } },
        Rigidbody{ .restitution = 0.0, .mass = 5.0 },
        Grounded{ .grounded = false },
    }, &.{});

    const player_entity = ecs_engine.createEntity(.{
        Health{ .current = 50.0, .max = 50.0 },
        Position{ .x = -3, .y = 1.1 },
        Rigidbody{ .mass = 5.0, .restitution = 0.0 },
        Collider{ .capsule = .{ .radius = 0.25, .half_height = 1 } },
        Grounded{ .grounded = false },
        Camera{
            .offset = 0.75,
            .projection = .{ .far = 1000.0, .near = 0.001, .fov = 90 },
            .rotation = .{ .pitch = 0.0, .yaw = 0.0 },
            .view = .initPerspective(
                90.0,
                @as(f32, @floatFromInt(window.width)) / @as(f32, @floatFromInt(window.height)),
                100.0,
                0.01,
            ),
        },
    }, &.{});

    ecs_engine.setSingletonsEntity(player_singleton, player_entity) catch unreachable;

    var lapsed_time: f64 = 0.0;
    var ignore_input: bool = false;

    while (window.run()) {
        glad.glClear(glad.GL_COLOR_BUFFER_BIT | glad.GL_DEPTH_BUFFER_BIT);
        glad.glClearColor(66.0 / 245.0, 161.0 / 245.0, 245 / 245.0, 1.0);

        const delta_time: f32 = outer: {
            const delta_time: f64 = glfw.glfwGetTime() - lapsed_time;
            lapsed_time += delta_time;

            break :outer @floatCast(delta_time);
        };

        physics.update(&ecs_engine, delta_time);
        handleCollision(&physics, &ecs_engine);

        if (window.input.getKeyState(.escape) == .justPressed) {
            ignore_input = true;
            window.setMouseMode(.captured);
            debug_window.setOpenState(true);
        }

        if (debug_window.state == .just_closed) {
            ignore_input = false;
            window.setMouseMode(.disabled);
        } else if (debug_window.state.isOpen() and debug_window.data.spawn_pressed) {
            _ = ecs_engine.createEntity(.{
                debug_window.data.position,
                debug_window.data.scale,
                Rotation.initFromVector(debug_window.data.rotation.segment(std.math.pi)),
                Model.init(Model.cube),
            }, &.{});
        }

        update_view: {
            var iterator = ecs_engine.getIterator(.{ .component = Camera }) orelse break :update_view;

            const aspect: f32 = @as(f32, @floatFromInt(window.width)) / @as(f32, @floatFromInt(window.height));

            while (iterator.next()) |camera| {
                camera.updateView(aspect);
            }
        }

        var view_matrix, var projection_matrix = init: {
            if (ecs_engine.getSingletonsEntity(player_singleton)) |id| {
                const player: Player = .{
                    .position = ecs_engine.getEntityComponent(id, Position) catch unreachable,
                    .rigidbody = ecs_engine.getEntityComponent(id, Rigidbody) catch unreachable,
                    .grounded = ecs_engine.getEntityComponent(id, Grounded) catch unreachable,
                    .camera = ecs_engine.getEntityComponent(id, Camera) catch unreachable,
                };

                if (!ignore_input) {
                    handlePlayerInput(&window, player, delta_time);

                    if (window.input.mouse_state.left_click == .justPressed) {
                        const forward = Vector3.forward
                            .rotateAroundAxis(.x, player.camera.rotation.pitch)
                            .rotateAroundAxis(.y, player.camera.rotation.yaw)
                            .normalize()
                            .negate();

                        _ = ecs_engine.createEntity(.{
                            Bullet{ .damage = 10, .duration = 3.0, .max_deflection_angle = 0.85 },
                            player.position.add(forward).add(Position{ .y = player.camera.offset }),
                            Scale{ .x = 0.1, .y = 0.1, .z = 0.1 },
                            Rotation.identity,
                            ModelInstance.cube,
                            Collider{ .sphere = .{ .radius = 0.5 } },
                            Rigidbody{ .velocity = forward.scale(50.0), .gravity = 0.0, .restitution = 0.0, .mass = 0.1 },
                        }, &.{});
                    }
                }

                break :init .{
                    math.f32.Mat4.initView(
                        player.position.add(Position{ .y = player.camera.offset }).negate(),
                        math.f32.Quaternion.initCamRotation(
                            -player.camera.rotation.yaw,
                            -player.camera.rotation.pitch,
                        ),
                    ),
                    player.camera.view,
                };
            }

            break :init .{ math.f32.Mat4.identity, math.f32.Mat4.identity };
        };

        enemy: {
            const player_id = ecs_engine.getSingletonsEntity(player_singleton) orelse break :enemy;
            const player_pos = ecs_engine.getEntityComponent(player_id, Position) catch unreachable;

            var iterator = ecs_engine.getTupleIterator(.{
                .include = ecs.Template{ .components = &.{ Enemy, Position, Rotation, Rigidbody, Grounded } },
            }) orelse break :enemy;

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
                            &ecs_engine,
                            enemy_position.add(enemy_forward.scale(1.5)).coerce(Vector3),
                            player_pos.add(Position{ .y = 0.5 }).subtract(enemy_position.*).normalize().coerce(Vector3),
                            enemy.vision.distance,
                        ) orelse break :blk false;
                        break :blk hit.body.eql(player_id);
                    };

                // ── Sight memory: keep chasing N seconds after losing LOS ─────────
                if (player_visible) {
                    enemy.vision.memory.reset();
                } else {
                    _ = enemy.vision.memory.pass(delta_time);
                }

                const player_detected = player_visible or !enemy.vision.memory.up();

                // ── State transitions ─────────────────────────────────────────────
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

                // ── Behavior ──────────────────────────────────────────────────────
                var face_direction = enemy_forward;

                switch (enemy.state) {
                    .patrol => {
                        if (!enemy.patrol.wait.pass(delta_time)) {
                            enemy_rb.velocity.x = 0;
                            enemy_rb.velocity.z = 0;
                        } else {
                            const current_waypoint: Vector3 = enemy.patrol.path.current();

                            if (enemy_position.distance(current_waypoint) <= enemy.patrol.accuracy) {
                                enemy.patrol.path.next(rand.int(usize));
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

                        // ── Erratic strafing ──────────────────────────────────────
                        // Perpendicular to the player direction on the XZ plane
                        const right = Position{ .x = -player_direction.z, .y = 0.0, .z = player_direction.x };

                        // Randomly flip strafe direction on interval
                        if (enemy.attack.strafe.@"switch".pass(delta_time)) {
                            enemy.attack.strafe.direction.x = @min(0.05, rand.float(f32));
                            if (rand.boolean()) {
                                enemy.attack.strafe.direction.x = -enemy.attack.strafe.direction.x;
                            }

                            enemy.attack.strafe.direction.z = @min(0.05, rand.float(f32));
                            if (rand.boolean()) {
                                enemy.attack.strafe.direction.z = -enemy.attack.strafe.direction.z;
                            }

                            enemy.attack.strafe.direction = enemy.attack.strafe.direction.normalize();

                            enemy.attack.strafe.@"switch".reset();
                        }

                        const strafe = right.multiply(enemy.attack.strafe.direction).scale(enemy.attack.strafe.speed);
                        const approach = player_direction.scale(
                            std.math.clamp((player_distance - enemy.attack.distance) / enemy.attack.distance, -1.0, 1.0) * enemy.attack.speed,
                        );

                        enemy_rb.velocity.x = strafe.x + approach.x;
                        enemy_rb.velocity.z = strafe.z + approach.z;

                        // ── Jump: grounded only, on its own cooldown ──────────────
                        if (enemy.attack.jump.cooldown.pass(delta_time) and grounded.grounded) {
                            enemy.attack.jump.cooldown.reset();
                            enemy_rb.velocity.y = enemy.attack.jump.force;
                        }

                        // ── Shoot ─────────────────────────────────────────────────
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
                                                ModelInstance.cube,
                                                Collider{ .sphere = .{ .radius = 0.5 } },
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
                                        ModelInstance.cube,
                                        Collider{ .sphere = .{ .radius = 0.5 } },
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

        render: {
            var tuple_iterator = ecs_engine.getTupleIterator(.{
                .include = ecs.Template{ .components = &.{ Position, Scale, Rotation, Model } },
            }) orelse break :render;

            rendering.startRender();

            glad.glUniformMatrix4fv(rendering.program.getUniform("view"), 1, glad.GL_FALSE, &view_matrix.fields[0][0]);
            glad.glUniformMatrix4fv(rendering.program.getUniform("projection"), 1, glad.GL_FALSE, &projection_matrix.fields[0][0]);

            rendering.drawModels(&tuple_iterator);
        }

        render: {
            var tuple_iterator = ecs_engine.getTupleIterator(.{
                .include = ecs.Template{ .components = &.{ Position, Scale, Rotation, ModelInstance } },
            }) orelse break :render;

            rendering.startRender();

            glad.glUniformMatrix4fv(rendering.program.getUniform("view"), 1, glad.GL_FALSE, &view_matrix.fields[0][0]);
            glad.glUniformMatrix4fv(rendering.program.getUniform("projection"), 1, glad.GL_FALSE, &projection_matrix.fields[0][0]);

            rendering.drawIntances(&tuple_iterator);
        }

        destroy: {
            var iterator = ecs_engine.getIterator(.{
                .component = Position,
            }) orelse break :destroy;

            while (iterator.next()) |position| {
                if (position.y < -100.0) {
                    ecs_engine.destroyEntity(iterator.getCurrentEntity());
                }
            }
        }

        destroy: {
            var iterator = ecs_engine.getIterator(.{
                .component = Health,
            }) orelse break :destroy;

            while (iterator.next()) |health| {
                if (health.current <= 0) {
                    ecs_engine.destroyEntity(iterator.getCurrentEntity());
                }
            }
        }

        destroy: {
            var iterator = ecs_engine.getIterator(.{
                .component = Bullet,
            }) orelse break :destroy;

            while (iterator.next()) |buller| {
                buller.elapsed += delta_time;
                if (buller.duration < buller.elapsed) {
                    ecs_engine.destroyEntity(iterator.getCurrentEntity());
                }
            }
        }

        gui.newFrame();

        debug_window.draw();

        gui.render();

        gui.endFrame();

        physics.clear();
        ecs_engine.clearDestroyedEntitys();

        window.swapAndPoll();
    }
}

pub fn handleCollision(physics: *Physics, ecs_engine: *Ecs) void {
    for (physics.sbVsRb_collisions.items, 0..) |collision, i| {
        if (ecs_engine.entityHas(collision.body1, Grounded) and 0.9 < physics.sbVsRb_infos.items[i].normal.dot(Vector3.up)) {
            const grounded = ecs_engine.getEntityComponent(collision.body1, Grounded) catch unreachable;
            grounded.grounded = true;
        }

        if (ecs_engine.entityHas(collision.body1, Bullet)) {
            const bullet = ecs_engine.getEntityComponent(collision.body1, Bullet) catch unreachable;
            if (bullet.max_deflection_angle < -physics.sbVsRb_infos.items[i].angle) {
                ecs_engine.destroyEntity(collision.body1);
            }
        }
    }

    for (physics.rbVsRb_collisions.items, 0..) |collision, i| {
        if (ecs_engine.entityHas(collision.body1, Grounded) and 0.9 < physics.rbVsRb_infos.items[i].normal.dot(Vector3.up)) {
            const grounded = ecs_engine.getEntityComponent(collision.body1, Grounded) catch unreachable;
            grounded.grounded = true;
        }

        if (ecs_engine.entityHas(collision.body2, Grounded) and 0.9 < physics.rbVsRb_infos.items[i].normal.negate().dot(Vector3.up)) {
            const grounded = ecs_engine.getEntityComponent(collision.body2, Grounded) catch unreachable;
            grounded.grounded = true;
        }

        if (ecs_engine.entityHas(collision.body1, Health) and ecs_engine.entityHas(collision.body2, Bullet)) {
            const health = ecs_engine.getEntityComponent(collision.body1, Health) catch unreachable;
            const bullet = ecs_engine.getEntityComponent(collision.body2, Bullet) catch unreachable;
            health.current -= bullet.damage;

            ecs_engine.destroyEntity(collision.body2);
        }

        if (ecs_engine.entityHas(collision.body2, Health) and ecs_engine.entityHas(collision.body1, Bullet)) {
            const health = ecs_engine.getEntityComponent(collision.body2, Health) catch unreachable;
            const bullet = ecs_engine.getEntityComponent(collision.body1, Bullet) catch unreachable;
            health.current -= bullet.damage;

            ecs_engine.destroyEntity(collision.body1);
        }
    }

    physics.clear();
}

const Player = struct { position: *Position, rigidbody: *Rigidbody, grounded: *Grounded, camera: *Camera };

pub fn handlePlayerInput(window: *Window, player: Player, _: f32) void {
    player.camera.rotation.yaw -= window.input.mouse_state.motion.x;
    player.camera.rotation.pitch += window.input.mouse_state.motion.y;

    var movement_input: Vector3 = .zero;
    if (window.input.getKeyState(.w).isDown()) {
        movement_input.z -= 1.0;
    }
    if (window.input.getKeyState(.s).isDown()) {
        movement_input.z += 1.0;
    }
    if (window.input.getKeyState(.d).isDown()) {
        movement_input.x += 1.0;
    }
    if (window.input.getKeyState(.a).isDown()) {
        movement_input.x -= 1.0;
    }

    if (player.grounded.grounded and window.input.getKeyState(.space) == .justPressed) {
        player.rigidbody.velocity.y += 5;
    }

    if (movement_input.length() > 0.0) {
        movement_input = movement_input.normalize().rotateAroundAxis(.y, player.camera.rotation.yaw).scale(if (window.input.getKeyState(.left_shift).isDown()) 10 else 4);
        player.rigidbody.velocity.x = movement_input.x;
        player.rigidbody.velocity.z = movement_input.z;
    } else {
        player.rigidbody.velocity.x = 0.0;
        player.rigidbody.velocity.z = 0.0;
    }
}

pub fn makeArena(ecs_engine: *Ecs, size: f32) void {
    const wall_height = 5.0;
    const wall_thickness = 0.5;

    const half_arena = size / 2.0;
    const wall_offset = half_arena + (wall_thickness / 2.0);

    _ = ecs_engine.createEntity(.{
        Position{ .y = -0.5 },
        Scale{ .x = size, .y = 0.5, .z = size },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .{ .x = size, .y = 0.5, .z = size } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = 0, .y = wall_height / 2.0 - 0.5, .z = -wall_offset },
        Scale{ .x = size, .y = wall_height, .z = wall_thickness },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .{
            .x = size,
            .y = wall_height,
            .z = wall_thickness,
        } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = 0, .y = wall_height / 2.0 - 0.5, .z = wall_offset },
        Scale{ .x = size, .y = wall_height, .z = wall_thickness },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .{
            .x = size,
            .y = wall_height,
            .z = wall_thickness,
        } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = -wall_offset, .y = wall_height / 2.0 - 0.5, .z = 0 },
        Scale{ .x = wall_thickness, .y = wall_height, .z = size },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .{
            .x = wall_thickness,
            .y = wall_height,
            .z = size,
        } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = wall_offset, .y = wall_height / 2.0 - 0.5, .z = 0 },
        Scale{ .x = wall_thickness, .y = wall_height, .z = size },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .{
            .x = wall_thickness,
            .y = wall_height,
            .z = size,
        } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = 10, .y = wall_height / 2.0 - 0.5, .z = 8 },
        Scale{ .x = wall_thickness, .y = wall_height, .z = 10 },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .{ .x = wall_thickness, .y = 3.0, .z = 10 } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .y = 2.5 },
        Scale.one,
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .one },
        Rigidbody{ .velocity = .{ .y = -0.5 }, .restitution = 0.5, .mass = 10.0 },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .one },
        Rigidbody{ .restitution = 0.5, .mass = 10.0 },
    }, &.{});
}
