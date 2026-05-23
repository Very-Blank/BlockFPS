const std = @import("std");
const glfw = @import("glfw");
const glad = @import("glad");
// const math = @import("math");

pub const Window = struct {
    ptr: *glfw.GLFWwindow,
    width: i32,
    height: i32,
    input: Input,

    export fn errorCallback(err: c_int, description: [*c]const u8) void {
        std.debug.panic("GLFW Error {any}: {s}\n", .{ err, description });
    }

    pub fn init(name: []const u8, width: i32, height: i32) !Window {
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);

        _ = glfw.glfwSetErrorCallback(errorCallback);

        if (glfw.glfwInit() == glfw.GL_FALSE) {
            std.debug.print("Failed to initialize GLFW\n", .{});
            return error.GlfwInitFailed;
        }

        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3);
        glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);

        const window: Window = Window{
            .ptr = init: {
                if (glfw.glfwCreateWindow(width, height, name.ptr, null, null)) |ptr| {
                    break :init ptr;
                }

                std.debug.print("Failed to create GLFW window\n", .{});
                glfw.glfwTerminate();

                return error.WindowCreateFailed;
            },
            .width = width,
            .height = height,
            .input = .init(),
        };

        glfw.glfwMakeContextCurrent(window.ptr);
        glfw.glfwSetInputMode(window.ptr, glfw.GLFW_CURSOR, glfw.GLFW_CURSOR_DISABLED);

        if (glad.gladLoadGL() == 0) {
            std.debug.print("Failed to initialize GLAD\n", .{});
            return error.GladLoadGLFailed;
        }

        glad.glViewport(0, 0, @intCast(width), @intCast(height));

        // glad.glEnable(glad.GL_BLEND);
        // glad.glBlendFunc(glad.GL_SRC_ALPHA, glad.GL_FUNC_ADD);
        glad.glEnable(glad.GL_DEPTH_TEST);
        glad.glDepthFunc(glad.GL_LESS);
        glad.glPointSize(5.0);

        return window;
    }

    pub fn setCallbacks(self: *Window) void {
        glfw.glfwSetWindowUserPointer(self.ptr, self);
        _ = glfw.glfwSetWindowSizeCallback(self.ptr, windowSizeCallback);

        // NOTE: We have to sync window size.
        var newHeight: c_int = 0;
        var newWidth: c_int = 0;
        glfw.glfwGetFramebufferSize(self.ptr, &newWidth, &newHeight);
        windowSizeCallback(self.ptr, newWidth, newHeight);

        _ = glfw.glfwSetKeyCallback(self.ptr, keyCallback);
        _ = glfw.glfwSetMouseButtonCallback(self.ptr, mouseButtonCallback);
        _ = glfw.glfwSetCursorPosCallback(self.ptr, mousePositionCallback);
    }

    // GLFWwindow* window, int width, int height
    export fn windowSizeCallback(glfw_window: ?*glfw.GLFWwindow, width: c_int, height: c_int) void {
        const window: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(glfw_window).?));

        window.width = width;
        window.height = height;

        glad.glViewport(0, 0, @intCast(window.width), @intCast(window.height));
    }

    export fn keyCallback(glfw_window: ?*glfw.GLFWwindow, key: c_int, _: c_int, action: c_int, _: c_int) void {
        const window: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(glfw_window).?));

        const index = KeysType.getIndex(key) catch return;
        window.input.key_states[index] = window.input.key_states[index].updateKeyState(action == glfw.GLFW_PRESS or action == glfw.GLFW_REPEAT);
    }

    export fn mouseButtonCallback(glfw_window: ?*glfw.GLFWwindow, key: c_int, action: c_int, _: c_int) void {
        const window: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(glfw_window).?));

        if (key == glfw.GLFW_MOUSE_BUTTON_LEFT) {
            window.input.mouse_state.left_click = window.input.mouse_state.left_click.updateKeyState(action == glfw.GLFW_PRESS or action == glfw.GLFW_REPEAT);
        }

        if (key == glfw.GLFW_MOUSE_BUTTON_RIGHT) {
            window.input.mouse_state.right_click = window.input.mouse_state.right_click.updateKeyState(action == glfw.GLFW_PRESS or action == glfw.GLFW_REPEAT);
        }
    }

    export fn mousePositionCallback(glfw_window: ?*glfw.GLFWwindow, xpos: f64, ypos: f64) void {
        const window: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(glfw_window).?));

        var xscale: f32 = 0.0;
        var yscale: f32 = 0.0;
        glfw.glfwGetWindowContentScale(window.ptr, &xscale, &yscale);

        const mouse_position: math.f32.Vector2 = .{
            .x = @as(f32, @floatCast(xpos)) / (@as(f32, @floatFromInt(window.width)) / (2 * xscale)) - 1,
            .y = -(@as(f32, @floatCast(ypos)) / (@as(f32, @floatFromInt(window.height)) / (2 * yscale)) - 1),
        };

        window.input.mouse_state.motion = mouse_position.subtract(window.input.mouse_state.position);
        window.input.mouse_state.position = mouse_position;
    }

    pub inline fn run(self: *const Window) bool {
        return glfw.glfwWindowShouldClose(self.ptr) == glfw.GLFW_FALSE;
    }

    pub inline fn close(self: *const Window) void {
        return glfw.glfwSetWindowShouldClose(self.ptr, glfw.GLFW_TRUE);
    }

    pub fn swapAndPoll(self: *Window) void {
        self.input.mouse_state.motion = .{ .x = 0.0, .y = 0.0 };

        inline for (.{ &self.input.mouse_state.left_click, &self.input.mouse_state.right_click }) |key| {
            switch (key.*) {
                .justPressed => key.* = .pressed,
                .justReleased => key.* = .released,
                else => {},
            }
        }

        glfw.glfwSwapBuffers(self.ptr);
        glfw.glfwPollEvents();
    }

    pub fn deinit(self: *const Window) void {
        glfw.glfwDestroyWindow(self.ptr);
        glfw.glfwTerminate();
    }
};

