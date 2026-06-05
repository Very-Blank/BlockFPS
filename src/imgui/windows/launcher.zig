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

                imgui.ImGui_PushItemWidth(standards.width);
                defer imgui.ImGui_PopItemWidth();

                imgui.ImGui_SameLine();
                help.enumSelector(Mode, &data.game.mode, "Mode");
            }
        }
    }.draw,
};
