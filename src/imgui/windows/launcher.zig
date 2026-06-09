const std = @import("std");
const imgui = @import("imgui");
const help = @import("../help.zig");
const standards = @import("../standards.zig");
const Window = @import("../window.zig").Window;

pub const LauncherData = struct {
    tools: struct {
        editor: bool = false,
        inspector: bool = false,
    },
    game: struct {
        freeze: bool = false,
        mode: enum(u32) { normal = 0, cam = 1 } = .normal,
    },
    transfrom_tool: enum { move, rotate, scale } = .move,
};

pub const Launcher = Window(LauncherData);

pub const init: Launcher = .{
    .name = "Launcher",
    .data = .{
        .tools = .{},
        .game = .{},
    },
    .draw_fn = struct {
        pub fn draw(data: *LauncherData) void {
            if (imgui.ImGui_BeginTable("split", 2, 0)) {
                defer imgui.ImGui_EndTable();

                const button_size: f32 = 32.5;

                imgui.ImGui_TableSetupColumn("Left", 0);
                imgui.ImGui_TableSetupColumnEx("Right", imgui.ImGuiTableColumnFlags_WidthFixed, button_size, 0);

                if (imgui.ImGui_TableNextColumn()) {
                    {
                        imgui.ImGui_PushItemWidth(100);
                        defer imgui.ImGui_PopItemWidth();

                        if (imgui.ImGui_BeginCombo("##tools", "Tools", 0)) {
                            defer imgui.ImGui_EndCombo();

                            if (imgui.ImGui_Selectable("Inspector")) {
                                data.tools.inspector = true;
                            }

                            if (imgui.ImGui_Selectable("Editor")) {
                                data.tools.editor = true;
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
                    const old = data.transfrom_tool;

                    if (old != .move)
                        imgui.ImGui_PushStyleVar(imgui.ImGuiStyleVar_Alpha, imgui.ImGui_GetStyle()[0].Alpha * 0.5);

                    if (imgui.ImGui_ButtonEx(std.fmt.comptimePrint("{u}", .{''}), .{ .x = button_size, .y = button_size })) {
                        data.transfrom_tool = .move;
                    }

                    if (old != .move)
                        imgui.ImGui_PopStyleVar();

                    if (old != .rotate)
                        imgui.ImGui_PushStyleVar(imgui.ImGuiStyleVar_Alpha, imgui.ImGui_GetStyle()[0].Alpha * 0.5);

                    if (imgui.ImGui_ButtonEx(std.fmt.comptimePrint("{u}", .{''}), .{ .x = button_size, .y = button_size })) {
                        data.transfrom_tool = .rotate;
                    }

                    if (old != .rotate)
                        imgui.ImGui_PopStyleVar();

                    if (old != .scale)
                        imgui.ImGui_PushStyleVar(imgui.ImGuiStyleVar_Alpha, imgui.ImGui_GetStyle()[0].Alpha * 0.5);

                    if (imgui.ImGui_ButtonEx(std.fmt.comptimePrint("{u}", .{''}), .{ .x = button_size, .y = button_size })) {
                        data.transfrom_tool = .scale;
                    }

                    if (old != .scale)
                        imgui.ImGui_PopStyleVar();
                }
            }
        }
    }.draw,
};
