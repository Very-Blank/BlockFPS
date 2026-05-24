const std = @import("std");
const glad = @import("glad");
const imgui = @import("imgui");
const ecs = @import("ecs");
const glfw = @import("glfw");
const math = @import("math");

const Io = std.Io;

const Window = @import("Window.zig");

const Shader = @import("Shader.zig");
const Program = @import("Program.zig");

const Rendering = @import("Rendering.zig");

const Model = @import("components/Model.zig");
const Position = @import("components/position.zig").Position;
const Rotation = @import("components/rotation.zig").Rotation;
const Scale = @import("components/scale.zig").Scale;
const Camera = @import("components/Camera.zig");

const Ecs = @import("ecs.zig").Ecs;
const Template = ecs.Template;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var window = try Window.init("Game", 100, 100);
    defer window.deinit();

    window.setCallbacks();
    window.sync(); // NOTE: We missed some window callbacks so we need to sync.
    //
    _ = imgui.ImGui_CreateContext(null);
    defer imgui.ImGui_DestroyContext(null);

    _ = imgui.cImGui_ImplOpenGL3_Init();
    defer imgui.cImGui_ImplOpenGL3_Shutdown();
    _ = imgui.cImGui_ImplGlfw_InitForOpenGL(@ptrCast(window.ptr), false);
    defer imgui.cImGui_ImplGlfw_Shutdown();

    imgui.ImGui_StyleColorsDark(null);
    const imgui_io: *imgui.struct_ImGuiIO_t = imgui.ImGui_GetIO();

    // // 4. Init backends (after context, before loop)
    // _ = imgui.ImGui_ImplGlfw_InitForOpenGL(window, true);
    // _ = imgui.ImGui(window, true);
    // _ = imgui._impl_opengl3.ImGui_ImplOpenGL3_Init("#version 460");

    const rendering: Rendering = try .init(io, gpa);
    defer rendering.deinit();

    var ecs_engine: Ecs = .init(gpa);
    defer ecs_engine.deinit();

    const player_singleton = ecs_engine.createSingleton(.{ .components = &.{ Position, Camera } });

    _ = ecs_engine.createEntity(.{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model.init(Model.cube),
    }, &.{});

    const player_entity = ecs_engine.createEntity(.{
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
        Position.zero,
    }, &.{});

    ecs_engine.setSingletonsEntity(player_singleton, player_entity) catch unreachable;

    var lapsed_time: f64 = 0.0;

    while (window.run()) {
        glad.glClear(glad.GL_COLOR_BUFFER_BIT | glad.GL_DEPTH_BUFFER_BIT);
        glad.glClearColor(66.0 / 245.0, 161.0 / 245.0, 245 / 245.0, 1.0);

        const delta_time: f32 = outer: {
            const delta_time: f64 = glfw.glfwGetTime() - lapsed_time;
            lapsed_time += delta_time;

            break :outer @floatCast(delta_time);
        };

        update_view: {
            var iterator = ecs_engine.getIterator(.{ .component = Camera }) orelse break :update_view;

            const aspect: f32 = @as(f32, @floatFromInt(window.width)) / @as(f32, @floatFromInt(window.height));

            while (iterator.next()) |camera| {
                camera.updateView(aspect);
            }
        }

        var view_matrix, var projection_matrix = init: {
            if (ecs_engine.getSingletonsEntity(player_singleton)) |player| {
                const player_position = ecs_engine.getEntityComponent(player, Position) catch unreachable;
                const player_camera = ecs_engine.getEntityComponent(player, Camera) catch unreachable;

                handlePlayerInput(&window, .{
                    .position = player_position,
                    .camera = player_camera,
                }, delta_time);

                break :init .{
                    math.f32.Mat4.initView(
                        player_position.negate(),
                        math.f32.Quaternion.initCamRotation(
                            -player_camera.rotation.yaw,
                            -player_camera.rotation.pitch,
                        ),
                    ),
                    player_camera.view,
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

            rendering.draw(&tuple_iterator);
        }

        renderUI(imgui_io);

        window.swapAndPoll();
    }

    // const arena: std.mem.Allocator = init.arena.allocator();
    //
    // const args = try init.minimal.args.toSlice(arena);
    // for (args) |arg| {
    //     std.log.info("arg: {s}", .{arg});
    // }
    //
    // const io = init.io;
}

fn renderUI(_: *imgui.struct_ImGuiIO_t) void {
    // imgui_io.DisplaySize.x = 1920;
    // imgui_io.DisplaySize.y = 1080;
    // imgui_io.DeltaTime = 1.0 / 60.0;

    // 1. Start a new ImGui frame
    imgui.cImGui_ImplOpenGL3_NewFrame();
    imgui.cImGui_ImplGlfw_NewFrame();
    imgui.ImGui_NewFrame();

    // 2. Begin a window
    _ = imgui.ImGui_Begin("My First Window", null, 0);

    // --- Text ---
    imgui.ImGui_Text("Hello from ImGui + Zig!");
    imgui.ImGui_TextColored(.{ .x = 1.0, .y = 0.4, .z = 0.4, .w = 1.0 }, "This text is colored!");
    imgui.ImGui_Separator();

    // --- Buttons ---
    if (imgui.ImGui_Button("Click Me")) {
        std.debug.print("Button clicked!\n", .{});
    }

    imgui.ImGui_SameLine();

    if (imgui.ImGui_ButtonEx("Other Button", .{ .x = 120, .y = 30 })) {
        std.debug.print("Other button clicked!\n", .{});
    }

    imgui.ImGui_End();

    imgui.ImGui_Render();

    imgui.cImGui_ImplOpenGL3_RenderDrawData(imgui.ImGui_GetDrawData());
}

pub fn handlePlayerInput(window: *Window, player: struct { position: *Position, camera: *Camera }, delta_time: f32) void {
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
    if (window.input.getKeyState(.space).isDown()) {
        movement_input.y += 1.0;
    }
    if (window.input.getKeyState(.left_control).isDown()) {
        movement_input.y -= 1.0;
    }

    if (movement_input.length() > 0.0) {
        movement_input = movement_input.normalize();
        player.position.* = player.position.add(movement_input.rotateAroundAxis(.y, player.camera.rotation.yaw).scale(10 * delta_time));
    }
}
