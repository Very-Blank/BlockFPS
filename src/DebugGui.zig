const std = @import("std");
const ecs = @import("ecs");
const math = @import("math");
const imgui = @import("imgui");

const Ecs = @import("ecs.zig").Ecs;
const SingletonType = ecs.SingletonType;
const EntityPointer = ecs.EntityPointer;

const Physics = @import("Physics.zig");

const Vector3 = math.f32.Vector3;
const Mat4 = math.f32.Mat4;

const Window = @import("Window.zig");
const Assets = @import("Assets.zig");

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

const View = struct {
    name: [:0]const u8,
    open: bool = false,
    flags: i32 = 0,
};

const Tool = enum {
    select,
    move,
    rotate,
    scale,
};

const Mode = enum(u32) {
    normal = 0,
    cam = 1,
};

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

io: *imgui.ImGuiIO,
context: *imgui.ImGuiContext,
icons: *imgui.ImFont,
views: struct {
    main: View = .{ .name = "Main" },
    inspector: View = .{ .name = "Inspector" },
    editor: View = .{ .name = "Editor" },
},
game: struct {
    freeze: bool = false,
    mode: Mode = .normal,
} = .{},
tool: Tool = .select,
state: enum {
    just_opened,
    open,
    just_closed,
    closed,
} = .closed,
selections: struct {
    positions: std.ArrayList(Vector3),
    entitys: std.ArrayList(EntityPointer),

    pub fn clearEntitySelections(self: *@This(), ecs_engine: *Ecs) void {
        self.setEntityOutlines(ecs_engine, .all, false);
        self.entitys.clearRetainingCapacity();
    }

    pub fn setEntityOutlines(self: *@This(), ecs_engine: *Ecs, which: enum { primary, all }, enabled: bool) void {
        if (self.entitys.items.len == 0) return;
        switch (which) {
            .primary => {
                var i: usize = 0;
                while (i < self.entitys.items.len - 1) : (i += 1) {
                    const entity = self.entitys.items[i];
                    (ecs_engine.getEntityComponent(entity, Model) orelse continue).outline = .{
                        .enabled = enabled,
                        .color = .{ .r = 0.5, .b = 0.5, .g = 0.5 },
                    };
                }

                set_primary: {
                    (ecs_engine.getEntityComponent(self.entitys.getLast(), Model) orelse break :set_primary).outline = .{
                        .enabled = enabled,
                        .color = .{},
                    };
                }
            },
            .all => {
                var i: usize = 0;
                while (i < self.entitys.items.len - 1) : (i += 1) {
                    const entity = self.entitys.items[i];
                    (ecs_engine.getEntityComponent(entity, Model) orelse continue).outline = .{
                        .enabled = enabled,
                        .color = .{},
                    };
                }

                set_primary: {
                    (ecs_engine.getEntityComponent(self.entitys.getLast(), Model) orelse break :set_primary).outline = .{
                        .enabled = enabled,
                        .color = .{},
                    };
                }
            },
        }
    }

    pub fn clearPositionSelections(self: *@This()) void {
        self.positions.clearRetainingCapacity();
    }
},
allocator: std.mem.Allocator,

const Self = @This();

pub const width = 150.0;

