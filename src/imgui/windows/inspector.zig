const std = @import("std");
const math = @import("math");
const imgui = @import("imgui");

const help = @import("../help.zig");
const standards = @import("../standards.zig");

const Window = @import("../window.zig").Window;

const Vector3 = math.f32.Vector3;
const Mat4 = math.f32.Mat4;

const Model = @import("../../components/model.zig").Model;
const Position = @import("../../components/position.zig").Position;
const Rotation = @import("../../components/rotation.zig").Rotation;
const Scale = @import("../../components/scale.zig").Scale;
const Camera = @import("../../components/Camera.zig");
const Collider = @import("../../components/collider.zig").Collider;
const Mask = Collider.Mask;
const Layer = Collider.Layer;
const Rigidbody = @import("../../components/Rigidbody.zig");
const Grounded = @import("../../components/Grounded.zig");
const Health = @import("../../components/Health.zig");
const Bullet = @import("../../components/Bullet.zig");
const Enemy = @import("../../components/Enemy.zig");

pub const InspectorData = struct {
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

pub const Inspector = Window(InspectorData);

pub const init: Inspector = .{
    .name = "Inspector",
    .data = .{},
    .draw_fn = struct {
        pub fn draw(data: *InspectorData) void {
            {
                imgui.ImGui_PushItemWidth(standards.width);
                defer imgui.ImGui_PopItemWidth();

                if (data.position.has and imgui.ImGui_CollapsingHeader("Position", 0)) {
                    imgui.ImGui_Indent();
                    defer imgui.ImGui_Unindent();

                    help.vectorField(Position, &data.position.value, "##pos", .{});
                }

                if (data.rotation.has and imgui.ImGui_CollapsingHeader("Rotation", 0)) {
                    const rotation = &data.rotation.value;

                    imgui.ImGui_Indent();
                    defer imgui.ImGui_Unindent();

                    _ = imgui.ImGui_DragFloatEx("W##rot", @ptrCast(&rotation.fields[0]), 0.005, -1.0, 1.0, "%.3f", 0);
                    _ = imgui.ImGui_DragFloatEx("X##rot", @ptrCast(&rotation.fields[1]), 0.005, -1.0, 1.0, "%.3f", 0);
                    _ = imgui.ImGui_DragFloatEx("Y##rot", @ptrCast(&rotation.fields[2]), 0.005, -1.0, 1.0, "%.3f", 0);
                    _ = imgui.ImGui_DragFloatEx("Z##rot", @ptrCast(&rotation.fields[3]), 0.005, -1.0, 1.0, "%.3f", 0);
                }

                if (data.scale.has and imgui.ImGui_CollapsingHeader("Scale", 0)) {
                    imgui.ImGui_Indent();
                    defer imgui.ImGui_Unindent();

                    help.vectorField(Scale, &data.scale.value, "##pos", .{});
                }
            }

            if (data.model.has and imgui.ImGui_CollapsingHeader("Model", 0)) {
                imgui.ImGui_Indent();
                defer imgui.ImGui_Unindent();

                help.enumSelector(Model, &data.model.value, "Model##enum");
            }

            if (data.collider.has and imgui.ImGui_CollapsingHeader("Collider", 0)) {
                const collider = &data.collider.value;

                imgui.ImGui_Indent();
                defer imgui.ImGui_Unindent();

                help.enumSelector(Layer, &collider.layer, "Layer##col");

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
                            imgui.ImGui_Text(comptime help.pad(help.itoa(i) ++ "-" ++ help.itoa(i + columns - 1), 5, .right));
                            imgui.ImGui_SameLineEx(0, 0);
                        } else {
                            imgui.ImGui_SameLineEx(0, 0);
                        }

                        const bit: i32 = @as(i32, 1) << i;
                        var checked = (mask_int & bit) != 0;

                        if (imgui.ImGui_Checkbox("##mask" ++ (comptime help.itoa(i)), &checked)) {
                            if (checked) mask_int |= bit else mask_int &= ~bit;
                            collider.mask = @enumFromInt(mask_int);
                        }
                    }
                }

                imgui.ImGui_Separator();

                {
                    imgui.ImGui_Indent();
                    defer imgui.ImGui_Unindent();

                    imgui.ImGui_PushItemWidth(standards.width);
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

                imgui.ImGui_PushItemWidth(standards.width);
                defer imgui.ImGui_PopItemWidth();

                if (imgui.ImGui_CollapsingHeader("Velocity", 0)) {
                    imgui.ImGui_Indent();
                    defer imgui.ImGui_Unindent();

                    help.vectorField(Vector3, &rigidbody.velocity, "##rb", .{});
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

                imgui.ImGui_PushItemWidth(standards.width);
                defer imgui.ImGui_PopItemWidth();

                _ = imgui.ImGui_DragFloat("Current##hp", @ptrCast(&hp.current));
                _ = imgui.ImGui_DragFloat("Max##hp", @ptrCast(&hp.max));
            }
        }
    }.draw,
};
