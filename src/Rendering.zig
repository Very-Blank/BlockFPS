const std = @import("std");
const glad = @import("glad");
const math = @import("math");
const ecs = @import("ecs");

const Io = std.Io;

const Shader = @import("Shader.zig");
const Program = @import("Program.zig");
const Model = @import("Model.zig");
const Texture = @import("Texture.zig");

const ModelComponent = @import("components/model.zig").Model;
const Position = @import("components/position.zig").Position;
const Rotation = @import("components/rotation.zig").Rotation;
const Scale = @import("components/scale.zig").Scale;
const Camera = @import("components/Camera.zig");

const Ecs = @import("ecs.zig").Ecs;
const SingletonType = ecs.SingletonType;

programs: struct {
    main: Program,
    outline: Program,
},
models: [2]Model,
textures: [1]Texture,

const Self = @This();

pub fn init(io: Io, allocator: std.mem.Allocator) !Self {
    const main = try createProgram(io, "shaders/vertex.glsl", "shaders/fragment.glsl", allocator);
    errdefer main.destroy();
    const outline = try createProgram(io, "shaders/outline_vertex.glsl", "shaders/outline_fragment.glsl", allocator);
    errdefer outline.destroy();

    const monkey = init: {
        const buffer = try Io.Dir.cwd().readFileAlloc(io, "models/monkey.slime", allocator, .unlimited);
        defer allocator.free(buffer);

        break :init try Model.Data.init(buffer, allocator);
    };
    defer monkey.deinit(allocator);

    return .{
        .programs = .{
            .main = main,
            .outline = outline,
        },
        .models = .{
            Model.init(Model.cube),
            Model.init(monkey),
        },
        .textures = .{
            try Texture.init("textures/missing.qoi", .nearest, io, allocator),
        },
    };
}

pub fn deinit(self: *const Self) void {
    inline for (@typeInfo(@FieldType(Self, "programs")).@"struct".fields) |field| {
        @field(self.programs, field.name).destroy();
    }
}

fn createProgram(io: Io, vertex_path: []const u8, fragment_path: []const u8, allocator: std.mem.Allocator) !Program {
    const vertex = init_vertex: {
        const buffer: [:0]const u8 = try Io.Dir.cwd().readFileAllocOptions(io, vertex_path, allocator, .unlimited, .@"1", 0);
        defer allocator.free(buffer);
        break :init_vertex try Shader.create(.{ .type = .vertex, .source = buffer, .allocator = allocator });
    };

    defer vertex.destroy();

    const fragment = init_vertex: {
        const buffer: [:0]const u8 = try Io.Dir.cwd().readFileAllocOptions(io, fragment_path, allocator, .unlimited, .@"1", 0);
        defer allocator.free(buffer);
        break :init_vertex try Shader.create(.{ .type = .fragment, .source = buffer, .allocator = allocator });
    };

    defer fragment.destroy();

    return Program.create(.{ .shaders = &.{ vertex, fragment }, .allocator = allocator });
}

pub fn render(self: *const Self, ecs_engine: *Ecs, player_singleton: SingletonType) void {
    var view: math.f32.Mat4, var projection: math.f32.Mat4 = init: {
        if (ecs_engine.getSingletonsEntity(player_singleton)) |id| {
            const position = ecs_engine.getEntityComponent(id, Position) orelse unreachable;
            const camera = ecs_engine.getEntityComponent(id, Camera) orelse unreachable;

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

    self.programs.outline.use();

    glad.glUniformMatrix4fv(self.programs.outline.getUniform("view"), 1, glad.GL_FALSE, &view.fields[0][0]);
    glad.glUniformMatrix4fv(self.programs.outline.getUniform("projection"), 1, glad.GL_FALSE, &projection.fields[0][0]);

    self.programs.main.use();

    glad.glUniformMatrix4fv(self.programs.main.getUniform("view"), 1, glad.GL_FALSE, &view.fields[0][0]);
    glad.glUniformMatrix4fv(self.programs.main.getUniform("projection"), 1, glad.GL_FALSE, &projection.fields[0][0]);

    render: {
        var iterator = ecs_engine.getTupleIterator(.{
            .include = ecs.Template{ .components = &.{ Position, Scale, Rotation, ModelComponent } },
        }) orelse break :render;

        const main_model_location = self.programs.main.getUniform("model");

        const outline_model_location = self.programs.outline.getUniform("model");
        const outline_scale_location = self.programs.outline.getUniform("scale");
        const outline_color_location = self.programs.outline.getUniform("color");

        glad.glCullFace(glad.GL_BACK);

        var mat: math.f32.Mat4 = .identity;
        while (iterator.next()) |tuple| {
            const position: *Position = tuple[0];
            const scale: *Scale = tuple[1];
            const rotation: *Rotation = tuple[2];
            const model: *ModelComponent = tuple[3];

            mat = .initModel(position.*, scale.*, rotation.*);
            glad.glUniformMatrix4fv(main_model_location, 1, glad.GL_FALSE, &mat.fields[0][0]);

            if (model.outline.enabled) {
                self.programs.outline.use();
                glad.glUniform3fv(outline_scale_location, 1, &scale.x);
                glad.glUniform4fv(outline_color_location, 1, &model.outline.color.r);
                glad.glUniformMatrix4fv(outline_model_location, 1, glad.GL_FALSE, &mat.fields[0][0]);

                glad.glCullFace(glad.GL_FRONT);

                switch (model.type) {
                    _ => self.models[0].draw(),
                    else => self.models[@intFromEnum(model.type)].draw(),
                }

                glad.glCullFace(glad.GL_BACK);
                self.programs.main.use();
            }

            switch (model.texture) {
                .missing => {
                    glad.glActiveTexture(glad.GL_TEXTURE0);
                    self.textures[0].bind();
                },
                _ => {
                    glad.glActiveTexture(glad.GL_TEXTURE0);
                    self.textures[0].bind();

                    std.debug.print("Invalid texture used.\n", .{});
                },
            }

            switch (model.type) {
                _ => self.models[0].draw(),
                else => self.models[@intFromEnum(model.type)].draw(),
            }
        }
    }
}