const KeysType = enum(c_int) {
    space = glfw.GLFW_KEY_SPACE,
    @"0" = glfw.GLFW_KEY_0,
    @"1" = glfw.GLFW_KEY_1,
    @"2" = glfw.GLFW_KEY_2,
    @"3" = glfw.GLFW_KEY_3,
    @"4" = glfw.GLFW_KEY_4,
    @"5" = glfw.GLFW_KEY_5,
    @"6" = glfw.GLFW_KEY_6,
    @"7" = glfw.GLFW_KEY_7,
    @"8" = glfw.GLFW_KEY_8,
    @"9" = glfw.GLFW_KEY_9,
    a = glfw.GLFW_KEY_A,
    b = glfw.GLFW_KEY_B,
    c = glfw.GLFW_KEY_C,
    d = glfw.GLFW_KEY_D,
    e = glfw.GLFW_KEY_E,
    f = glfw.GLFW_KEY_F,
    g = glfw.GLFW_KEY_G,
    h = glfw.GLFW_KEY_H,
    i = glfw.GLFW_KEY_I,
    j = glfw.GLFW_KEY_J,
    k = glfw.GLFW_KEY_K,
    l = glfw.GLFW_KEY_L,
    m = glfw.GLFW_KEY_M,
    n = glfw.GLFW_KEY_N,
    o = glfw.GLFW_KEY_O,
    p = glfw.GLFW_KEY_P,
    q = glfw.GLFW_KEY_Q,
    r = glfw.GLFW_KEY_R,
    s = glfw.GLFW_KEY_S,
    t = glfw.GLFW_KEY_T,
    u = glfw.GLFW_KEY_U,
    v = glfw.GLFW_KEY_V,
    w = glfw.GLFW_KEY_W,
    x = glfw.GLFW_KEY_X,
    y = glfw.GLFW_KEY_Y,
    z = glfw.GLFW_KEY_Z,
    escape = glfw.GLFW_KEY_ESCAPE,
    enter = glfw.GLFW_KEY_ENTER,
    tab = glfw.GLFW_KEY_TAB,
    backspace = glfw.GLFW_KEY_BACKSPACE,
    right = glfw.GLFW_KEY_RIGHT,
    left = glfw.GLFW_KEY_LEFT,
    down = glfw.GLFW_KEY_DOWN,
    up = glfw.GLFW_KEY_UP,
    caps_lock = glfw.GLFW_KEY_CAPS_LOCK,
    f1 = glfw.GLFW_KEY_F1,
    f2 = glfw.GLFW_KEY_F2,
    f3 = glfw.GLFW_KEY_F3,
    f4 = glfw.GLFW_KEY_F4,
    f5 = glfw.GLFW_KEY_F5,
    f6 = glfw.GLFW_KEY_F6,
    f7 = glfw.GLFW_KEY_F7,
    f8 = glfw.GLFW_KEY_F8,
    f9 = glfw.GLFW_KEY_F9,
    f10 = glfw.GLFW_KEY_F10,
    f11 = glfw.GLFW_KEY_F11,
    f12 = glfw.GLFW_KEY_F12,
    left_shift = glfw.GLFW_KEY_LEFT_SHIFT,
    left_control = glfw.GLFW_KEY_LEFT_CONTROL,
    left_alt = glfw.GLFW_KEY_LEFT_ALT,
    left_super = glfw.GLFW_KEY_LEFT_SUPER,
    right_shift = glfw.GLFW_KEY_RIGHT_SHIFT,
    right_control = glfw.GLFW_KEY_RIGHT_CONTROL,
    right_alt = glfw.GLFW_KEY_RIGHT_ALT,
    right_super = glfw.GLFW_KEY_RIGHT_SUPER,

    pub inline fn make(int: c_int) KeysType {
        return @enumFromInt(int);
    }

    pub inline fn value(@"enum": KeysType) c_int {
        return @intFromEnum(@"enum");
    }

    pub fn getIndex(key: anytype) !u32 {
        switch (@TypeOf(key)) {
            c_int => {
                inline for (@typeInfo(KeysType).@"enum".fields, 0..) |field, i| {
                    if (field.value == key) return i;
                }

                return error.InvalidKey;
            },
            KeysType => {
                inline for (@typeInfo(KeysType).@"enum".fields, 0..) |field, i| {
                    if (field.value == @intFromEnum(key)) return i;
                }
            },
            *const KeysType => {
                inline for (@typeInfo(KeysType).@"enum".fields, 0..) |field, i| {
                    if (field.value == @intFromEnum(key.*)) return i;
                }
            },
            else => @compileError("Expected a c_int or a KeysType: " ++ @typeName(@TypeOf(key)) ++ "."),
        }

        unreachable;
    }
};

