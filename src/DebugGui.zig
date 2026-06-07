const std = @import("std");
const ecs = @import("ecs");
const math = @import("math");
const imgui = @import("imgui");

const help = @import("imgui/help.zig");
const editor = @import("imgui/windows/editor.zig");
const inspector = @import("imgui/windows/inspector.zig");
const launch = @import("imgui/windows/launcher.zig");

const Ecs = @import("ecs.zig").Ecs;
const SingletonType = ecs.SingletonType;
const EntityPointer = ecs.EntityPointer;

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

const Tools = struct {
    editor: editor.Editor = editor.init,
    inspector: inspector.Inspector = inspector.init,
};

const tool_fields = @typeInfo(Tools).@"struct".fields;

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

io: *imgui.struct_ImGuiIO_t,
context: *imgui.ImGuiContext,
launcher: launch.Launcher = launch.init,
tools: Tools = .{},
open_states: [tool_fields.len]bool = .{false} ** tool_fields.len,
selections: struct {
    positions: std.ArrayList(Vector3),
    entitys: std.ArrayList(EntityPointer),
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
allocator: std.mem.Allocator,
drag: ?math.AxisType = null,

const Self = @This();

pub fn init(window: Window, allocator: std.mem.Allocator) Self {
    var new_imgui: Self = .{
        .io = undefined,
        .context = undefined,
        .selections = .{
            .entitys = .empty,
            .positions = .empty,
        },
        .tools = .{},
        .allocator = allocator,
    };

    new_imgui.context = imgui.ImGui_CreateContext(null).?;
    _ = imgui.cImGui_ImplGlfw_InitForOpenGL(@ptrCast(window.ptr), true);
    _ = imgui.cImGui_ImplOpenGL3_Init();

    new_imgui.io = imgui.ImGui_GetIO();
    _ = imgui.ImFontAtlas_AddFontFromFileTTF(
        new_imgui.io.*.Fonts,
        "fonts/RobotoMono-Regular.ttf",
        16.0,
        null,
        null,
    );

    return new_imgui;
}

pub fn deinit(self: *Self) void {
    imgui.cImGui_ImplOpenGL3_Shutdown();
    imgui.cImGui_ImplGlfw_Shutdown();
    imgui.ImGui_DestroyContext(self.context);

    self.selections.entitys.clearAndFree(self.allocator);
    self.selections.positions.clearAndFree(self.allocator);

    self.context = undefined;
    self.io = undefined;
}

pub fn open(self: *Self) void {
    self.launcher.open = true;

    inline for (tool_fields, 0..) |field, i| {
        @field(self.tools, field.name).open = self.open_states[i];
    }

    self.state.update(true);
}

pub fn close(self: *Self, ecs_engine: *Ecs) void {
    self.launcher.open = false;

    inline for (inspected) |field| {
        @field(self.tools.inspector.data, field.name).has = false;
    }

    self.clearEntitySelections(ecs_engine);
    self.clearPositionSelections();

    inline for (tool_fields, 0..) |field, i| {
        self.open_states[i] = @field(self.tools, field.name).open;
        @field(self.tools, field.name).open = false;
    }

    self.state.update(false);
}

pub fn clearEntitySelections(self: *Self, ecs_engine: *Ecs) void {
    self.setEntityOutlines(ecs_engine, false);
    self.selections.entitys.clearRetainingCapacity();
}

pub fn clearPositionSelections(self: *Self) void {
    self.selections.positions.clearRetainingCapacity();
}

pub fn setEntityOutlines(self: *Self, ecs_engine: *Ecs, outline: bool) void {
    for (self.selections.entitys.items) |entity| {
        if (ecs_engine.entityIsValid(entity) and ecs_engine.entityHas(entity, Model)) {
            const model: *Model = ecs_engine.getEntityComponent(entity, Model) catch unreachable;
            model.outline = outline;
        }
    }
}

// Returns true if any of the debug windows are open.
pub fn update(
    self: *Self,
    ecs_engine: *Ecs,
    window: *Window,
    main_camera_singleton: SingletonType,
) !void {
    if (self.launcher.data.tools.inspector) {
        self.tools.inspector.open = true;
    }

    if (self.launcher.data.tools.editor) {
        self.tools.editor.open = true;
    }

    {
        var sync: bool = false;
        var i: usize = 0;
        while (i < self.selections.entitys.items.len) {
            if (!ecs_engine.entityIsValid(self.selections.entitys.items[i])) {
                _ = self.selections.entitys.orderedRemove(i);
                sync = true;
            } else {
                i += 1;
            }
        }

        if (sync) {
            self.syncInspector(ecs_engine, true);
        }
    }

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

            something: {
                if (hit) |raycast_result| {
                    if (ecs_engine.entityHas(raycast_result.body, math.AxisType)) {
                        const axis = ecs_engine.getEntityComponent(raycast_result.body, math.AxisType) catch unreachable;
                        self.drag = axis.*;
                        break :something;
                    }

                    if (window.input.getKeyState(.left_control).isDown()) {
                        self.clearPositionSelections();

                        set: {
                            for (self.selections.entitys.items, 0..) |list_entity, i| {
                                if (list_entity.eql(raycast_result.body)) {
                                    _ = self.selections.entitys.orderedRemove(i);
                                    if (ecs_engine.entityHas(raycast_result.body, Model)) {
                                        const model: *Model = ecs_engine.getEntityComponent(raycast_result.body, Model) catch unreachable;
                                        model.outline = false;
                                    }

                                    break :set;
                                }
                            }

                            if (ecs_engine.entityHas(raycast_result.body, Model)) {
                                const model: *Model = ecs_engine.getEntityComponent(raycast_result.body, Model) catch unreachable;
                                model.outline = true;
                            }

                            try self.selections.entitys.append(self.allocator, raycast_result.body);
                        }

                        self.syncInspector(ecs_engine, true);
                    } else if (window.input.getKeyState(.left_shift).isDown()) {
                        self.clearEntitySelections(ecs_engine);
                        try self.selections.positions.append(self.allocator, raycast_result.position.coerce(Vector3));
                    } else {
                        self.clearEntitySelections(ecs_engine);
                        self.clearPositionSelections();
                    }
                } else {
                    self.clearEntitySelections(ecs_engine);
                    self.clearPositionSelections();
                }
            }
        }
    }

    if (window.input.mouse_state.left_click.isDown()) {
        if (self.drag) |axis| {
            switch (axis) {
                .x => {
                    for (self.selections.entitys.items) |entity| {
                        const pos: *Position = ecs_engine.getEntityComponent(entity, Position) catch unreachable;
                        pos.* = pos.add(Position.right.scale(window.input.mouse_state.motion.x * 0.01));
                    }
                },
                .y => {
                    for (self.selections.entitys.items) |entity| {
                        const pos: *Position = ecs_engine.getEntityComponent(entity, Position) catch unreachable;
                        pos.* = pos.add(Position.up.scale(window.input.mouse_state.motion.y * -0.01));
                    }
                },
                .z => {
                    for (self.selections.entitys.items) |entity| {
                        const pos: *Position = ecs_engine.getEntityComponent(entity, Position) catch unreachable;
                        pos.* = pos.add(Position.forward.scale(window.input.mouse_state.motion.x * 0.01));
                    }
                },
            }
            self.syncInspector(ecs_engine, true);
        }
    } else if (window.input.mouse_state.left_click == .justReleased) {
        self.drag = null;
    }

    self.syncInspector(ecs_engine, false);

    self.newFrame();

    self.launcher.draw();

    inline for (tool_fields) |field| {
        @field(self.tools, field.name).draw();
    }

    render();
    endFrame();

    const is_open: bool = init: {
        inline for (tool_fields) |field| {
            if (@field(self.tools, field.name).open) break :init true;
        }

        break :init self.launcher.open;
    };

    self.state.update(is_open);
}

