const math = @import("math");
const std = @import("std");
const glad = @import("glad");

vao: u32,
ebo: u32,
vbo: u32,
len: u32,

const Self = @This();

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    texture_coordinate: [2]f32,
};

pub const Data = struct {
    vertices: []const Vertex,
    indices: []const u32,
};

pub const cube: Data = .{
    .vertices = &.{
        .{ .position = .{ -0.5, 0.5, 0.5 }, .normal = .{ 0.0, 1.0, 0.0 }, .texture_coordinate = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, 0.5 }, .normal = .{ 0.0, 1.0, 0.0 }, .texture_coordinate = .{ 0.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, -0.5 }, .normal = .{ 0.0, 1.0, 0.0 }, .texture_coordinate = .{ 0.0, 0.0 } },
        .{ .position = .{ -0.5, 0.5, -0.5 }, .normal = .{ 0.0, 1.0, 0.0 }, .texture_coordinate = .{ 1.0, 0.0 } },
        .{ .position = .{ -0.5, -0.5, 0.5 }, .normal = .{ 0.0, -1.0, 0.0 }, .texture_coordinate = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, 0.5 }, .normal = .{ 0.0, -1.0, 0.0 }, .texture_coordinate = .{ 0.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, -0.5 }, .normal = .{ 0.0, -1.0, 0.0 }, .texture_coordinate = .{ 0.0, 0.0 } },
        .{ .position = .{ -0.5, -0.5, -0.5 }, .normal = .{ 0.0, -1.0, 0.0 }, .texture_coordinate = .{ 1.0, 0.0 } },
        .{ .position = .{ 0.5, -0.5, -0.5 }, .normal = .{ 1.0, 0.0, 0.0 }, .texture_coordinate = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, 0.5 }, .normal = .{ 1.0, 0.0, 0.0 }, .texture_coordinate = .{ 0.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, 0.5 }, .normal = .{ 1.0, 0.0, 0.0 }, .texture_coordinate = .{ 0.0, 0.0 } },
        .{ .position = .{ 0.5, 0.5, -0.5 }, .normal = .{ 1.0, 0.0, 0.0 }, .texture_coordinate = .{ 1.0, 0.0 } },
        .{ .position = .{ -0.5, -0.5, -0.5 }, .normal = .{ -1.0, 0.0, 0.0 }, .texture_coordinate = .{ 1.0, 1.0 } },
        .{ .position = .{ -0.5, -0.5, 0.5 }, .normal = .{ -1.0, 0.0, 0.0 }, .texture_coordinate = .{ 0.0, 1.0 } },
        .{ .position = .{ -0.5, 0.5, 0.5 }, .normal = .{ -1.0, 0.0, 0.0 }, .texture_coordinate = .{ 0.0, 0.0 } },
        .{ .position = .{ -0.5, 0.5, -0.5 }, .normal = .{ -1.0, 0.0, 0.0 }, .texture_coordinate = .{ 1.0, 0.0 } },
        .{ .position = .{ -0.5, -0.5, 0.5 }, .normal = .{ 0.0, 0.0, 1.0 }, .texture_coordinate = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, 0.5 }, .normal = .{ 0.0, 0.0, 1.0 }, .texture_coordinate = .{ 0.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, 0.5 }, .normal = .{ 0.0, 0.0, 1.0 }, .texture_coordinate = .{ 0.0, 0.0 } },
        .{ .position = .{ -0.5, 0.5, 0.5 }, .normal = .{ 0.0, 0.0, 1.0 }, .texture_coordinate = .{ 1.0, 0.0 } },
        .{ .position = .{ -0.5, -0.5, -0.5 }, .normal = .{ 0.0, 0.0, -1.0 }, .texture_coordinate = .{ 1.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, -0.5 }, .normal = .{ 0.0, 0.0, -1.0 }, .texture_coordinate = .{ 0.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, -0.5 }, .normal = .{ 0.0, 0.0, -1.0 }, .texture_coordinate = .{ 0.0, 0.0 } },
        .{ .position = .{ -0.5, 0.5, -0.5 }, .normal = .{ 0.0, 0.0, -1.0 }, .texture_coordinate = .{ 1.0, 0.0 } },
    },
    .indices = &.{
        0,  1,  2,  0,  2,  3,
        4,  6,  5,  4,  7,  6,
        8,  10, 9,  8,  11, 10,
        12, 13, 14, 12, 14, 15,
        16, 17, 18, 16, 18, 19,
        20, 22, 21, 20, 23, 22,
    },
};

pub fn init(data: Data) Self {
    var vao: u32 = 0;
    glad.glGenVertexArrays(1, @ptrCast(&vao));
    glad.glBindVertexArray(vao);

    var vbo: u32 = 0;
    glad.glGenBuffers(1, @ptrCast(&vbo));
    glad.glBindBuffer(glad.GL_ARRAY_BUFFER, vbo);
    glad.glBufferData(glad.GL_ARRAY_BUFFER, @intCast(data.vertices.len * @sizeOf(Vertex)), data.vertices.ptr, glad.GL_STATIC_DRAW);

    glad.glVertexAttribPointer(0, 3, glad.GL_FLOAT, glad.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "position")));
    glad.glEnableVertexAttribArray(0);

    glad.glVertexAttribPointer(1, 3, glad.GL_FLOAT, glad.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "normal")));
    glad.glEnableVertexAttribArray(1);

    glad.glVertexAttribPointer(2, 2, glad.GL_FLOAT, glad.GL_FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "texture_coordinate")));
    glad.glEnableVertexAttribArray(2);

    var ebo: u32 = 0;
    glad.glGenBuffers(1, @ptrCast(&ebo));
    glad.glBindBuffer(glad.GL_ELEMENT_ARRAY_BUFFER, ebo);
    glad.glBufferData(glad.GL_ELEMENT_ARRAY_BUFFER, @intCast(data.indices.len * @sizeOf(u32)), data.indices.ptr, glad.GL_STATIC_DRAW);
    glad.glBindVertexArray(0);

    return Self{
        .ebo = ebo,
        .vbo = vbo,
        .vao = vao,
        .len = @intCast(data.indices.len),
    };
}

pub fn deinit(self: *Self) void {
    glad.glDeleteBuffers(1, &self.vbo);
    glad.glDeleteBuffers(1, &self.ebo);
    glad.glDeleteVertexArrays(1, &self.vao);
}

pub inline fn bindVertex(self: *const Self) void {
    glad.glBindVertexArray(self.vao);
}

pub inline fn drawElements(self: *const Self) void {
    glad.glDrawElements(glad.GL_TRIANGLES, @intCast(self.len), glad.GL_UNSIGNED_INT, null);
}

pub inline fn draw(self: *const Self) void {
    glad.glBindVertexArray(self.vao);
    glad.glDrawElements(glad.GL_TRIANGLES, @intCast(self.len), glad.GL_UNSIGNED_INT, null);
    glad.glBindVertexArray(0);
}
