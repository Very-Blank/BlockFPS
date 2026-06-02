const std = @import("std");
const glad = @import("glad");
const math = @import("math");
const ecs = @import("ecs");

const Io = std.Io;

const Shader = @import("Shader.zig");
const Program = @import("Program.zig");

const Model = @import("components/Model.zig");
const ModelInstance = @import("components/model_instance.zig").ModelInstance;
const Position = @import("components/position.zig").Position;
const Rotation = @import("components/rotation.zig").Rotation;
const Scale = @import("components/scale.zig").Scale;
const Camera = @import("components/Camera.zig");

const Ecs = @import("ecs.zig").Ecs;
const SingletonType = ecs.SingletonType;

program: Program,
model_instances: [1]Model,

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
        .model_instances = .{
            Model.init(Model.cube),
        },
    };
}

pub fn deinit(self: *const Self) void {
    self.program.destroy();
}

pub fn render(self: *const Self, ecs_engine: *Ecs, player_singleton: SingletonType) void {
    var view: math.f32.Mat4, var projection: math.f32.Mat4 = init: {
        if (ecs_engine.getSingletonsEntity(player_singleton)) |id| {
            const position = ecs_engine.getEntityComponent(id, Position) catch unreachable;
            const camera = ecs_engine.getEntityComponent(id, Camera) catch unreachable;

            break :init .{
                math.f32.Mat4.initView(
                    position.add(Position{ .y = camera.offset }).negate(),
                    math.f32.Quaternion.initCamRotation(-camera.rotation.yaw, -camera.rotation.pitch),
                ),
                camera.projection.mat,
            };
        }

        break :init .{ .identity, .identity };
    };

    self.startRender();

    glad.glUniformMatrix4fv(self.program.getUniform("view"), 1, glad.GL_FALSE, &view.fields[0][0]);
    glad.glUniformMatrix4fv(self.program.getUniform("projection"), 1, glad.GL_FALSE, &projection.fields[0][0]);

    render: {
        var tuple_iterator = ecs_engine.getTupleIterator(.{
            .include = ecs.Template{ .components = &.{ Position, Scale, Rotation, Model } },
        }) orelse break :render;

        self.drawModels(&tuple_iterator);
    }

    render: {
        var tuple_iterator = ecs_engine.getTupleIterator(.{
            .include = ecs.Template{ .components = &.{ Position, Scale, Rotation, ModelInstance } },
        }) orelse break :render;

        self.drawIntances(&tuple_iterator);
    }
}

pub fn drawModels(self: *const Self, iterator: *Ecs.TupleIterator(.{
    .include = ecs.Template{ .components = &.{ Position, Scale, Rotation, Model } },
})) void {
    std.debug.assert(started_rendering: {
        var current: i32 = 0;
        glad.glGetIntegerv(glad.GL_CURRENT_PROGRAM, &current);
        break :started_rendering current == @as(i32, @intCast(self.program.id));
    });

    const location = self.program.getUniform("model");
    while (iterator.next()) |tuple| {
        const mat: math.f32.Mat4 = .initModel(tuple[0].*, tuple[1].*, tuple[2].*);
        glad.glUniformMatrix4fv(location, 1, glad.GL_FALSE, &mat.fields[0][0]);

        tuple[3].draw();
    }
}

pub fn drawIntances(self: *const Self, iterator: *Ecs.TupleIterator(.{
    .include = ecs.Template{ .components = &.{ Position, Scale, Rotation, ModelInstance } },
})) void {
    std.debug.assert(started_rendering: {
        var current: i32 = 0;
        glad.glGetIntegerv(glad.GL_CURRENT_PROGRAM, &current);
        break :started_rendering current == @as(i32, @intCast(self.program.id));
    });

    const location = self.program.getUniform("model");

    var mat: math.f32.Mat4 = .identity;
    var last_instance: ModelInstance = init: {
        if (iterator.next()) |tuple| {
            mat = .initModel(tuple[0].*, tuple[1].*, tuple[2].*);
            glad.glUniformMatrix4fv(location, 1, glad.GL_FALSE, &mat.fields[0][0]);

            self.model_instances[@intFromEnum(tuple[3].*)].bindVertex();
            self.model_instances[@intFromEnum(tuple[3].*)].drawElements();

            break :init tuple[3].*;
        }

        return;
    };

    while (iterator.next()) |tuple| {
        mat = .initModel(tuple[0].*, tuple[1].*, tuple[2].*);
        glad.glUniformMatrix4fv(location, 1, glad.GL_FALSE, &mat.fields[0][0]);

        if (last_instance == tuple[3].*) {
            self.model_instances[@intFromEnum(last_instance)].drawElements();
        } else {
            last_instance = tuple[3].*;
            self.model_instances[@intFromEnum(last_instance)].bindVertex();
            self.model_instances[@intFromEnum(last_instance)].drawElements();
        }
    }
}

pub fn startRender(self: *const Self) void {
    self.program.use();
}
