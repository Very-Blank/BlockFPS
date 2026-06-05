const std = @import("std");
const ecs = @import("ecs");
const json = @import("json.zig");
const math = @import("math");
const imgui = @import("imgui");

const help = @import("imgui/help.zig");
const inspector = @import("imgui/windows/inspector.zig");
const launch = @import("imgui/windows/launcher.zig");

const Ecs = @import("ecs.zig").Ecs;
const SingletonType = ecs.SingletonType;

const Physics = @import("Physics.zig");

const Vector3 = math.f32.Vector3;
const Mat4 = math.f32.Mat4;

const Window = @import("Window.zig");
const ImGuiWindow = @import("imgui/window.zig").Window;

const Model = @import("components/model.zig").Model;
const Position = @import("components/position.zig").Position;
const Rotation = @import("components/rotation.zig").Rotation;
const Scale = @import("components/scale.zig").Scale;
const Camera = @import("components/Camera.zig");
const Collider = @import("components/collider.zig").Collider;
const Mask = Collider.Mask;
const Layer = Collider.Layer;
const Rigidbody = @import("components/Rigidbody.zig");
const Grounded = @import("components/Grounded.zig");
const Health = @import("components/Health.zig");
const Bullet = @import("components/Bullet.zig");
const Enemy = @import("components/Enemy.zig");

io: *imgui.struct_ImGuiIO_t,
context: *imgui.ImGuiContext,
launcher: launch.Launcher = launch.init,
tools: struct {
    editor: ,
    inspector: inspector.Inspector = inspector.init,
},
open_states: [2]bool = .{false} ** 2,
selection: struct {
    singleton: SingletonType,
    position: Vector3,
},
state: enum {
    just_opened,
    open,
    just_closed,
    closed,

    pub inline fn isOpen(state: @This()) bool {
        return (state == .just_opened or state == .open);
    }

    pub inline fn update(self: *@This(), is_open: bool) void {
        if (is_open) {
            self.* = switch (self.*) {
                .just_opened, .open => .open,
                else => .just_opened,
            };

            return;
        }

        self.* = switch (self.*) {
            .just_opened, .open => .just_closed,
            else => .closed,
        };
    }
} = .closed,

const Self = @This();

pub fn init(window: Window, selection: SingletonType) Self {
    var new_imgui: Self = .{
        .io = undefined,
        .context = undefined,
        .selection = .{
            .singleton = selection,
            .position = .zero,
        },
        .tools = .{},
    };

    new_imgui.context = imgui.ImGui_CreateContext(null).?;
    _ = imgui.cImGui_ImplGlfw_InitForOpenGL(@ptrCast(window.ptr), true);
    _ = imgui.cImGui_ImplOpenGL3_Init();

    new_imgui.io = imgui.ImGui_GetIO();

    return new_imgui;
}

pub fn open(self: *Self) void {
    self.launcher.open = true;

    inline for (@typeInfo(@FieldType(Self, "tools")).@"struct".fields, 0..) |field, i| {
        @field(self.tools, field.name).open = self.open_states[i];
    }

    self.state.update(true);
}

pub fn close(self: *Self) void {
    self.launcher.open = false;

    inline for (@typeInfo(@FieldType(Self, "tools")).@"struct".fields, 0..) |field, i| {
        self.open_states[i] = @field(self.tools, field.name).open;
        @field(self.tools, field.name).open = false;
    }

    self.state.update(false);
}

