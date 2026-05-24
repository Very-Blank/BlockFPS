const builtin = @import("builtin");
const glad = @import("glad");
const std = @import("std");

const debug: bool = @import("build_options").debug;

id: u32,

const Self = @This();

pub const ShaderType = enum(c_uint) {
    compute = glad.GL_COMPUTE_SHADER,
    vertex = glad.GL_VERTEX_SHADER,
    tess_control = glad.GL_TESS_CONTROL_SHADER,
    tess_evaluation = glad.GL_TESS_EVALUATION_SHADER,
    geometry = glad.GL_GEOMETRY_SHADER,
    fragment = glad.GL_FRAGMENT_SHADER,

    pub inline fn value(@"enum": ShaderType) c_uint {
        return @intFromEnum(@"enum");
    }

    pub fn name(@"enum": ShaderType) []const u8 {
        return switch (@"enum") {
            .compute => "Compute shader",
            .vertex => "Vertex shader",
            .tess_control => "Tess control shader",
            .tess_evaluation => "Tess evalution shader",
            .geometry => "Geometry shader",
            .fragment => "Fragment shader",
        };
    }
};

pub fn create(options: struct { type: ShaderType, source: [:0]const u8, allocator: ?std.mem.Allocator = null }) !Self {
    const shader: Self = .{
        .id = init_shader: {
            const id = glad.glCreateShader(options.type.value());
            if (id == 0) return error.CreateShaderFailed;
            break :init_shader id;
        },
    };

    errdefer shader.destroy();

    glad.glShaderSource(shader.id, 1, &options.source.ptr, null);

    glad.glCompileShader(shader.id);

    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe or debug) switch (init: {
        var compile_status: u32 = 0;
        glad.glGetShaderiv(shader.id, glad.GL_COMPILE_STATUS, @ptrCast(&compile_status));
        break :init compile_status;
    }) {
        glad.GL_TRUE => {},
        else => {
            std.debug.print("{s} compilation failed.\n", .{options.type.name()});

            if (options.allocator) |allocator| {
                const info_log_length: u32 = init_length: {
                    var info_log_length: i32 = 0;
                    glad.glGetShaderiv(shader.id, glad.GL_INFO_LOG_LENGTH, @ptrCast(&info_log_length));
                    if (info_log_length <= 0) {
                        return error.LoggingFailed;
                    }

                    break :init_length @intCast(info_log_length);
                };

                const log: []u8 = try allocator.alloc(u8, @intCast(info_log_length));
                defer allocator.free(log);

                glad.glGetShaderInfoLog(shader.id, @intCast(info_log_length), null, log.ptr);

                std.debug.print("OpenGL log: {s}\n", .{log});
            }

            return error.ShaderCompilationFailed;
        },
    };

    return shader;
}

pub fn destroy(self: *const Self) void {
    glad.glDeleteShader(self.id);
}
