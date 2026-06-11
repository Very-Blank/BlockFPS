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
icon_font: *imgui.ImFont,
launcher: launch.Launcher = launch.init,
views: Tools = .{},
open_states: [tool_fields.len]bool = .{false} ** tool_fields.len,
selections: struct {
    positions: std.ArrayList(Vector3),
    entitys: std.ArrayList(EntityPointer),
},
gizmo_last_value: struct {
    position: Position = .zero,
    rotation: Rotation = .identity,
    scale: Scale = .one,
} = .{},
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

const Self = @This();

pub fn init(window: Window, allocator: std.mem.Allocator) Self {
    var new_imgui: Self = .{
        .io = undefined,
        .context = undefined,
        .icon_font = undefined,
        .selections = .{
            .entitys = .empty,
            .positions = .empty,
        },
        .views = .{},
        .allocator = allocator,
    };

    new_imgui.context = imgui.ImGui_CreateContext(null).?;
    _ = imgui.cImGui_ImplGlfw_InitForOpenGL(@ptrCast(window.ptr), true);
    _ = imgui.cImGui_ImplOpenGL3_Init();

    new_imgui.io = imgui.ImGui_GetIO();
    var main_config: imgui.ImFontConfig = .{
        .FontDataOwnedByAtlas = true,
        .OversampleH = 2,
        .OversampleV = 1,
        .GlyphMinAdvanceX = 0.0,
        .GlyphMaxAdvanceX = 18.0,
        .RasterizerMultiply = 1.0,
        .RasterizerDensity = 1.0,
        .ExtraSizeScale = 1.0,
        .PixelSnapV = true,
    };

    _ = imgui.ImFontAtlas_AddFontFromFileTTF(
        new_imgui.io.Fonts,
        "fonts/0xProtoNerdFontMono-Regular.ttf",
        18.0,
        &main_config,
        null,
    );

    var icon_config: imgui.ImFontConfig = .{
        .FontDataOwnedByAtlas = true,
        .OversampleH = 2,
        .OversampleV = 1,
        .GlyphMinAdvanceX = 18.0,
        .GlyphMaxAdvanceX = 18.0,
        .RasterizerMultiply = 1.0,
        .RasterizerDensity = 1.0,
        .ExtraSizeScale = 1.0,
        .PixelSnapV = true,
    };

    new_imgui.icon_font = imgui.ImFontAtlas_AddFontFromFileTTF(
        new_imgui.io.Fonts,
        "fonts/fontawesome-free-7.2.0-web/fa-solid-900.ttf",
        18.0,
        &icon_config,
        null,
    ).?;

    const style: *imgui.ImGuiStyle = imgui.ImGui_GetStyle();
    style.WindowRounding = 5.0;
    const rouding = 2.5;
    style.ScrollbarRounding = rouding;
    style.GrabRounding = rouding;
    style.ImageRounding = rouding;
    style.TabRounding = rouding;
    style.ChildRounding = rouding;
    style.PopupRounding = rouding;
    style.FrameRounding = rouding;
    style.ScrollbarRounding = rouding;
    style.GrabRounding = rouding;
    style.ImageRounding = rouding;
    style.TabRounding = rouding;

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
        @field(self.views, field.name).open = self.open_states[i];
    }

    self.state.update(true);
}

pub fn close(self: *Self, ecs_engine: *Ecs) void {
    self.launcher.open = false;

    inline for (inspected) |field| {
        @field(self.views.inspector.data, field.name).has = false;
    }

    self.clearEntitySelections(ecs_engine);
    self.clearPositionSelections();

    inline for (tool_fields, 0..) |field, i| {
        self.open_states[i] = @field(self.views, field.name).open;
        @field(self.views, field.name).open = false;
    }

    self.state.update(false);
}

pub fn clearEntitySelections(self: *Self, ecs_engine: *Ecs) void {
    self.setEntityOutlines(ecs_engine, .all, false);
    self.selections.entitys.clearRetainingCapacity();
}

pub fn clearPositionSelections(self: *Self) void {
    self.selections.positions.clearRetainingCapacity();
}

