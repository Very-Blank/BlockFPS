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

const Health = @import("components/Health.zig");
const Damage = @import("components/Damage.zig");
const LifeTime = @import("components/LifeTime.zig");

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

    ecs_engine.setArchetypeInitCapcacity(ecs.Template{ .components = &.{
        Position,
        Scale,
        Rotation,
        ModelInstance,
        Collider,
        Rigidbody,
    } }, 100);

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
        Health{ .current = 50.0, .max = 50.0 },
        Position{ .y = 2.5 },
        Scale.one,
        Rotation.identity,
        Model.init(Model.cube),
        Collider{ .box = .one },
        Rigidbody{ .velocity = .{ .y = -0.5 }, .restitution = 0.5, .mass = 10.0 },
    }, &.{});

    _ = ecs_engine.createEntity(.{
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
        Rigidbody{ .mass = 5.0 },
        Collider{ .capsule = .{ .radius = 0.5, .length = 2 } },
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

        physics.update(delta_time, &ecs_engine);

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
                    .camera = ecs_engine.getEntityComponent(id, Camera) catch unreachable,
                };

                if (!ignore_input) {
                    var grounded = false;

                    for (physics.collisions.items, 0..) |collision, i| {
                        if (collision.body1.eql(id) and 0.9 < physics.infos.items[i].normal.dot(math.f32.Vector3.up)) grounded = true;
                        if (collision.body2.eql(id) and 0.9 < physics.infos.items[i].normal.negate().dot(math.f32.Vector3.up)) grounded = true;

                        if (ecs_engine.entityHas(collision.body1, Health) and ecs_engine.entityHas(collision.body2, Damage)) {
                            const health = ecs_engine.getEntityComponent(collision.body1, Health) catch unreachable;
                            const damage = ecs_engine.getEntityComponent(collision.body2, Damage) catch unreachable;
                            health.current -= damage.damage;
                        }

                        if (ecs_engine.entityHas(collision.body2, Health) and ecs_engine.entityHas(collision.body1, Damage)) {
                            const health = ecs_engine.getEntityComponent(collision.body2, Health) catch unreachable;
                            const damage = ecs_engine.getEntityComponent(collision.body1, Damage) catch unreachable;
                            health.current -= damage.damage;
                        }
                    }

                    handlePlayerInput(&window, player, grounded, delta_time);

                    if (window.input.mouse_state.left_click == .justPressed) {
                        const forward = math.f32.Vector3.forward
                            .rotateAroundAxis(.x, player.camera.rotation.pitch)
                            .rotateAroundAxis(.y, player.camera.rotation.yaw)
                            .normalize()
                            .negate();

                        _ = ecs_engine.createEntity(.{
                            LifeTime{ .duration = 5.0 },
                            Damage{ .damage = 10 },
                            player.position.add(forward),
                            Scale{ .x = 0.1, .y = 0.1, .z = 0.1 },
                            Rotation.identity,
                            ModelInstance.cube,
                            Collider{ .sphere = .{ .radius = 0.1 } },
                            Rigidbody{ .velocity = forward.scale(20.0), .gravity = -0.5, .restitution = 1.5, .mass = 0.1 },
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

        render: {
            var tuple_iterator = if (ecs_engine.getTupleIterator(.{
                .include = ecs.Template{ .components = &.{ Position, Scale, Rotation, Model } },
            })) |tuple_iterator| tuple_iterator else break :render;

            rendering.startRender();

            glad.glUniformMatrix4fv(rendering.program.getUniform("view"), 1, glad.GL_FALSE, &view_matrix.fields[0][0]);
            glad.glUniformMatrix4fv(rendering.program.getUniform("projection"), 1, glad.GL_FALSE, &projection_matrix.fields[0][0]);

            rendering.drawModels(&tuple_iterator);
        }

        render: {
            var tuple_iterator = if (ecs_engine.getTupleIterator(.{
                .include = ecs.Template{ .components = &.{ Position, Scale, Rotation, ModelInstance } },
            })) |tuple_iterator| tuple_iterator else break :render;

            rendering.startRender();

            glad.glUniformMatrix4fv(rendering.program.getUniform("view"), 1, glad.GL_FALSE, &view_matrix.fields[0][0]);
            glad.glUniformMatrix4fv(rendering.program.getUniform("projection"), 1, glad.GL_FALSE, &projection_matrix.fields[0][0]);

            rendering.drawIntances(&tuple_iterator);
        }

        destroy: {
            var iterator = if (ecs_engine.getIterator(.{
                .component = Position,
            })) |iterator| iterator else break :destroy;

            while (iterator.next()) |position| {
                if (position.y < -100.0) {
                    ecs_engine.destroyEntity(iterator.getCurrentEntity());
                }
            }
        }

        destroy: {
            var iterator = if (ecs_engine.getIterator(.{
                .component = Health,
            })) |iterator| iterator else break :destroy;

            while (iterator.next()) |health| {
                if (health.current <= 0) {
                    ecs_engine.destroyEntity(iterator.getCurrentEntity());
                }
            }
        }

        destroy: {
            var iterator = if (ecs_engine.getIterator(.{
                .component = LifeTime,
            })) |iterator| iterator else break :destroy;

            while (iterator.next()) |lifetime| {
                lifetime.elapsed += delta_time;
                if (lifetime.duration < lifetime.elapsed) {
                    ecs_engine.destroyEntity(iterator.getCurrentEntity());
                }
            }
        }

        gui.newFrame();

        debug_window.draw();

        gui.render();

        gui.endFrame();

        ecs_engine.clearDestroyedEntitys();
        physics.clear();

        window.swapAndPoll();
    }
}

const Player = struct { position: *Position, rigidbody: *Rigidbody, camera: *Camera };

pub fn handlePlayerInput(window: *Window, player: Player, grounded: bool, delta_time: f32) void {
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

    if (grounded and window.input.getKeyState(.space) == .justPressed) {
        player.rigidbody.velocity.y += 1250 * delta_time;
    }

    // if (window.input.getKeyState(.space).isDown()) {
    //     movement_input.y += 1.0;
    // }
    // if (window.input.getKeyState(.left_control).isDown()) {
    //     movement_input.y -= 1.0;
    // }

    if (movement_input.length() > 0.0) {
        movement_input = movement_input.normalize().rotateAroundAxis(.y, player.camera.rotation.yaw).scale(1000 * delta_time);
        player.rigidbody.velocity.x = movement_input.x;
        player.rigidbody.velocity.z = movement_input.z;
    } else {
        player.rigidbody.velocity.x = 0.0;
        player.rigidbody.velocity.z = 0.0;
    }
}
