const std = @import("std");
const ecs = @import("ecs");
const math = @import("math");
const imgui = @import("imgui");

const Ecs = @import("ecs.zig").Ecs;
const SingletonType = ecs.SingletonType;

const Physics = @import("Physics.zig");

const Vector3 = math.f32.Vector3;
const Mat4 = math.f32.Mat4;

const Window = @import("Window.zig");

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

const width = 150.0;

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

pub fn rightPad(comptime value: [:0]const u8, comptime len: usize) [:0]const u8 {
    comptime var string: [:0]const u8 = value;
    while (string.len < len) {
        string = string ++ " ";
    }

    return string;
}

inline fn enumSelector(comptime T: type, value: *T, name: [:0]const u8) void {
    switch (@typeInfo(T)) {
        .@"enum" => {},
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

    imgui.ImGui_PushItemWidth(width);

    if (imgui.ImGui_ComboEx(name, &current, names.ptr, -1)) {
        inline for (@typeInfo(T).@"enum".fields, 0..) |field, i| {
            if (current == i) {
                value.* = @enumFromInt(field.value);
            }
        }
    }

    imgui.ImGui_PopItemWidth();
}

io: *imgui.struct_ImGuiIO_t,
context: *imgui.ImGuiContext,
launcher: GuiWindow(LauncherData) = .{
    .name = "Launcher",
    .data = .{
        .tools = .{},
        .game = .{},
    },
    .draw_fn = struct {
        pub fn draw(data: *LauncherData) void {
            {
                imgui.ImGui_Text("Tools");
                imgui.ImGui_Indent();
                defer imgui.ImGui_Unindent();

                data.tools.inspector = imgui.ImGui_Button("Inspector");
                imgui.ImGui_SameLine();
                data.tools.editor = imgui.ImGui_Button("Editor");
            }

            imgui.ImGui_Separator();

            {
                imgui.ImGui_Text("Game");
                imgui.ImGui_Indent();
                defer imgui.ImGui_Unindent();

                _ = imgui.ImGui_Checkbox("Freeze", &data.game.freeze);

                const Mode: type = @FieldType(@FieldType(LauncherData, "game"), "mode");

                imgui.ImGui_PushItemWidth(width);
                defer imgui.ImGui_PopItemWidth();

                imgui.ImGui_SameLine();
                enumSelector(Mode, &data.game.mode, "Mode");
            }
        }
    }.draw,
},
tools: struct {
    editor: GuiWindow(void) = .{
        .name = "Editor",
        .data = {},
        .draw_fn = struct {
            pub fn draw(_: *void) void {
                imgui.ImGui_Text("Hello\n");
            }
        }.draw,
    },
    inspector: GuiWindow(InspectorData) = .{
        .name = "Inspector",
        .data = .{},
        .draw_fn = struct {
            pub fn draw(data: *InspectorData) void {
                {
                    imgui.ImGui_PushItemWidth(width);
                    defer imgui.ImGui_PopItemWidth();

                    if (data.position.has and imgui.ImGui_CollapsingHeader("Position", 0)) {
                        const position = &data.position.value;

                        imgui.ImGui_Indent();
                        defer imgui.ImGui_Unindent();

                        _ = imgui.ImGui_DragFloatEx("X##pos", @ptrCast(&position.x), 0.01, -1000.0, 1000.0, "%.3f", 0);
                        _ = imgui.ImGui_DragFloatEx("Y##pos", @ptrCast(&position.y), 0.01, -1000.0, 1000.0, "%.3f", 0);
                        _ = imgui.ImGui_DragFloatEx("Z##pos", @ptrCast(&position.z), 0.01, -1000.0, 1000.0, "%.3f", 0);
                    }

                    if (data.rotation.has and imgui.ImGui_CollapsingHeader("Rotation", 0)) {
                        const rotation = &data.rotation.value;

                        imgui.ImGui_Indent();
                        defer imgui.ImGui_Unindent();

                        _ = imgui.ImGui_DragFloatEx("X##rot", @ptrCast(&rotation.fields[0]), 0.005, -1.0, 1.0, "%.3f", 0);
                        _ = imgui.ImGui_DragFloatEx("Y##rot", @ptrCast(&rotation.fields[1]), 0.005, -1.0, 1.0, "%.3f", 0);
                        _ = imgui.ImGui_DragFloatEx("Z##rot", @ptrCast(&rotation.fields[2]), 0.005, -1.0, 1.0, "%.3f", 0);
                        _ = imgui.ImGui_DragFloatEx("W##rot", @ptrCast(&rotation.fields[3]), 0.005, -1.0, 1.0, "%.3f", 0);
                    }

                    if (data.scale.has and imgui.ImGui_CollapsingHeader("Scale", 0)) {
                        const scale = &data.scale.value;

                        imgui.ImGui_Indent();
                        defer imgui.ImGui_Unindent();

                        _ = imgui.ImGui_DragFloatEx("X##scale", @ptrCast(&scale.x), 0.01, 0.0, 100.0, "%.3f", 0);
                        _ = imgui.ImGui_DragFloatEx("Y##scale", @ptrCast(&scale.y), 0.01, 0.0, 100.0, "%.3f", 0);
                        _ = imgui.ImGui_DragFloatEx("Z##scale", @ptrCast(&scale.z), 0.01, 0.0, 100.0, "%.3f", 0);
                    }
                }

                if (data.model.has and imgui.ImGui_CollapsingHeader("Model", 0)) {
                    imgui.ImGui_Indent();
                    defer imgui.ImGui_Unindent();

                    enumSelector(Model, &data.model.value, "Model##enum");
                }

                if (data.collider.has and imgui.ImGui_CollapsingHeader("Collider", 0)) {
                    const collider = &data.collider.value;

                    imgui.ImGui_Indent();
                    defer imgui.ImGui_Unindent();

                    enumSelector(Layer, &collider.layer, "Layer##col");

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
                                imgui.ImGui_Text(comptime rightPad(itoa(i) ++ "-" ++ itoa(i + columns - 1), 5));
                                imgui.ImGui_SameLineEx(0, 0);
                            } else {
                                imgui.ImGui_SameLineEx(0, 0);
                            }

                            const bit: i32 = @as(i32, 1) << i;
                            var checked = (mask_int & bit) != 0;

                            if (imgui.ImGui_Checkbox("##mask" ++ (comptime itoa(i)), &checked)) {
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

                        if (imgui.ImGui_ComboEx("Shape##col", &current_shape, shape_names.ptr, -1)) {
                            collider.type = switch (current_shape) {
                                0 => .{ .sphere = .{ .radius = 1.0 } },
                                1 => .{ .capsule = .{ .radius = 0.5, .half_height = 1.0 } },
                                else => .{ .box = .{ .x = 1.0, .y = 1.0, .z = 1.0 } },
                            };
                        }

                        switch (collider.type) {
                            .sphere => |*sphere| _ = imgui.ImGui_DragFloat("Radius##sph", @ptrCast(&sphere.radius)),
                            .capsule => |*capsule| {
                                _ = imgui.ImGui_DragFloat("Radius##cap", @ptrCast(&capsule.radius));
                                _ = imgui.ImGui_DragFloat("Height##cap", @ptrCast(&capsule.half_height));
                            },
                            .box => |*box| {
                                _ = imgui.ImGui_DragFloat("Width##box", @ptrCast(&box.x));
                                _ = imgui.ImGui_DragFloat("Height##box", @ptrCast(&box.y));
                                _ = imgui.ImGui_DragFloat("Depth##box", @ptrCast(&box.z));
                            },
                        }
                    }
                }

                if (data.rigidbody.has and imgui.ImGui_CollapsingHeader("Rigidbody", 0)) {
                    const rigidbody = &data.rigidbody.value;

                    imgui.ImGui_Indent();
                    defer imgui.ImGui_Unindent();

                    imgui.ImGui_PushItemWidth(width);
                    defer imgui.ImGui_PopItemWidth();

                    if (imgui.ImGui_CollapsingHeader("Velocity", 0)) {
                        imgui.ImGui_Indent();
                        defer imgui.ImGui_Unindent();

                        _ = imgui.ImGui_DragFloatEx("X##rb", @ptrCast(&rigidbody.velocity.x), 0.01, -1000.0, 1000.0, "%.3f", 0);
                        _ = imgui.ImGui_DragFloatEx("Y##rb", @ptrCast(&rigidbody.velocity.y), 0.01, -1000.0, 1000.0, "%.3f", 0);
                        _ = imgui.ImGui_DragFloatEx("Z##rb", @ptrCast(&rigidbody.velocity.z), 0.01, -1000.0, 1000.0, "%.3f", 0);
                    }

                    imgui.ImGui_Separator();

                    _ = imgui.ImGui_DragFloat("Gravity##rb", @ptrCast(&rigidbody.gravity));
                    _ = imgui.ImGui_DragFloat("Mass##rb", @ptrCast(&rigidbody.mass));
                    _ = imgui.ImGui_DragFloat("Restitution##rb", @ptrCast(&rigidbody.restitution));
                }

                if (data.grounded.has and imgui.ImGui_CollapsingHeader("Grounded", 0)) {
                    const grounded = &data.grounded.value;
                    imgui.ImGui_Indent();
                    defer imgui.ImGui_Unindent();

                    _ = imgui.ImGui_Checkbox("Grounded##gnd", &grounded.grounded);
                }

                if (data.health.has and imgui.ImGui_CollapsingHeader("Health", 0)) {
                    const hp = &data.health.value;

                    imgui.ImGui_Indent();
                    defer imgui.ImGui_Unindent();

                    imgui.ImGui_PushItemWidth(width);
                    defer imgui.ImGui_PopItemWidth();

                    _ = imgui.ImGui_DragFloat("Current##hp", @ptrCast(&hp.current));
                    _ = imgui.ImGui_DragFloat("Max##hp", @ptrCast(&hp.max));
                }
            }
        }.draw,
    },
},
open_states: [2]bool = .{false} ** 2,
selection: struct {
    singleton: SingletonType,
    position: Vector3,
},
state: State = .closed,
// TODO: Add position for spawning stuff.

