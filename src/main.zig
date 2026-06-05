const std = @import("std");
const glad = @import("glad");
const imgui = @import("imgui");
const ecs = @import("ecs");
const glfw = @import("glfw");
const math = @import("math");

const json = @import("json.zig");

const enemies = @import("enemies.zig");

const Io = std.Io;

const Vector3 = math.f32.Vector3;

const Window = @import("Window.zig");
const DebugGui = @import("DebugGui.zig");

const Shader = @import("Shader.zig");
const Program = @import("Program.zig");

const Rendering = @import("Rendering.zig");
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
const Template = ecs.Template;
const SingletonType = ecs.SingletonType;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    var prng: std.Random.DefaultPrng = .init(blk: {
        var seed: u64 = undefined;
        io.random(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const random: std.Random = prng.random();

    var window = try Window.init("Game", 100, 100);
    defer window.deinit();

    window.setCallbacks();
    window.sync(); // NOTE: We missed some window callbacks so we need to sync.
    window.setMouseMode(.disabled);

    const rendering: Rendering = try .init(io, gpa);
    defer rendering.deinit();

    const buffer: []u8 = try gpa.alloc(u8, 4_000_000);
    defer gpa.free(buffer);
    var fba: std.heap.FixedBufferAllocator = .init(buffer);
    var ecs_engine: Ecs = try .init(fba.allocator());
    defer ecs_engine.deinit();

    var debug_gui = DebugGui.init(window);
    defer debug_gui.deinit();

    const main_camera_singleton = ecs_engine.createSingleton(.{ .components = &.{ Position, Camera } });
    const player_singleton = ecs_engine.createSingleton(.{ .components = &.{ Position, Rigidbody, Grounded, Camera } });
    const cam_singleton = ecs_engine.createSingleton(.{ .components = &.{ Position, Camera } });

    const target = ecs_engine.createSingleton(.{ .components = &.{ Position, Collider } });

    var physics: Physics = .init(gpa);
    defer physics.deinit();

    makeArena(&ecs_engine, 50.0);

    const cam_entity = ecs_engine.createEntity(.{
        Position{ .x = -3, .y = 1.1 },
        Camera{
            .offset = 0.75,
            .projection = .{
                .mat = .initPerspective(90.0, @as(f32, @floatFromInt(window.logical.width)) / @as(f32, @floatFromInt(window.logical.height)), 1000.0, 0.001),
                .far = 1000.0,
                .near = 0.001,
                .fov = 90,
            },
            .rotation = .{ .pitch = 0.0, .yaw = 0.0 },
        },
    }, &.{});

    ecs_engine.setSingletonsEntity(cam_singleton, cam_entity) catch unreachable;

    const player_entity = ecs_engine.createEntity(.{
        Health{ .current = 50.0, .max = 50.0 },
        Position{ .x = -3, .y = 1.1 },
        Rigidbody{ .mass = 5.0, .restitution = 0.0 },
        Collider{ .type = .{ .capsule = .{ .radius = 0.25, .half_height = 1 } }, .layer = .player },
        Grounded{ .grounded = false },
        Camera{
            .offset = 0.75,
            .projection = .{
                .mat = .initPerspective(90.0, @as(f32, @floatFromInt(window.logical.width)) / @as(f32, @floatFromInt(window.logical.height)), 1000.0, 0.001),
                .far = 1000.0,
                .near = 0.001,
                .fov = 90,
            },
            .rotation = .{ .pitch = 0.0, .yaw = 0.0 },
        },
    }, &.{});

    ecs_engine.setSingletonsEntity(main_camera_singleton, player_entity) catch unreachable;
    ecs_engine.setSingletonsEntity(player_singleton, player_entity) catch unreachable;
    ecs_engine.setSingletonsEntity(target, player_entity) catch unreachable;

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

        if (!debug_gui.launcher.data.game.freeze) {
            physics.update(&ecs_engine, delta_time);
            handleCollision(&physics, &ecs_engine);
        }

        if (window.input.getKeyState(.escape) == .justPressed) {
            if (debug_gui.state.isOpen()) {
                debug_gui.close();
            } else {
                ignore_input = true;
                window.setMouseMode(.captured);
                debug_gui.open();
            }
        }

        if (debug_gui.state == .just_closed) {
            ignore_input = false;
            window.setMouseMode(.disabled);
            ecs_engine.clearSingletonsEntity(debug_gui.selection.singleton);
        }

        if (!debug_gui.state.isOpen()) {
            switch (debug_gui.launcher.data.game.mode) {
                .normal => {
                    handlePlayerInput(&ecs_engine, &window, player_singleton);
                },
                .cam => {
                    handleCamInput(&ecs_engine, &window, cam_singleton, delta_time);
                },
            }
        } else if (ecs_engine.getSingletonsEntity(player_singleton)) |id| {
            const rigidbody = ecs_engine.getEntityComponent(id, Rigidbody) catch unreachable;
            rigidbody.velocity.x = 0;
            rigidbody.velocity.z = 0;
        }

        switch (debug_gui.launcher.data.game.mode) {
            .normal => {
                if (ecs_engine.getSingletonsEntity(player_singleton)) |id| {
                    ecs_engine.setSingletonsEntity(main_camera_singleton, id) catch unreachable;
                }
            },
            .cam => {
                if (ecs_engine.getSingletonsEntity(cam_singleton)) |id| {
                    ecs_engine.setSingletonsEntity(main_camera_singleton, id) catch unreachable;
                }
            },
        }

        if (!debug_gui.launcher.data.game.freeze)
            enemies.update(&ecs_engine, target, random, delta_time);

        rendering.render(&ecs_engine, main_camera_singleton);

        debug_gui.update(&ecs_engine, &window, main_camera_singleton);

        update_view: {
            var iterator = ecs_engine.getIterator(.{ .component = Camera }) orelse break :update_view;

            const aspect: f32 = @as(f32, @floatFromInt(window.logical.width)) / @as(f32, @floatFromInt(window.logical.height));

            while (iterator.next()) |camera| {
                camera.updateView(aspect);
            }
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

        if (!debug_gui.launcher.data.game.freeze) {
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
        }

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
        inline for (.{ .{ .self = "body1", .other = "body2" }, .{ .self = "body2", .other = "body1" } }) |fields| {
            if (ecs_engine.entityHas(@field(collision, fields.self), Grounded) and 0.9 < physics.rbVsRb_infos.items[i].normal.dot(Vector3.up)) {
                const grounded = ecs_engine.getEntityComponent(@field(collision, fields.self), Grounded) catch unreachable;
                grounded.grounded = true;
            }

            if (ecs_engine.entityHas(@field(collision, fields.self), Bullet)) {
                const bullet = ecs_engine.getEntityComponent(@field(collision, fields.self), Bullet) catch unreachable;
                if (ecs_engine.entityHas(@field(collision, fields.other), Enemy)) {
                    const enemy = ecs_engine.getEntityComponent(@field(collision, fields.other), Enemy) catch unreachable;
                    enemy.vision.memory.reset();
                }

                if (ecs_engine.entityHas(@field(collision, fields.other), Health)) {
                    const health = ecs_engine.getEntityComponent(@field(collision, fields.other), Health) catch unreachable;
                    health.current -= bullet.damage;
                }

                ecs_engine.destroyEntity(@field(collision, fields.self));
            }
        }
    }

    physics.clear();
}

pub fn handleCamInput(ecs_engine: *Ecs, window: *Window, cam_singleton: SingletonType, delta_time: f32) void {
    if (ecs_engine.getSingletonsEntity(cam_singleton)) |id| {
        const position = ecs_engine.getEntityComponent(id, Position) catch unreachable;
        const camera = ecs_engine.getEntityComponent(id, Camera) catch unreachable;

        camera.rotation.yaw -= window.input.mouse_state.motion.x / 1000.0;
        camera.rotation.pitch -= window.input.mouse_state.motion.y / 1000.0;

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

        if (window.input.getKeyState(.space).isDown()) {
            movement_input.y += 1.0;
        }

        if (window.input.getKeyState(.left_control).isDown()) {
            movement_input.y -= 1.0;
        }

        if (movement_input.length() > 0.0) {
            position.* = position.add(
                movement_input
                    .normalize()
                    .rotateAroundAxis(.y, camera.rotation.yaw)
                    .scale(if (window.input.getKeyState(.left_shift).isDown()) 25 else 10)
                    .scale(delta_time),
            );
        }
    }
}

pub fn handlePlayerInput(ecs_engine: *Ecs, window: *Window, player_singleton: SingletonType) void {
    if (ecs_engine.getSingletonsEntity(player_singleton)) |id| {
        const position = ecs_engine.getEntityComponent(id, Position) catch unreachable;
        const rigidbody = ecs_engine.getEntityComponent(id, Rigidbody) catch unreachable;
        const grounded = ecs_engine.getEntityComponent(id, Grounded) catch unreachable;
        const camera = ecs_engine.getEntityComponent(id, Camera) catch unreachable;

        camera.rotation.yaw -= window.input.mouse_state.motion.x / 1000.0;
        camera.rotation.pitch -= window.input.mouse_state.motion.y / 1000.0;

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

        if (grounded.grounded and window.input.getKeyState(.space) == .justPressed) {
            rigidbody.velocity.y += 5;
        }

        if (movement_input.length() > 0.0) {
            movement_input = movement_input.normalize().rotateAroundAxis(.y, camera.rotation.yaw).scale(if (window.input.getKeyState(.left_shift).isDown()) 10 else 4);
            rigidbody.velocity.x = movement_input.x;
            rigidbody.velocity.z = movement_input.z;
        } else {
            rigidbody.velocity.x = 0.0;
            rigidbody.velocity.z = 0.0;
        }

        if (window.input.mouse_state.left_click == .justPressed) {
            const forward = Vector3.forward
                .rotateAroundAxis(.x, camera.rotation.pitch)
                .rotateAroundAxis(.y, camera.rotation.yaw)
                .normalize()
                .negate();

            _ = ecs_engine.createEntity(.{
                Bullet{ .damage = 10, .duration = 3.0, .max_deflection_angle = 0.85 },
                position.add(forward).add(Position{ .y = camera.offset }),
                Scale{ .x = 0.1, .y = 0.1, .z = 0.1 },
                Rotation.identity,
                Model.cube,
                Collider{ .type = .{ .sphere = .{ .radius = 0.5 } } },
                Rigidbody{ .velocity = forward.scale(50.0), .gravity = 0.0, .restitution = 0.0, .mass = 0.1 },
            }, &.{});
        }
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
        Model.cube,
        Collider{ .type = .{ .box = .{ .x = size, .y = 0.5, .z = size } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = 0, .y = wall_height / 2.0 - 0.5, .z = -wall_offset },
        Scale{ .x = size, .y = wall_height, .z = wall_thickness },
        Rotation.identity,
        Model.cube,
        Collider{ .type = .{ .box = .{ .x = size, .y = wall_height, .z = wall_thickness } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = 0, .y = wall_height / 2.0 - 0.5, .z = wall_offset },
        Scale{ .x = size, .y = wall_height, .z = wall_thickness },
        Rotation.identity,
        Model.cube,
        Collider{ .type = .{ .box = .{ .x = size, .y = wall_height, .z = wall_thickness } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = -wall_offset, .y = wall_height / 2.0 - 0.5, .z = 0 },
        Scale{ .x = wall_thickness, .y = wall_height, .z = size },
        Rotation.identity,
        Model.cube,
        Collider{ .type = .{ .box = .{ .x = wall_thickness, .y = wall_height, .z = size } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = wall_offset, .y = wall_height / 2.0 - 0.5, .z = 0 },
        Scale{ .x = wall_thickness, .y = wall_height, .z = size },
        Rotation.identity,
        Model.cube,
        Collider{ .type = .{ .box = .{ .x = wall_thickness, .y = wall_height, .z = size } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = 10, .y = wall_height / 2.0 - 0.5, .z = 8 },
        Scale{ .x = wall_thickness, .y = wall_height, .z = 10 },
        Rotation.identity,
        Model.cube,
        Collider{ .type = .{ .box = .{ .x = wall_thickness, .y = 3.0, .z = 10 } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .y = 2.5 },
        Scale.one,
        Rotation.identity,
        Model.cube,
        Collider{ .type = .{ .box = .one } },
        Rigidbody{ .velocity = .{ .y = -0.5 }, .restitution = 0.5, .mass = 10.0 },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model.cube,
        Collider{ .type = .{ .box = .one } },
        Rigidbody{ .restitution = 0.5, .mass = 10.0 },
    }, &.{});

    // _ = ecs_engine.createEntity(.{
    //     Enemy{
    //         .state = .patrol,
    //         .vision = .{
    //             .memory = .init(5.0, .finished),
    //             .distance = 30.0,
    //             .angle = std.math.pi / 2.0,
    //         },
    //         .follow = .{ .accuracy = 0.3, .distance = 6.0, .speed = 4.5 },
    //         .patrol = .{
    //             .path = .{
    //                 .waypoints = .{
    //                     .{ .x = 0, .y = 1, .z = 5 },
    //                     .{ .x = 8, .y = 1, .z = 3 },
    //                     .{ .x = -8, .y = 1, .z = 8 },
    //                     .{ .x = 5, .y = 1, .z = 8 },
    //                 },
    //             },
    //             .wait = .init(1.5, .running),
    //             .accuracy = 0.5,
    //             .speed = 2.0,
    //         },
    //         .attack = .{
    //             .range = 20.0,
    //             .move = .{
    //                 .speed = 7.0,
    //                 .distance = .{ .current = 5.0, .min = 10.0, .max = 15.0, .change = .init(1.5, .finished) },
    //             },
    //             .weapon = .{
    //                 .type = .single,
    //                 .cooldown = .init(1.5, .running),
    //                 .bullet = .{ .speed = 80.0, .damage = 25.0 },
    //             },
    //             .jump = .{ .force = 4.0, .cooldown = .init(5.0, .running) },
    //             .strafe = .{ .speed = 5.0, .change = .init(1.2, .running) },
    //         },
    //     },
    //     Health{ .current = 50.0, .max = 50.0 },
    //     Position{ .y = 1.5, .z = 3 },
    //     Scale{ .x = 1.0, .y = 2.0, .z = 1.0 },
    //     Rotation.identity,
    //     Model.cube,
    //     Collider{ .type = .{ .capsule = .{ .radius = 0.5, .half_height = 1 } }, .layer = .enemy },
    //     Rigidbody{ .restitution = 0.0, .mass = 5.0 },
    //     Grounded{ .grounded = false },
    // }, &.{});
    //
    _ = ecs_engine.createEntity(.{
        Enemy{
            .state = .patrol,
            .vision = .{
                .memory = .init(5.0, .finished),
                .distance = 30.0,
                .angle = std.math.pi / 2.0,
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
                .wait = .init(1.5, .running),
                .accuracy = 0.5,
                .speed = 2.0,
            },
            .attack = .{
                .range = 20.0,
                .move = .{
                    .speed = 7.0,
                    .distance = .{ .current = 5.0, .min = 4.0, .max = 15.0, .change = .init(1.5, .finished) },
                },
                .weapon = .{
                    .type = .{ .burst = .{ .length = .init(0.5, .running), .rpm = .init(0.1, .running) } },
                    .cooldown = .init(1.5, .running),
                    .bullet = .{ .speed = 50.0, .damage = 0.0 },
                },
                .jump = .{ .force = 6.0, .cooldown = .init(4.0, .running) },
                .strafe = .{ .speed = 10.0, .change = .init(1.2, .running) },
            },
        },
        Health{ .current = 50.0, .max = 50.0 },
        Position{ .y = 1.5, .z = 5, .x = 5 },
        Scale{ .x = 1.0, .y = 2.0, .z = 1.0 },
        Rotation.identity,
        Model.cube,
        Collider{ .type = .{ .capsule = .{ .radius = 0.5, .half_height = 1 } }, .layer = .enemy },
        Rigidbody{ .restitution = 0.0, .mass = 5.0 },
        Grounded{ .grounded = false },
    }, &.{});
}