pub fn init(window: Window, allocator: std.mem.Allocator) Self {
    var new_imgui: Self = .{
        .io = undefined,
        .context = undefined,
        .icons = undefined,
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

    new_imgui.icons = imgui.ImFontAtlas_AddFontFromFileTTF(
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
    self.state = .just_opened;
    self.views.main.open = true;
}

pub fn close(self: *Self, ecs_engine: *Ecs) void {
    self.state = .just_closed;
    self.selections.clearEntitySelections(ecs_engine);
}

pub fn isOpen(self: *Self) bool {
    return self.state == .just_opened or self.state == .open;
}

// Returns true if any of the debug windows are open.
pub fn update(
    self: *Self,
    ecs_engine: *Ecs,
    window: *Window,
    assets: *Assets,
    main_camera_singleton: SingletonType,
) !void {
    self.state = switch (self.state) {
        .just_opened, .open => .open,
        .just_closed, .closed => .closed,
    };

    if (self.state == .closed or self.state == .just_closed) return;

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
                    self.selections.clearPositionSelections();

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
                } else if (window.input.getKeyState(.left_shift).isDown()) {
                    self.selections.clearEntitySelections(ecs_engine);
                    try self.selections.positions.append(self.allocator, raycast_result.position.coerce(Vector3));
                } else {
                    self.selections.clearEntitySelections(ecs_engine);
                    self.selections.clearPositionSelections();
                }
            } else {
                self.selections.clearEntitySelections(ecs_engine);
                self.selections.clearPositionSelections();
            }
        }
    }

    imgui.cImGui_ImplOpenGL3_NewFrame();
    imgui.cImGui_ImplGlfw_NewFrame();
    imgui.ImGui_NewFrame();
    imgui.ImGuizmo_BeginFrame();

    if (self.selections.entitys.items.len > 0) {
        switch (self.tool) {
            .select, .rotate, .scale => self.selections.setEntityOutlines(ecs_engine, .primary, true),
            .move => self.selections.setEntityOutlines(ecs_engine, .all, true),
        }

        switch (self.tool) {
            .move, .rotate, .scale => |tool| if (ecs_engine.getSingletonsEntity(main_camera_singleton)) |id| {
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

                                (ecs_engine.getEntityComponent(entity, Rigidbody) orelse continue).velocity = .zero;
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
            },
            else => {},
        }
    }

    self.mainUpdate();
    self.inspectorUpdate(ecs_engine);
    self.editorUpdate(ecs_engine, assets);

    imgui.ImGui_Render();
    imgui.cImGui_ImplOpenGL3_RenderDrawData(imgui.ImGui_GetDrawData());
    imgui.ImGui_EndFrame();
}

pub fn mainUpdate(self: *Self) void {
    if (!self.views.main.open) return;

    defer imgui.ImGui_End();
    if (!imgui.ImGui_Begin(self.views.main.name, &(self.views.main.open), self.views.main.flags)) return;

    if (imgui.ImGui_BeginTable("split", 2, 0)) {
        defer imgui.ImGui_EndTable();

        const button_size: f32 = 32.5;

        imgui.ImGui_TableSetupColumn("Left", 0);
        imgui.ImGui_TableSetupColumnEx("Right", imgui.ImGuiTableColumnFlags_WidthFixed, button_size, 0);

        if (imgui.ImGui_TableNextColumn()) {
            {
                imgui.ImGui_PushItemWidth(100);
                defer imgui.ImGui_PopItemWidth();

                if (imgui.ImGui_BeginCombo("##tools", "Views", 0)) {
                    defer imgui.ImGui_EndCombo();

                    if (imgui.ImGui_Selectable("Inspector"))
                        self.views.inspector.open = true;

                    if (imgui.ImGui_Selectable("Editor"))
                        self.views.editor.open = true;
                }
            }

            imgui.ImGui_Separator();

            {
                imgui.ImGui_Text("Game");
                imgui.ImGui_Indent();
                defer imgui.ImGui_Unindent();

                _ = imgui.ImGui_Checkbox("Freeze", &self.game.freeze);

                imgui.ImGui_PushItemWidth(width);
                defer imgui.ImGui_PopItemWidth();

                imgui.ImGui_SameLine();

                enumSelector(Mode, &self.game.mode, "Mode");
            }
        }

        if (imgui.ImGui_TableNextColumn()) {
            const old = self.tool;
            imgui.ImGui_PushFont(self.icons);
            defer imgui.ImGui_PopFont();
            inline for (std.enums.values(Tool)) |value| {
                if (old != value)
                    imgui.ImGui_PushStyleVar(imgui.ImGuiStyleVar_Alpha, imgui.ImGui_GetStyle()[0].Alpha * 0.5);

                if (imgui.ImGui_ButtonEx(std.fmt.comptimePrint("{u}", .{switch (value) {
                    .select => '',
                    .move => '',
                    .rotate => '',
                    .scale => '',
                }}), .{ .x = button_size, .y = button_size })) {
                    self.tool = value;
                }
                if (old != value)
                    imgui.ImGui_PopStyleVar();
            }
        }
    }
}