const KeyStateType = enum {
    justPressed,
    pressed,
    justReleased,
    released,

    pub inline fn isDown(keyState: KeyStateType) bool {
        return keyState == .justPressed or keyState == .pressed;
    }

    pub inline fn isUp(keyState: KeyStateType) bool {
        return keyState == .justReleased or keyState == .released;
    }

    pub inline fn updateKeyState(keyState: KeyStateType, press: bool) KeyStateType {
        if (press) {
            return switch (keyState) {
                .justPressed => .pressed,
                .pressed => .pressed,
                .justReleased => .justPressed,
                .released => .justPressed,
            };
        }

        return switch (keyState) {
            .justPressed => .justReleased,
            .pressed => .justReleased,
            .justReleased => .released,
            .released => .released,
        };
    }
};

const Mouse = struct {
    position: math.f32.Vector2,
    motion: math.f32.Vector2,
    right_click: KeyStateType,
    left_click: KeyStateType,
};

pub const Input = struct {
    key_states: [@typeInfo(KeysType).@"enum".fields.len]KeyStateType,
    mouse_state: Mouse,

    pub fn init() Input {
        return .{
            .key_states = .{KeyStateType.released} ** @typeInfo(KeysType).@"enum".fields.len,
            .mouse_state = Mouse{
                .position = math.f32.Vector2.zero,
                .motion = math.f32.Vector2.zero,
                .right_click = KeyStateType.released,
                .left_click = KeyStateType.released,
            },
        };
    }

    pub inline fn getKeyState(self: *Input, key: KeysType) KeyStateType {
        return self.key_states[key.getIndex() catch unreachable];
    }
};
