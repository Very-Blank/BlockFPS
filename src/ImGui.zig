const imgui = @import("imgui");

const Window = @import("Window.zig");

io: *imgui.struct_ImGuiIO_t,
context: *imgui.ImGuiContext,

const Self = @This();

/// Dark is default.
pub const Style = enum {
    dark,
    light,
    classic,
};

pub fn GuiWindow(comptime T: type) type {
    return struct {
        name: [:0]const u8,
        open: bool = true,
        flags: i32 = 0,
        data: T,
        draw: *const fn (data: *T) void,

        pub inline fn drawWindow(self: *@This()) void {
            if (self.open) {
                if (imgui.ImGui_Begin(self.name, &(self.open), self.flags))
                    self.draw(&self.data);
                imgui.ImGui_End();
            }
        }
    };
}

pub fn init(window: Window) Self {
    var new_imgui: Self = .{
        .io = undefined,
        .context = undefined,
    };

    new_imgui.context = imgui.ImGui_CreateContext(null).?;
    _ = imgui.cImGui_ImplGlfw_InitForOpenGL(@ptrCast(window.ptr), true);
    _ = imgui.cImGui_ImplOpenGL3_Init();

    new_imgui.io = imgui.ImGui_GetIO();

    return new_imgui;
}

pub inline fn deinit(self: *Self) void {
    imgui.cImGui_ImplOpenGL3_Shutdown();
    imgui.cImGui_ImplGlfw_Shutdown();
    imgui.ImGui_DestroyContext(self.context);

    self.context = undefined;
    self.io = undefined;
}

pub inline fn setStyle(_: *Self, style: Style) void {
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
pub inline fn endFrame(_: *Self) void {
    imgui.ImGui_EndFrame();
}

pub inline fn render(_: *Self) void {
    imgui.ImGui_Render();
    imgui.cImGui_ImplOpenGL3_RenderDrawData(imgui.ImGui_GetDrawData());
}
