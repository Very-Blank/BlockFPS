const imgui = @import("imgui");

pub fn Window(comptime T: type) type {
    return struct {
        name: [:0]const u8,
        open: bool = false,
        flags: i32 = 0,
        data: T,
        draw_fn: *const fn (data: *T, icons: *imgui.ImFont) void,

        pub inline fn draw(self: *@This(), icons: *imgui.ImFont) void {
            if (self.open) {
                if (imgui.ImGui_Begin(self.name, &(self.open), self.flags))
                    self.draw_fn(&self.data, icons);
                imgui.ImGui_End();
            }
        }
    };
}
