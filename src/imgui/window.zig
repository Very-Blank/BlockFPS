const imgui = @import("imgui");

pub fn Window(comptime T: type) type {
    return struct {
        name: [:0]const u8,
        open: bool = false,
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