pub fn syncInspector(self: *Self, ecs_engine: *Ecs, copy: bool) void {
    const entity = if (0 < self.selections.entitys.items.len) self.selections.entitys.getLast() else return;

    inline for (inspected) |field| {
        if (ecs_engine.entityHas(entity, field.type)) {
            const component = ecs_engine.getEntityComponent(entity, field.type) catch unreachable;
            if (copy) {
                @field(self.tools.inspector.data, field.name).value = component.*;
            } else {
                component.* = @field(self.tools.inspector.data, field.name).value;
            }

            @field(self.tools.inspector.data, field.name).has = true;
        } else {
            @field(self.tools.inspector.data, field.name).has = false;
        }
    }
}

pub fn setStyle(_: *Self, style: enum { dark, light, classic }) void {
    switch (style) {
        .dark => imgui.ImGui_StyleColorsDark(null),
        .light => imgui.ImGui_StyleColorsLight(null),
        .classic => imgui.ImGui_StyleColorsClassic(null),
    }
}

// Start a new Dear ImGui frame, you can submit any command from this point until Render()/EndFrame()
pub fn newFrame(self: *const Self) void {
    imgui.ImGui_SetCurrentContext(self.context);

    imgui.cImGui_ImplOpenGL3_NewFrame();
    imgui.cImGui_ImplGlfw_NewFrame();
    imgui.ImGui_NewFrame();
}

// Ends the Dear ImGui frame. automatically called by Render(). If you don't need to render data (skipping rendering) you may call EndFrame() without Render()
pub fn endFrame() void {
    imgui.ImGui_EndFrame();
}

pub fn render() void {
    imgui.ImGui_Render();
    imgui.cImGui_ImplOpenGL3_RenderDrawData(imgui.ImGui_GetDrawData());
}