pub fn setEntityOutlines(self: *Self, ecs_engine: *Ecs, which: enum { primary, all }, enabled: bool) void {
    if (self.selections.entitys.items.len == 0) return;
    switch (which) {
        .primary => {
            var i: usize = 0;
            while (i < self.selections.entitys.items.len - 1) : (i += 1) {
                const entity = self.selections.entitys.items[i];
                (ecs_engine.getEntityComponent(entity, Model) orelse continue).outline = .{
                    .enabled = enabled,
                    .color = .{ .r = 0.5, .b = 0.5, .g = 0.5 },
                };
            }

            set_primary: {
                (ecs_engine.getEntityComponent(self.selections.entitys.getLast(), Model) orelse break :set_primary).outline = .{
                    .enabled = enabled,
                    .color = .{},
                };
            }
        },
        .all => {
            var i: usize = 0;
            while (i < self.selections.entitys.items.len - 1) : (i += 1) {
                const entity = self.selections.entitys.items[i];
                (ecs_engine.getEntityComponent(entity, Model) orelse continue).outline = .{
                    .enabled = enabled,
                    .color = .{},
                };
            }

            set_primary: {
                (ecs_engine.getEntityComponent(self.selections.entitys.getLast(), Model) orelse break :set_primary).outline = .{
                    .enabled = enabled,
                    .color = .{},
                };
            }
        },
    }

    self.views.inspector.data.model.value.outline = .{
        .enabled = enabled,
        .color = .{},
    };
}

