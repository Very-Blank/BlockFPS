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

                            if (imgui.ImGui_Selectable("Inspector")) {
                                data.views.inspector = true;
                            }

                            if (imgui.ImGui_Selectable("Editor")) {
                                data.views.editor = true;
                            }
                        }
                    }

                    imgui.ImGui_Separator();

                    {
                        imgui.ImGui_Text("Game");
                        imgui.ImGui_Indent();
                        defer imgui.ImGui_Unindent();

                        _ = imgui.ImGui_Checkbox("Freeze", &data.game.freeze);

                        imgui.ImGui_PushItemWidth(standards.width);
                        defer imgui.ImGui_PopItemWidth();

                        imgui.ImGui_SameLine();

                        const Mode: type = @FieldType(@FieldType(LauncherData, "game"), "mode");
                        help.enumSelector(Mode, &data.game.mode, "Mode");
                    }
                }

                if (imgui.ImGui_TableNextColumn()) {
                    const old = data.tool.type;
                    const values = std.enums.values(@FieldType(@FieldType(LauncherData, "tool"), "type"));

                    imgui.ImGui_PushFont(icons);
                    defer imgui.ImGui_PopFont();
                    inline for (values) |value| {
                        if (old != value)
                            imgui.ImGui_PushStyleVar(imgui.ImGuiStyleVar_Alpha, imgui.ImGui_GetStyle()[0].Alpha * 0.5);

                        if (imgui.ImGui_ButtonEx(std.fmt.comptimePrint("{u}", .{switch (value) {
                            .select => '',
                            .move => '',
                            .rotate => '',
                            .scale => '',
                        }}), .{ .x = button_size, .y = button_size })) {
                            data.tool.type = value;
                            data.tool.changed = true;
                        } else {
                            data.tool.changed = false;
                        }

                        if (old != value)
                            imgui.ImGui_PopStyleVar();
                    }
                }
            }
        }
    }.draw,
};
