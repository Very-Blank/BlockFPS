const std = @import("std");
const glad = @import("glad");
const imgui = @import("imgui");
const ecs = @import("ecs");
const glfw = @import("glfw");
const math = @import("math");

const enemies = @import("enemies.zig");

const Io = std.Io;

const Vector3 = math.f32.Vector3;

const Window = @import("Window.zig");
const DebugGui = @import("DebugGui.zig");
const Assets = @import("Assets.zig");

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
const Pickable = @import("components/pickable.zig").Pickable;

const Enemy = @import("components/Enemy.zig");
const Health = @import("components/Health.zig");
const Bullet = @import("components/Bullet.zig");
const Grounded = @import("components/Grounded.zig");

const Ecs = @import("ecs.zig").Ecs;
const Parent = @import("ecs.zig").Parent;

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

    var assets: Assets = .empty;
    defer assets.deinit(gpa);
    try assets.loadAll(io, gpa);

    var debug_gui = DebugGui.init(window, gpa);
    defer debug_gui.deinit();

    const spawnp_singleton = ecs_engine.createSingleton(.{ .components = &.{Position} });
    const camera_singleton = ecs_engine.createSingleton(.{ .components = &.{ Position, Rotation, Camera } });
    const body_singleton = ecs_engine.createSingleton(.{ .components = &.{ Position, Grounded, Rigidbody } });
    const target = ecs_engine.createSingleton(.{ .components = &.{ Position, Collider } });

    var physics: Physics = .init(gpa);
    defer physics.deinit();

    makeArena(&ecs_engine, 50.0);

    {
        const player_entity = ecs_engine.createEntity(.{
            Health{ .current = 50.0, .max = 50.0 },
            Position{ .x = -5, .z = -5, .y = 1.0 },
            Rigidbody{ .mass = 5.0, .restitution = 0.0 },
            Collider{ .type = .{ .capsule = .{ .radius = 0.25, .half_height = 1 } }, .layer = .player },
            Grounded{ .grounded = false },
        }, &.{});

        ecs_engine.setSingletonsEntity(body_singleton, player_entity) catch unreachable;

        const camera = ecs_engine.createEntity(.{
            Position{ .x = -5, .z = -5, .y = 1.0 },
            Rotation.identity,
            Camera{
                .fov = 90,
                .aspect = @as(f32, @floatFromInt(window.logical.width)) / @as(f32, @floatFromInt(window.logical.height)),
                .near = 0.001,
                .far = 1000,
            },
        }, &.{});

        ecs_engine.setSingletonsEntity(camera_singleton, camera) catch unreachable;

        ecs_engine.createLink("follow", player_entity, camera, Position{ .y = 0.75 }) catch unreachable;
    }

    try ecs_engine.setSingletonsEntity(spawnp_singleton, ecs_engine.createEntity(.{Position{ .x = 2.0, .y = 2.0, .z = 2.0 }}, &.{}));

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

        if (!debug_gui.game.freeze) {
            physics.update(&ecs_engine, delta_time);
            handleCollision(&physics, &ecs_engine);
        }

        if (window.input.getKeyState(.escape) == .justPressed) {
            if (debug_gui.isOpen()) {
                debug_gui.close(&ecs_engine);
            } else {
                ignore_input = true;
                window.setMouseMode(.captured);
                debug_gui.open();
            }
        }

        if (debug_gui.state == .just_closed) {
            ignore_input = false;
            window.setMouseMode(.disabled);
        }

        if (!debug_gui.isOpen()) {
            handlePlayerInput(&ecs_engine, &window, body_singleton, camera_singleton);
            // switch (debug_gui.game.mode) {
            //     .normal => {
            //         handlePlayerInput(&ecs_engine, &window, body_singleton);
            //     },
            //     .cam => {
            //         handleCamInput(&ecs_engine, &window, flycam_singleton, delta_time);
            //     },
            // }
        } else if (ecs_engine.getSingletonsEntity(body_singleton)) |id| {
            const rigidbody = ecs_engine.getEntityComponent(id, Rigidbody) orelse unreachable;
            rigidbody.velocity.x = 0;
            rigidbody.velocity.z = 0;
        }

        {
            const links = ecs_engine.getLinks("follow");
            for (links.data, 0..) |data, i| {
                const src_position = ecs_engine.getEntityComponent(links.sources[i], Position) orelse unreachable;

                const dst_position = ecs_engine.getEntityComponent(links.destinations[i], Position) orelse unreachable;

                dst_position.* = src_position.add(data);
            }
        }

        {
            const links = ecs_engine.getLinks("parent");
            for (links.data, 0..) |data, i| {
                const src = ecs_engine.getEntityComponents(links.sources[i], &.{ Position, Rotation }) orelse unreachable;
                const src_position: *Position = src[0];
                const src_rotation: *Rotation = src[1];

                const dst = ecs_engine.getEntityComponents(links.destinations[i], &.{ Position, Rotation }) orelse unreachable;
                const dst_position: *Position = dst[0];
                const dst_rotation: *Rotation = dst[1];

                dst_position.* = src_position.add(data.position.rotate(src_rotation.*));
                dst_rotation.* = src_rotation.multiply(data.rotation);
            }
        }

        // switch (debug_gui.game.mode) {
        //     .normal => {
        //         if (ecs_engine.getSingletonsEntity(body_singleton)) |id| {
        //             ecs_engine.setSingletonsEntity(camera_singleton, id) catch unreachable;
        //         }
        //     },
        //     .cam => {
        //         if (ecs_engine.getSingletonsEntity(flycam_singleton)) |id| {
        //             ecs_engine.setSingletonsEntity(camera_singleton, id) catch unreachable;
        //         }
        //     },
        // }
        //
        if (!debug_gui.game.freeze)
            enemies.update(&ecs_engine, target, random, delta_time);

        update_aspect: {
            var iterator = ecs_engine.getIterator(.{ .component = Camera }) orelse break :update_aspect;

            const aspect: f32 = @as(f32, @floatFromInt(window.logical.width)) / @as(f32, @floatFromInt(window.logical.height));

            while (iterator.next()) |camera| {
                camera.aspect = aspect;
            }
        }

        rendering.render(&ecs_engine, camera_singleton);

        try debug_gui.update(&ecs_engine, &window, &assets, camera_singleton);

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

        if (!debug_gui.game.freeze) {
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
                        std.debug.print("{any}\n", .{iterator.getCurrentEntity()});
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

// pub fn respawn(
//     ecs_engine: *Ecs,
//     window: *Window,
//     player_singleton: SingletonType,
//     camera_singleton: SingletonType,
//     spawnp_singleton: SingletonType,
//     target: SingletonType,
// ) void {
//     const spawn_point: Position = (ecs_engine.getEntityComponent(
//         ecs_engine.getSingletonsEntity(spawnp_singleton) orelse return,
//         Position,
//     ) orelse return).*;
//
//     if (ecs_engine.getSingletonsEntity(player_singleton) == null) {
//         const player_entity = ecs_engine.createEntity(.{
//             Health{ .current = 50.0, .max = 50.0 },
//             spawn_point,
//             Rigidbody{ .mass = 5.0, .restitution = 0.0 },
//             Collider{ .type = .{ .capsule = .{ .radius = 0.25, .half_height = 1 } }, .layer = .player },
//             Grounded{ .grounded = false },
//             Camera{
//                 .offset = 0.75,
//                 .projection = .{
//                     .mat = .initPerspective(90.0, @as(f32, @floatFromInt(window.logical.width)) / @as(f32, @floatFromInt(window.logical.height)), 1000.0, 0.001),
//                     .far = 1000.0,
//                     .near = 0.001,
//                     .fov = 90,
//                 },
//                 .rotation = .{ .pitch = 0.0, .yaw = 0.0 },
//             },
//         }, &.{});
//
//         ecs_engine.setSingletonsEntity(player_singleton, player_entity) catch unreachable;
//         ecs_engine.setSingletonsEntity(target, player_entity) catch unreachable;
//     }
// }

pub fn handleCollision(physics: *Physics, ecs_engine: *Ecs) void {
    for (physics.sbVsRb_collisions.items, 0..) |collision, i| {
        grounded: {
            if (physics.sbVsRb_infos.items[i].normal.dot(Vector3.up) < 0.9) break :grounded;
            (ecs_engine.getEntityComponent(collision.body1, Grounded) orelse break :grounded).grounded = true;
        }

        bullet: {
            const bullet = ecs_engine.getEntityComponent(collision.body1, Bullet) orelse break :bullet;
            if (bullet.max_deflection_angle < -physics.sbVsRb_infos.items[i].angle) {
                ecs_engine.destroyEntity(collision.body1);
            }
        }
    }

    for (physics.rbVsRb_collisions.items, 0..) |collision, i| {
        inline for (.{ .{ .self = "body1", .other = "body2" }, .{ .self = "body2", .other = "body1" } }) |fields| {
            grounded: {
                if (physics.rbVsRb_infos.items[i].normal.dot(Vector3.up) < 0.9) break :grounded;
                (ecs_engine.getEntityComponent(@field(collision, fields.self), Grounded) orelse break :grounded).grounded = true;
            }

            grounded: {
                if (physics.rbVsRb_infos.items[i].normal.negate().dot(Vector3.up) < 0.9) break :grounded;
                (ecs_engine.getEntityComponent(@field(collision, fields.other), Grounded) orelse break :grounded).grounded = true;
            }

            bullet: {
                const bullet = ecs_engine.getEntityComponent(@field(collision, fields.self), Bullet) orelse break :bullet;
                vision: {
                    (ecs_engine.getEntityComponent(@field(collision, fields.other), Enemy) orelse break :vision).vision.memory.reset();
                }

                health: {
                    (ecs_engine.getEntityComponent(@field(collision, fields.other), Health) orelse break :health).current -= bullet.damage;
                }

                ecs_engine.destroyEntity(@field(collision, fields.self));
            }
        }
    }

    physics.clear();
}

pub fn handleCamInput(ecs_engine: *Ecs, window: *Window, cam_singleton: SingletonType, delta_time: f32) void {
    if (ecs_engine.getSingletonsEntity(cam_singleton)) |id| {
        const position = ecs_engine.getEntityComponent(id, Position) orelse unreachable;
        const camera = ecs_engine.getEntityComponent(id, Camera) orelse unreachable;

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

pub fn handlePlayerInput(ecs_engine: *Ecs, window: *Window, player_singleton: SingletonType, camera_singleton: SingletonType) void {
    const player_entity = ecs_engine.getSingletonsEntity(player_singleton) orelse return;
    const camera_entity = ecs_engine.getSingletonsEntity(camera_singleton) orelse return;

    const rigidbody = ecs_engine.getEntityComponent(player_entity, Rigidbody) orelse unreachable;
    const grounded = ecs_engine.getEntityComponent(player_entity, Grounded) orelse unreachable;

    const camera_rotation = ecs_engine.getEntityComponent(camera_entity, Rotation) orelse unreachable;
    const camera_position = ecs_engine.getEntityComponent(camera_entity, Position) orelse unreachable;

    camera_rotation.* = camera_rotation
        .multiply(Rotation.initFromRadians(.x, -window.input.mouse_state.motion.y / 1000.0))
        .addAroundAxis(.y, -window.input.mouse_state.motion.x / 1000.0);

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
        movement_input = movement_input
            .normalize()
            .rotateAroundAxis(
                .y,
                2.0 * std.math.atan2(
                    camera_rotation.fields[2],
                    camera_rotation.fields[0],
                ),
            )
            .scale(if (window.input.getKeyState(.left_shift).isDown()) 10 else 4);
        rigidbody.velocity.x = movement_input.x;
        rigidbody.velocity.z = movement_input.z;
    } else {
        rigidbody.velocity.x = 0.0;
        rigidbody.velocity.z = 0.0;
    }

    const forward = Vector3.forward.negate().rotate(camera_rotation.*);

    if (window.input.getKeyState(.f) == .justPressed)
        if (Physics.raycast(
            ecs_engine,
            camera_position.coerce(Vector3),
            forward,
            200.0,
            Mask.all.remove(&.{.player}),
        )) |hit|
            if (ecs_engine.entityHas(hit.body, Pickable)) {
                ecs_engine.createLink(
                    "parent",
                    camera_entity,
                    hit.body,
                    Parent{
                        .position = Position{ .z = -1.5, .y = -0.3, .x = 0.1 },
                        .rotation = Rotation.identity,
                    },
                ) catch unreachable;
            };

    if (window.input.mouse_state.left_click == .justPressed) {
        _ = ecs_engine.createEntity(.{
            Bullet{ .damage = 10, .duration = 3.0, .max_deflection_angle = 0.85 },
            camera_position.*,
            Scale{ .x = 0.1, .y = 0.1, .z = 0.1 },
            Rotation.identity,
            Model{},
            Collider{ .type = .{ .sphere = .{ .radius = 0.1 } } },
            Rigidbody{ .velocity = forward.scale(50.0), .gravity = 0.0, .restitution = 0.0, .mass = 0.1 },
        }, &.{});
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
        Model{},
        Collider{ .type = .{ .box = .{ .x = size, .y = 0.5, .z = size } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = 0, .y = wall_height / 2.0 - 0.5, .z = -wall_offset },
        Scale{ .x = size, .y = wall_height, .z = wall_thickness },
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .{ .x = size, .y = wall_height, .z = wall_thickness } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = 0, .y = wall_height / 2.0 - 0.5, .z = wall_offset },
        Scale{ .x = size, .y = wall_height, .z = wall_thickness },
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .{ .x = size, .y = wall_height, .z = wall_thickness } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = -wall_offset, .y = wall_height / 2.0 - 0.5, .z = 0 },
        Scale{ .x = wall_thickness, .y = wall_height, .z = size },
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .{ .x = wall_thickness, .y = wall_height, .z = size } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = wall_offset, .y = wall_height / 2.0 - 0.5, .z = 0 },
        Scale{ .x = wall_thickness, .y = wall_height, .z = size },
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .{ .x = wall_thickness, .y = wall_height, .z = size } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .x = 10, .y = wall_height / 2.0 - 0.5, .z = 8 },
        Scale{ .x = wall_thickness, .y = wall_height, .z = 10 },
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .{ .x = wall_thickness, .y = 3.0, .z = 10 } } },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position{ .y = 2.5 },
        Scale.one,
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .one } },
        Rigidbody{ .velocity = .{ .y = -0.5 }, .restitution = 0.5, .mass = 10.0 },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position.zero,
        Scale{ .x = 1.5, .y = 1.5, .z = 1.5 },
        Rotation.identity,
        Model{ .type = .monkey },
        Collider{ .type = .{ .box = .{ .x = 2.5, .y = 2.5, .z = 2.5 } } },
        Rigidbody{ .restitution = 0.5, .mass = 10.0 },
    }, &.{});

    _ = ecs_engine.createEntity(.{
        Position.one.scale(5.0),
        Scale{ .x = 0.4, .y = 0.4, .z = 0.4 },
        Rotation.identity,
        Model{ .type = .cube },
        Collider{ .type = .{ .box = .{ .x = 0.4, .y = 0.4, .z = 0.4 } } },
        Rigidbody{ .restitution = 0.5, .mass = 10.0 },
    }, &.{Pickable});

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
    //     Model{},
    //     Collider{ .type = .{ .capsule = .{ .radius = 0.5, .half_height = 1 } }, .layer = .enemy },
    //     Rigidbody{ .restitution = 0.0, .mass = 5.0 },
    //     Grounded{ .grounded = false },
    // }, &.{});
    //
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
    //                     .{ .x = 0, .y = 1, .z = 9 },
    //                     .{ .x = 8, .y = 1, .z = -4 },
    //                     .{ .x = -8, .y = 1, .z = -8 },
    //                     .{ .x = 5, .y = 1, .z = -8 },
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
    //                 .distance = .{ .current = 5.0, .min = 4.0, .max = 15.0, .change = .init(1.5, .finished) },
    //             },
    //             .weapon = .{
    //                 .type = .{ .burst = .{ .length = .init(0.5, .running), .rpm = .init(0.1, .running) } },
    //                 .cooldown = .init(1.5, .running),
    //                 .bullet = .{ .speed = 50.0, .damage = 0.0 },
    //             },
    //             .jump = .{ .force = 6.0, .cooldown = .init(4.0, .running) },
    //             .strafe = .{ .speed = 10.0, .change = .init(1.2, .running) },
    //         },
    //     },
    //     Health{ .current = 50.0, .max = 50.0 },
    //     Position{ .y = 1.5, .z = 5, .x = 5 },
    //     Scale{ .x = 1.0, .y = 2.0, .z = 1.0 },
    //     Rotation.identity,
    //     Model{},
    //     Collider{ .type = .{ .capsule = .{ .radius = 0.5, .half_height = 1 } }, .layer = .enemy },
    //     Rigidbody{ .restitution = 0.0, .mass = 5.0 },
    //     Grounded{ .grounded = false },
    // }, &.{});
}

test "tests" {
    _ = @import("json.zig");
}