// Returns true if any of the debug windows are open.
pub fn update(
    self: *Self,
    ecs_engine: *Ecs,
    window: *Window,
    main_camera_singleton: SingletonType,
) !void {
    if (self.launcher.data.views.inspector) {
        self.launcher.data.views.inspector = false;
        self.views.inspector.open = true;
    }

    if (self.launcher.data.views.editor) {
        self.launcher.data.views.editor = false;
        self.views.editor.open = true;
    }

    {
        var copy = false;
        var i: usize = 0;
        while (i < self.selections.entitys.items.len) {
            if (!ecs_engine.entityIsValid(self.selections.entitys.items[i])) {
                _ = self.selections.entitys.orderedRemove(i);
                copy = true;
            } else {
                i += 1;
            }
        }

        if (copy) self.syncInspector(ecs_engine, .copy);
    }

    if (!self.io.WantCaptureMouse and window.input.mouse_state.left_click == .justPressed) {
        if (ecs_engine.getSingletonsEntity(main_camera_singleton)) |id| {
            const camera = ecs_engine.getEntityComponent(id, Camera) orelse unreachable;
            const position = ecs_engine.getEntityComponent(id, Position) orelse unreachable;

            const view_matrix = Mat4.initView(
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
                if (window.input.getKeyState(.left_control).isDown()) {
                    self.clearPositionSelections();

                    append: {
                        for (self.selections.entitys.items, 0..) |list_entity, i| {
                            if (list_entity.eql(raycast_result.body)) {
                                _ = self.selections.entitys.orderedRemove(i);
                                (ecs_engine.getEntityComponent(raycast_result.body, Model) orelse break :append).outline.enabled = false;

                                break :append;
                            }
                        }

                        try self.selections.entitys.append(self.allocator, raycast_result.body);
                    }

                    self.syncInspector(ecs_engine, .copy);
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

    self.newFrame();

    if (self.selections.entitys.items.len > 0) {
        switch (self.launcher.data.tool.type) {
            .select, .rotate, .scale => self.setEntityOutlines(ecs_engine, .primary, true),
            .move => self.setEntityOutlines(ecs_engine, .all, true),
        }

        switch (self.launcher.data.tool.type) {
            .select => {
                if (self.views.inspector.open) {
                    self.syncInspector(ecs_engine, .set);
                } else {
                    self.syncInspector(ecs_engine, .copy);
                }
            },
            else => |tool| if (ecs_engine.getSingletonsEntity(main_camera_singleton)) |id| {
                const camera = ecs_engine.getEntityComponent(id, Camera) orelse unreachable;
                const position = ecs_engine.getEntityComponent(id, Position) orelse unreachable;

                imgui.ImGuizmo_SetRect(0, 0, self.io.DisplaySize.x, self.io.DisplaySize.y);

                const view_matrix = (Mat4.initView(
                    position.add(Position{ .y = camera.offset }).negate(),
                    math.f32.Quaternion.initCamRotation(-camera.rotation.yaw, -camera.rotation.pitch),
                ));

                const projection_matrix = camera.projection.mat;

                manipulate: switch (tool) {
                    .move => {
                        var average_position: Position = .zero;

                        var count: usize = 0;
                        for (self.selections.entitys.items) |entity| {
                            average_position = average_position.add((ecs_engine.getEntityComponent(entity, Position) orelse continue).*);
                            count += 1;
                        }

                        average_position = average_position.segment(@floatFromInt(count));

                        var model_matrix = Mat4.initModel(average_position, Scale.one, Rotation.identity);

                        _ = imgui.ImGuizmo_Manipulate(
                            &view_matrix.fields[0][0],
                            &projection_matrix.fields[0][0],
                            imgui.ImGuizmo_OPERATION_TRANSLATE,
                            imgui.ImGuizmo_MODE_WORLD,
                            &model_matrix.fields[0][0],
                        );

                        if (imgui.ImGuizmo_IsUsing()) {
                            const change: Position = .{
                                .x = model_matrix.fields[3][0] - average_position.x,
                                .y = model_matrix.fields[3][1] - average_position.y,
                                .z = model_matrix.fields[3][2] - average_position.z,
                            };

                            for (self.selections.entitys.items) |entity| {
                                const selection_position = (ecs_engine.getEntityComponent(entity, Position) orelse continue);
                                selection_position.* = selection_position.add(change);
                            }
                        }
                    },
                    .rotate => {
                        const target_position = ecs_engine.getEntityComponent(self.selections.entitys.getLast(), Position) orelse break :manipulate;
                        const target_rotation = ecs_engine.getEntityComponent(self.selections.entitys.getLast(), Rotation) orelse break :manipulate;

                        var model_matrix = Mat4.initModel(target_position.*, Scale.one, target_rotation.*);

                        _ = imgui.ImGuizmo_Manipulate(
                            &view_matrix.fields[0][0],
                            &projection_matrix.fields[0][0],
                            imgui.ImGuizmo_OPERATION_ROTATE & ~imgui.ImGuizmo_OPERATION_ROTATE_SCREEN,
                            imgui.ImGuizmo_MODE_WORLD,
                            &model_matrix.fields[0][0],
                        );

                        if (imgui.ImGuizmo_IsUsing()) {
                            model_matrix.fields[3][0] -= target_position.x;
                            model_matrix.fields[3][1] -= target_position.y;
                            model_matrix.fields[3][2] -= target_position.z;

                            target_rotation.* = Rotation.initFromMatrix(model_matrix).normalize();
                        }
                    },
                    .scale => {
                        const target_position = ecs_engine.getEntityComponent(self.selections.entitys.getLast(), Position) orelse break :manipulate;
                        const target_scale = ecs_engine.getEntityComponent(self.selections.entitys.getLast(), Scale) orelse break :manipulate;

                        var model_matrix = Mat4.initModel(target_position.*, target_scale.*, Rotation.identity);

                        _ = imgui.ImGuizmo_Manipulate(
                            &view_matrix.fields[0][0],
                            &projection_matrix.fields[0][0],
                            imgui.ImGuizmo_OPERATION_SCALE,
                            imgui.ImGuizmo_MODE_WORLD,
                            &model_matrix.fields[0][0],
                        );

                        if (imgui.ImGuizmo_IsUsing()) {
                            target_scale.* = Scale{
                                .x = model_matrix.fields[0][0],
                                .y = model_matrix.fields[1][1],
                                .z = model_matrix.fields[2][2],
                            };
                        }
                    },
                    else => unreachable,
                }

                self.syncInspector(ecs_engine, .copy);
            },
        }
    }

    self.launcher.draw(self.icon_font);

    inline for (tool_fields) |field| {
        @field(self.views, field.name).draw(self.icon_font);
    }

    render();
    endFrame();

    const is_open: bool = init: {
        inline for (tool_fields) |field| {
            if (@field(self.views, field.name).open) break :init true;
        }

        break :init self.launcher.open;
    };

    self.state.update(is_open);
}

pub fn syncInspector(self: *Self, ecs_engine: *Ecs, @"type": enum { copy, set }) void {
    const entity = if (0 < self.selections.entitys.items.len) self.selections.entitys.getLast() else return;

    inline for (inspected) |field| {
        if (ecs_engine.entityHas(entity, field.type)) {
            const component = ecs_engine.getEntityComponent(entity, field.type) orelse unreachable;
            switch (@"type") {
                .copy => @field(self.views.inspector.data, field.name).value = component.*,
                .set => component.* = @field(self.views.inspector.data, field.name).value,
            }

            @field(self.views.inspector.data, field.name).has = true;
        } else {
            @field(self.views.inspector.data, field.name).has = false;
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
    imgui.ImGuizmo_BeginFrame();
}

// Ends the Dear ImGui frame. automatically called by Render(). If you don't need to render data (skipping rendering) you may call EndFrame() without Render()
pub fn endFrame() void {
    imgui.ImGui_EndFrame();
}

pub fn render() void {
    imgui.ImGui_Render();
    imgui.cImGui_ImplOpenGL3_RenderDrawData(imgui.ImGui_GetDrawData());
}
