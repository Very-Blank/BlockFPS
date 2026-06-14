const std = @import("std");
const qoi = @import("qoi");
const glad = @import("glad");

const Io = std.Io;

id: u32,

const Self = @This();

pub fn init(path: [:0]const u8, filter: enum {
    nearest,
    linear,
}, io: Io, allocator: std.mem.Allocator) !Self {
    const buffer = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    defer allocator.free(buffer);
    const pixels, const body = try qoi.decode(buffer, allocator);
    defer allocator.free(pixels);

    var texture: u32 = undefined;
    glad.glGenTextures(1, &texture);
    glad.glBindTexture(glad.GL_TEXTURE_2D, texture);
    glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_S, glad.GL_REPEAT);
    glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_T, glad.GL_REPEAT);
    glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MIN_FILTER, switch (filter) {
        .linear => glad.GL_LINEAR_MIPMAP_LINEAR,
        .nearest => glad.GL_LINEAR_MIPMAP_NEAREST,
    });
    glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MAG_FILTER, switch (filter) {
        .linear => glad.GL_LINEAR,
        .nearest => glad.GL_NEAREST,
    });
    glad.glTexImage2D(glad.GL_TEXTURE_2D, 0, glad.GL_RGB, @intCast(body.width), @intCast(body.height), 0, glad.GL_RGBA, glad.GL_UNSIGNED_BYTE, pixels.ptr);
    glad.glGenerateMipmap(glad.GL_TEXTURE_2D);

    return .{
        .id = texture,
    };
}

pub fn bind(self: *const Self) void {
    glad.glBindTexture(glad.GL_TEXTURE_2D, self.id);
}

pub fn deinit(self: *const Self) void {
    glad.glDeleteTextures(1, &.{self.id});
}
