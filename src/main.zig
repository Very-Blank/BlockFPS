const std = @import("std");
const glad = @import("glad");
const imgui = @import("imgui");
const ecs = @import("ecs");
const glfw = @import("glfw");
const math = @import("math");
const Physics = @import("Physics.zig");

const Io = std.Io;

const Window = @import("Window.zig");
const ImGui = @import("ImGui.zig");

const Shader = @import("Shader.zig");
const Program = @import("Program.zig");

const Rendering = @import("Rendering.zig");

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
        rotation: math.f32.Vector3 = .zero,
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

    _ = ecs_engine.createEntity(.{
        Position{ .y = -0.5 },
        Scale{ .x = 20, .y = 0.5, .z = 20 },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .{ .x = 20.0, .y = 0.5, .z = 20.0 } },
    }, &.{});

    // Wall: -Z (front)
    _ = ecs_engine.createEntity(.{
        Position{ .x = 0, .y = 2.0, .z = -10.25 },
        Scale{ .x = 20, .y = 5.0, .z = 0.5 },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .{ .x = 20.0, .y = 5.0, .z = 0.5 } },
    }, &.{});

    // Wall: +Z (back)
    _ = ecs_engine.createEntity(.{
        Position{ .x = 0, .y = 2.0, .z = 10.25 },
        Scale{ .x = 20, .y = 5.0, .z = 0.5 },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .{ .x = 20.0, .y = 5.0, .z = 0.5 } },
    }, &.{});

    // Wall: -X (left)
    _ = ecs_engine.createEntity(.{
        Position{ .x = -10.25, .y = 2.0, .z = 0 },
        Scale{ .x = 0.5, .y = 5.0, .z = 20 },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .{ .x = 0.5, .y = 5.0, .z = 20.0 } },
    }, &.{});

    // Wall: +X (right)
    _ = ecs_engine.createEntity(.{
        Position{ .x = 10.25, .y = 2.0, .z = 0 },
        Scale{ .x = 0.5, .y = 5.0, .z = 20 },
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .{ .x = 0.5, .y = 5.0, .z = 20.0 } },
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

    _ = ecs_engine.createEntity(.{
        Enemy{ .follow_speed = 5.0, .follow_distance = 5.0 },
        Health{ .current = 50.0, .max = 50.0 },
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .one },
        Rigidbody{ .restitution = 0.5, .mass = 10.0 },
    }, &.{});

    const player_entity = ecs_engine.createEntity(.{
        Position{ .x = -3, .y = 1.1 },
        Rigidbody{ .mass = 5.0, .restitution = 0.0 },
        Collider{ .capsule = .{ .radius = 0.5, .height = 2 } },
        Grounded{ .grounded = false },
        Camera{
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
                        const forward = math.f32.Vector3.forward
                            .rotateAroundAxis(.x, player.camera.rotation.pitch)
                            .rotateAroundAxis(.y, player.camera.rotation.yaw)
                            .normalize()
                            .negate();

                        _ = ecs_engine.createEntity(.{
                            Bullet{ .damage = 10, .duration = 3.0, .max_deflection_angle = 0.85 },
                            player.position.add(forward),
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
                        player.position.negate(),
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
            const id = ecs_engine.getSingletonsEntity(player_singleton) orelse break :enemy;
            const position = ecs_engine.getEntityComponent(id, Position) catch unreachable;

            var iterator = ecs_engine.getTupleIterator(.{
                .include = ecs.Template{ .components = &.{ Enemy, Position, Rigidbody } },
            }) orelse break :enemy;

            while (iterator.next()) |tuple| {
                const enemy: *Enemy = tuple[0];
                const enemy_position: *Position = tuple[1];
                const enemy_rigidbody: *Rigidbody = tuple[2];

                const direction = position.subtract(enemy_position.*).normalize().scale(position.subtract(enemy_position.*).length() - enemy.follow_distance);

                if (1.0 < enemy_position.distance(enemy_position.add(direction))) {
                    const movement = direction.normalize().scale(enemy.follow_speed);
                    enemy_rigidbody.velocity.x = movement.x;
                    enemy_rigidbody.velocity.z = movement.z;
                } else {
                    enemy_rigidbody.velocity.x = 0;
                    enemy_rigidbody.velocity.z = 0;
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
        if (ecs_engine.entityHas(collision.body1, Grounded) and 0.9 < physics.sbVsRb_infos.items[i].normal.dot(math.f32.Vector3.up)) {
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
        if (ecs_engine.entityHas(collision.body1, Grounded) and 0.9 < physics.rbVsRb_infos.items[i].normal.dot(math.f32.Vector3.up)) {
            const grounded = ecs_engine.getEntityComponent(collision.body1, Grounded) catch unreachable;
            grounded.grounded = true;
        }

        if (ecs_engine.entityHas(collision.body2, Grounded) and 0.9 < physics.rbVsRb_infos.items[i].normal.negate().dot(math.f32.Vector3.up)) {
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

    var movement_input: math.f32.Vector3 = .zero;
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
