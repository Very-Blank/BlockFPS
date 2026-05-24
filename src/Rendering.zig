const std = @import("std");
const glad = @import("glad");
const math = @import("math");
const ecs = @import("ecs");

const Io = std.Io;

const Shader = @import("Shader.zig");
const Program = @import("Program.zig");

const Model = @import("components/Model.zig");
const Position = @import("components/position.zig").Position;
const Rotation = @import("components/rotation.zig").Rotation;
const Scale = @import("components/scale.zig").Scale;

const Ecs = @import("ecs.zig").Ecs;

program: Program,

const Self = @This();

pub fn init(io: Io, allocator: std.mem.Allocator) !Self {
    const vertex = init_vertex: {
        const buffer: [:0]const u8 = try Io.Dir.cwd().readFileAllocOptions(io, "shaders/vertex.glsl", allocator, .unlimited, .@"1", 0);
        defer allocator.free(buffer);
        break :init_vertex try Shader.create(.{ .type = .vertex, .source = buffer, .allocator = allocator });
    };

    defer vertex.destroy();

    const fragment = init_vertex: {
        const buffer: [:0]const u8 = try Io.Dir.cwd().readFileAllocOptions(io, "shaders/fragment.glsl", allocator, .unlimited, .@"1", 0);
        defer allocator.free(buffer);
        break :init_vertex try Shader.create(.{ .type = .fragment, .source = buffer, .allocator = allocator });
    };

    defer fragment.destroy();

    return .{
        .program = try Program.create(.{ .shaders = &.{ vertex, fragment }, .allocator = allocator }),
    };
}

pub fn deinit(self: *const Self) void {
    self.program.destroy();
}

pub fn draw(self: *const Self, iterator: *Ecs.TupleIterator(.{
    .include = ecs.Template{ .components = &.{ Position, Scale, Rotation, Model } },
})) void {
    while (iterator.next()) |tuple| {
        var mat: math.f32.Mat4 = .initModel(tuple[0].*, tuple[1].*, tuple[2].*);
        glad.glUniformMatrix4fv(self.program.getUniform("model"), 1, glad.GL_FALSE, &mat.fields[0][0]);

        tuple[3].draw();
    }
}

pub fn startRender(self: *const Self) void {
    self.program.use();
}