const Self = @This();

pub fn GuiWindow(comptime T: type) type {
    return struct {
        name: [:0]const u8,
        open: bool = false,
        state: State = .closed,
        flags: i32 = 0,
        data: T,
        draw_fn: *const fn (data: *T) void,

        pub inline fn draw(self: *@This()) void {
            if (self.open) {
                if (imgui.ImGui_Begin(self.name, &(self.open), self.flags))
                    self.draw_fn(&self.data);
                imgui.ImGui_End();
            }
        }
    };
}

pub const LauncherData: type = struct {
    tools: struct {
        editor: bool = false,
        inspector: bool = false,
    },
    game: struct {
        freeze: bool = false,
        mode: enum(u32) { normal = 0, cam = 1 } = .normal,
    },
};

pub const InspectorData: type = struct {
    pub fn Value(comptime T: type) type {
        return struct {
            value: T,
            has: bool = false,
        };
    }

    position: Value(Position) = .{ .value = .zero },
    rotation: Value(Rotation) = .{ .value = .identity },
    scale: Value(Scale) = .{ .value = .zero },
    model: Value(Model) = .{ .value = .cube },
    collider: Value(Collider) = .{ .value = Collider{ .type = .{ .sphere = .{ .radius = 0.0 } } } },
    rigidbody: Value(Rigidbody) = .{ .value = .{} },
    grounded: Value(Grounded) = .{ .value = .{} },
    health: Value(Health) = .{ .value = .{ .current = 0.0, .max = 0.0 } },
};

pub const State = enum {
    just_opened,
    open,
    just_closed,
    closed,

    pub inline fn isOpen(state: State) bool {
        return (state == .just_opened or state == .open);
    }

    pub inline fn update(self: *State, is_open: bool) void {
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
};

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