pub fn inspectorUpdate(self: *Self, ecs_engine: *Ecs) void {
    if (!self.views.inspector.open) return;

    defer imgui.ImGui_End();
    if (!imgui.ImGui_Begin(self.views.inspector.name, &(self.views.inspector.open), self.views.inspector.flags)) return;

    const entity = self.selections.entitys.getLastOrNull() orelse return;

    imgui.ImGui_BeginDisabled(self.tool != .select);
    defer imgui.ImGui_EndDisabled();

    {
        imgui.ImGui_PushItemWidth(width);
        defer imgui.ImGui_PopItemWidth();

        if (ecs_engine.entityHas(entity, Position) and imgui.ImGui_CollapsingHeader("Position", 0)) {
            imgui.ImGui_Indent();
            defer imgui.ImGui_Unindent();

            vectorField(Position, ecs_engine.getEntityComponent(entity, Position) orelse unreachable, "##Position", .{});
        }

        if (ecs_engine.entityHas(entity, Rotation) and imgui.ImGui_CollapsingHeader("Rotation", 0)) {
            imgui.ImGui_Indent();
            defer imgui.ImGui_Unindent();
            quaternionField(Rotation, ecs_engine.getEntityComponent(entity, Rotation) orelse unreachable, "##Rotation", .{});
        }

        if (ecs_engine.entityHas(entity, Scale) and imgui.ImGui_CollapsingHeader("Scale", 0)) {
            imgui.ImGui_Indent();
            defer imgui.ImGui_Unindent();

            vectorField(Scale, ecs_engine.getEntityComponent(entity, Scale) orelse unreachable, "##Scale", .{});
        }
    }

    if (ecs_engine.entityHas(entity, Model) and imgui.ImGui_CollapsingHeader("Model", 0)) {
        imgui.ImGui_Indent();
        defer imgui.ImGui_Unindent();

        enumSelector(Model.Type, &(ecs_engine.getEntityComponent(entity, Model) orelse unreachable).type, "Type##Model");
    }

    if (ecs_engine.entityHas(entity, Collider) and imgui.ImGui_CollapsingHeader("Collider", 0)) {
        const collider = ecs_engine.getEntityComponent(entity, Collider) orelse unreachable;

        imgui.ImGui_Indent();
        defer imgui.ImGui_Unindent();

        enumSelector(Layer, &collider.layer, "Layer##ColliderLayer");

        imgui.ImGui_Separator();

        {
            imgui.ImGui_Text("Mask");

            imgui.ImGui_Indent();
            defer imgui.ImGui_Unindent();

            var mask_int: i32 = @intFromEnum(collider.mask);
            const mask_bits = @typeInfo(@typeInfo(Mask).@"enum".tag_type).int.bits;
            const columns = 8;

            inline for (0..mask_bits) |i| {
                const column = i % columns;

                if (column == 0) {
                    imgui.ImGui_Text(comptime pad(itoa(i) ++ "-" ++ itoa(i + columns - 1), 5, .right));
                    imgui.ImGui_SameLineEx(0, 0);
                } else {
                    imgui.ImGui_SameLineEx(0, 0);
                }

                const bit: i32 = @as(i32, 1) << i;
                var checked = (mask_int & bit) != 0;

                if (imgui.ImGui_Checkbox("##ColliderMask" ++ (comptime itoa(i)), &checked)) {
                    if (checked) mask_int |= bit else mask_int &= ~bit;
                    collider.mask = @enumFromInt(mask_int);
                }
            }
        }

        imgui.ImGui_Separator();

        {
            imgui.ImGui_Indent();
            defer imgui.ImGui_Unindent();

            imgui.ImGui_PushItemWidth(width);
            defer imgui.ImGui_PopItemWidth();

            const shape_names: []const u8 = "Sphere" ++ .{0} ++ "Capsule" ++ .{0} ++ "Box" ++ .{ 0, 0 };
            var current_shape: i32 = switch (collider.type) {
                .sphere => 0,
                .capsule => 1,
                .box => 2,
            };

            if (imgui.ImGui_ComboEx("Shape##ColliderShape", &current_shape, shape_names.ptr, -1)) {
                collider.type = switch (current_shape) {
                    0 => .{ .sphere = .{ .radius = 1.0 } },
                    1 => .{ .capsule = .{ .radius = 0.5, .half_height = 1.0 } },
                    else => .{ .box = .{ .x = 1.0, .y = 1.0, .z = 1.0 } },
                };
            }

            switch (collider.type) {
                .sphere => |*sphere| _ = imgui.ImGui_DragFloat("Radius##SphereCollider", @ptrCast(&sphere.radius)),
                .capsule => |*capsule| {
                    _ = imgui.ImGui_DragFloat("Radius##CapsuleCollider", @ptrCast(&capsule.radius));
                    _ = imgui.ImGui_DragFloat("Height##CapsuleCollider", @ptrCast(&capsule.half_height));
                },
                .box => |*box| vectorField(Collider.Box, box, "##BoxCollider", .{}),
            }
        }
    }

    if (ecs_engine.entityHas(entity, Rigidbody) and imgui.ImGui_CollapsingHeader("Rigidbody", 0)) {
        const rigidbody = ecs_engine.getEntityComponent(entity, Rigidbody) orelse unreachable;

        imgui.ImGui_Indent();
        defer imgui.ImGui_Unindent();

        imgui.ImGui_PushItemWidth(width);
        defer imgui.ImGui_PopItemWidth();

        if (imgui.ImGui_CollapsingHeader("Velocity##Rigidbody", 0)) {
            imgui.ImGui_Indent();
            defer imgui.ImGui_Unindent();

            vectorField(Vector3, &rigidbody.velocity, "##Rigidbody", .{});
        }

        imgui.ImGui_Separator();

        _ = imgui.ImGui_DragFloat("Gravity##Rigidbody", @ptrCast(&rigidbody.gravity));
        _ = imgui.ImGui_DragFloat("Mass##Rigidbody", @ptrCast(&rigidbody.mass));
        _ = imgui.ImGui_DragFloat("Restitution##Rigidbody", @ptrCast(&rigidbody.restitution));
    }

    if (ecs_engine.entityHas(entity, Grounded) and imgui.ImGui_CollapsingHeader("Grounded", 0)) {
        imgui.ImGui_Indent();
        defer imgui.ImGui_Unindent();

        _ = imgui.ImGui_Checkbox("Grounded##gnd", &(ecs_engine.getEntityComponent(entity, Grounded) orelse unreachable).grounded);
    }

    if (ecs_engine.entityHas(entity, Health) and imgui.ImGui_CollapsingHeader("Health", 0)) {
        const healt = ecs_engine.getEntityComponent(entity, Health) orelse unreachable;

        imgui.ImGui_Indent();
        defer imgui.ImGui_Unindent();

        imgui.ImGui_PushItemWidth(width);
        defer imgui.ImGui_PopItemWidth();

        _ = imgui.ImGui_DragFloat("Current##Health", @ptrCast(&healt.current));
        _ = imgui.ImGui_DragFloat("Max##Health", @ptrCast(&healt.max));
    }
}

