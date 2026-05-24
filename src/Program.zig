const builtin = @import("builtin");
const glad = @import("glad");
const std = @import("std");

const debug: bool = @import("build_options").debug;

const Shader = @import("Shader.zig");

id: u32,

const Self = @This();

pub fn create(options: struct { shaders: []const Shader, allocator: ?std.mem.Allocator = null }) !Self {
    const program: Self = .{
        .id = init_program: {
            const id = glad.glCreateProgram();
            if (id == 0) return error.CreateProgramFailed;
            break :init_program id;
        },
    };

    for (options.shaders) |shader| {
        glad.glAttachShader(program.id, shader.id);

        if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe or debug) switch (glad.glGetError()) {
            glad.GL_NO_ERROR => {},
            else => |err| {
                const info = switch (err) {
                    glad.GL_INVALID_OPERATION => "Shader id is not a shader object or shader is already attached to the program.",
                    else => unreachable,
                };

                std.debug.print("OpenGL error: {s}\n", .{info});

                return error.ShaderSourceFailed;
            },
        };
    }

    glad.glLinkProgram(program.id);

    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe or debug) switch (init_linking_status: {
        var linking_status: i32 = 0;
        glad.glGetProgramiv(program.id, glad.GL_LINK_STATUS, &linking_status);
        break :init_linking_status linking_status;
    }) {
        glad.GL_TRUE => {},
        else => {
            std.debug.print("Linking failed.\n", .{});

            if (options.allocator) |allocator| {
                const info_log_length: u32 = init_length: {
                    var info_log_length: i32 = 0;
                    glad.glGetProgramiv(program.id, glad.GL_INFO_LOG_LENGTH, @ptrCast(&info_log_length));

                    if (info_log_length <= 0) {
                        return error.LoggingFailed;
                    }

                    break :init_length @intCast(info_log_length);
                };

                const log: []u8 = try allocator.alloc(u8, @intCast(info_log_length + 1));
                defer allocator.free(log);

                glad.glGetProgramInfoLog(program.id, @intCast(info_log_length), null, log.ptr);
                std.debug.print("OpenGL error: {s}\n", .{log});
            }

            return error.LinkingFailed;
        },
    };

    return program;
}

pub fn getUniform(self: *const Self, name: [:0]const u8) i32 {
    return glad.glGetUniformLocation(self.id, name.ptr);
}

pub fn use(self: *const Self) void {
    glad.glUseProgram(self.id);
}

///Calls GL delete Program
pub fn destroy(self: *const Self) void {
    glad.glDeleteProgram(self.id);
}
