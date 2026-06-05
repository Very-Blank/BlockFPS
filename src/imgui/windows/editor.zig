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

pub const EditorData = struct {
    assets: [][:0]const u8,
    current: u32,
};

pub const Editor = Window(EditorData);

pub const init: Editor = .{
    .name = "Editor",
    .data = {},
    .draw_fn = struct {
        pub fn draw(_: *EditorData) void {
            imgui.ImGui_Text("Hello\n");
        }
    }.draw,
};