pub fn editorUpdate(self: *Self, ecs_engine: *Ecs, assets: *Assets) void {
    if (!self.views.editor.open) return;

    defer imgui.ImGui_End();
    if (!imgui.ImGui_Begin(self.views.editor.name, &(self.views.editor.open), self.views.editor.flags)) return;

    for (assets.names.items, 0..) |asset_names, i| {
        if (imgui.ImGui_ButtonEx(asset_names, .{ .x = -imgui.__FLT_MIN__ })) {
            const asset = assets.assets.items[i];
            for (self.selections.positions.items) |position| {
                for (asset) |object| {
                    switch (object) {
                        .rigidbody => |value| {
                            var offseted = value;
                            offseted[0] = offseted[0].add(position);
                            _ = ecs_engine.createEntity(offseted, &.{});
                        },
                        .staticbody => |value| {
                            var offseted = value;
                            offseted[0] = offseted[0].add(position);
                            _ = ecs_engine.createEntity(offseted, &.{});
                        },
                        .model => |value| {
                            var offseted = value;
                            offseted[0] = offseted[0].add(position);
                            _ = ecs_engine.createEntity(offseted, &.{});
                        },
                    }
                }
            }
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

pub fn itoa(comptime value: anytype) [:0]const u8 {
    comptime var string: [:0]const u8 = "";
    comptime var num = value;

    if (num == 0) {
        string = string ++ .{'0'};
    } else {
        while (num != 0) {
            string = .{'0' + (num % 10)} ++ string;
            num = num / 10;
        }
    }

    return string;
}

pub fn pad(comptime value: [:0]const u8, comptime len: usize, comptime side: enum { left, right }) [:0]const u8 {
    comptime var string: [:0]const u8 = value;
    switch (side) {
        .left => {
            while (string.len < len) {
                string = .{' '} ++ string;
            }

            return string;
        },
        .right => {
            while (string.len < len) {
                string = string ++ .{' '};
            }

            return string;
        },
    }
}

pub inline fn vectorField(
    comptime T: type,
    value: *T,
    suffix: [:0]const u8,
    options: struct { speed: f32 = 0.01, min: f32 = -1000.0, max: f32 = 1000.0 },
) void {
    switch (@typeInfo(T)) {
        .@"struct" => {},
        else => @compileError("Unexpected type was given: " ++ @typeName(T) ++ "."),
    }

    if (!@hasDecl(T, "type") or (T.type != .vector2 and T.type != .vector3))
        @compileError("Unexpected type was given: " ++ @typeName(T) ++ ".");

    inline for (comptime std.meta.fieldNames(T)) |field| {
        _ = imgui.ImGui_DragFloatEx(.{std.ascii.toUpper(field[0])} ++ suffix, @ptrCast(&@field(value, field)), options.speed, options.min, options.max, "%.3f", 0);
    }
}

pub inline fn quaternionField(
    comptime T: type,
    value: *T,
    suffix: [:0]const u8,
    options: struct { speed: f32 = 0.01, min: f32 = -1.0, max: f32 = 1.0 },
) void {
    math.assertType(T, .quaternion);

    inline for (.{ "W", "X", "Y", "Z" }, 0..) |field, i| {
        _ = imgui.ImGui_DragFloatEx(field ++ suffix, @ptrCast(&value.fields[i]), options.speed, options.min, options.max, "%.3f", 0);
    }
}

pub inline fn enumSelector(comptime T: type, value: *T, name: [:0]const u8) void {
    switch (@typeInfo(T)) {
        .@"enum" => |@"enum"| if (@typeInfo(@"enum".tag_type) != .int) @compileError("Unexpected tag type."),
        else => @compileError("Unexpected type: " ++ @typeName(T) ++ "."),
    }

    const names: []const u8 = comptime init: {
        var names: []const u8 = "";

        for (@typeInfo(T).@"enum".fields) |field| {
            names = names ++ field.name ++ .{0};
        }

        names = names ++ .{0};

        break :init names;
    };

    var current: i32 = 0;

    inline for (@typeInfo(T).@"enum".fields, 0..) |field, i| {
        if (value.* == @as(T, @enumFromInt(field.value))) {
            current = i;
        }
    }

    if (imgui.ImGui_ComboEx(name, &current, names.ptr, -1)) {
        inline for (@typeInfo(T).@"enum".fields, 0..) |field, i| {
            if (current == i) {
                value.* = @enumFromInt(field.value);
            }
        }
    }
}
