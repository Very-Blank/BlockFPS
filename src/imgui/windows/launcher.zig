const std = @import("std");
const imgui = @import("imgui");
const help = @import("../help.zig");
const standards = @import("../standards.zig");
const Window = @import("../window.zig").Window;

pub const LauncherData = struct {
    views: struct {
        editor: bool = false,
        inspector: bool = false,
    },
    game: struct {
        freeze: bool = false,
        mode: enum(u32) { normal = 0, cam = 1 } = .normal,
    },
    tool: struct {
        type: enum { select, move, rotate, scale } = .select,
        changed: bool = false,
    },
};

pub const Launcher = Window(LauncherData);

pub const init: Launcher = .{
    .name = "Launcher",
    .data = .{
        .views = .{},
        .game = .{},
        .tool = .{},
    },
    .draw_fn = struct {
        pub fn draw(data: *LauncherData, icons: *imgui.ImFont) void {
        }
    }.draw,
};