// Returns true if any of the debug windows are open.
pub fn update(
    self: *Self,
    ecs_engine: *Ecs,
    window: *Window,
    main_camera_singleton: SingletonType,
) void {
    if (self.launcher.data.tools.inspector) {
        self.tools.inspector.open = true;
    }

    if (self.launcher.data.tools.editor) {
        self.tools.editor.open = true;
    }

    const inspected = .{
        .{ .name = "position", .type = Position },
        .{ .name = "rotation", .type = Rotation },
        .{ .name = "scale", .type = Scale },
        .{ .name = "model", .type = Model },
        .{ .name = "collider", .type = Collider },
        .{ .name = "rigidbody", .type = Rigidbody },
        .{ .name = "grounded", .type = Grounded },
        .{ .name = "health", .type = Health },
    };

    if (!self.io.WantCaptureMouse and window.input.mouse_state.left_click == .justPressed) {
        if (ecs_engine.getSingletonsEntity(main_camera_singleton)) |id| {
            const camera = ecs_engine.getEntityComponent(id, Camera) catch unreachable;
            const position = ecs_engine.getEntityComponent(id, Position) catch unreachable;

            const view_matrix = math.f32.Mat4.initView(
                position.add(Position{ .y = camera.offset }).negate(),
                math.f32.Quaternion.initCamRotation(-camera.rotation.yaw, -camera.rotation.pitch),
            );

            const inverse_projection = camera.projection.mat.inverse();
            const inverse_view = view_matrix.inverse();

            const ray_eye = inverse_projection.multiplyVector([4]f32{
                (2 * window.input.mouse_state.position.x) / @as(f32, @floatFromInt(window.logical.width)) - 1.0,
                1.0 - (2 * window.input.mouse_state.position.y) / @as(f32, @floatFromInt(window.logical.height)),
                -1.0,
                1.0,
            });

            const ray_world = inverse_view.multiplyVector([4]f32{
                ray_eye[0],
                ray_eye[1],
                -1.0,
                0.0,
            });

            const normal = (Vector3{
                .x = ray_world[0],
                .y = ray_world[1],
                .z = ray_world[2],
            }).normalize();

            const hit = Physics.raycast(
                ecs_engine,
                position.add(Position{ .y = camera.offset }).coerce(Vector3),
                normal,
                200.0,
                Mask.all.remove(&.{.player}),
            );

            if (hit) |raycast_result| {
                if (window.input.getKeyState(.left_shift).isDown()) {
                    ecs_engine.setSingletonsEntity(self.selection.singleton, raycast_result.body) catch unreachable;

                    inline for (inspected) |field| {
                        if (ecs_engine.entityHas(raycast_result.body, field.type)) {
                            const component = ecs_engine.getEntityComponent(raycast_result.body, field.type) catch unreachable;
                            @field(self.tools.inspector.data, field.name).value = component.*;
                        }
                    }
                } else {
                    self.selection.position = raycast_result.position.coerce(Vector3);
                }
            } else {
                ecs_engine.clearSingletonsEntity(self.selection.singleton);
            }
        }
    }

    if (ecs_engine.getSingletonsEntity(self.selection.singleton)) |selected_entity| {
        inline for (inspected) |field| {
            if (ecs_engine.entityHas(selected_entity, field.type)) {
                const component = ecs_engine.getEntityComponent(selected_entity, field.type) catch unreachable;
                component.* = @field(self.tools.inspector.data, field.name).value;
                @field(self.tools.inspector.data, field.name).has = true;
            } else {
                @field(self.tools.inspector.data, field.name).has = false;
            }
        }
    } else {
        inline for (inspected) |field| {
            @field(self.tools.inspector.data, field.name).has = false;
        }
    }

    self.newFrame();

    self.launcher.draw();

    inline for (@typeInfo(@FieldType(Self, "tools")).@"struct".fields) |field| {
        @field(self.tools, field.name).draw();
    }

    render();
    endFrame();

    const is_open: bool = init: {
        inline for (@typeInfo(@FieldType(Self, "tools")).@"struct".fields) |field| {
            if (@field(self.tools, field.name).open) break :init true;
        }

        break :init self.launcher.open;
    };

    self.state.update(is_open);
}

pub inline fn deinit(self: *Self) void {
    imgui.cImGui_ImplOpenGL3_Shutdown();
    imgui.cImGui_ImplGlfw_Shutdown();
    imgui.ImGui_DestroyContext(self.context);

    self.context = undefined;
    self.io = undefined;
}

pub inline fn setStyle(_: *Self, style: enum { dark, light, classic }) void {
    switch (style) {
        .dark => imgui.ImGui_StyleColorsDark(null),
        .light => imgui.ImGui_StyleColorsLight(null),
        .classic => imgui.ImGui_StyleColorsClassic(null),
    }
}

// Start a new Dear ImGui frame, you can submit any command from this point until Render()/EndFrame()
pub inline fn newFrame(self: *const Self) void {
    imgui.ImGui_SetCurrentContext(self.context);

    imgui.cImGui_ImplOpenGL3_NewFrame();
    imgui.cImGui_ImplGlfw_NewFrame();
    imgui.ImGui_NewFrame();
}

// Ends the Dear ImGui frame. automatically called by Render(). If you don't need to render data (skipping rendering) you may call EndFrame() without Render()
pub fn endFrame() void {
    imgui.ImGui_EndFrame();
}

pub inline fn render() void {
    imgui.ImGui_Render();
    imgui.cImGui_ImplOpenGL3_RenderDrawData(imgui.ImGui_GetDrawData());
}
