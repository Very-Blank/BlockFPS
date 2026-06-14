const std = @import("std");
const json = @import("json.zig");

const Io = std.Io;

assets: std.ArrayList([]json.Object),
names: std.ArrayList([:0]u8),

const Self = @This();

pub const empty: Self = .{
    .assets = .empty,
    .names = .empty,
};

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    for (self.assets.items) |key| {
        allocator.free(key);
    }

    for (self.names.items) |name| {
        allocator.free(name);
    }

    self.assets.deinit(allocator);
    self.names.deinit(allocator);
}

pub fn loadAll(self: *Self, io: Io, allocator: std.mem.Allocator) !void {
    const assets = try Io.Dir.cwd().openDir(io, "assets", .{ .iterate = true });
    defer assets.close(io);

    var iterator = assets.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (entry.name.len < (".json").len or !std.mem.eql(u8, entry.name[entry.name.len - (".json").len .. entry.name.len], ".json")) continue;

        const buffer = try assets.readFileAlloc(io, entry.name, allocator, .unlimited);
        defer allocator.free(buffer);

        const json_parsed = try std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
        defer json_parsed.deinit();

        const name_sentinel: [:0]u8 = try allocator.allocSentinel(u8, entry.name.len - (".json").len, 0);
        errdefer allocator.free(name_sentinel);
        @memcpy(name_sentinel, entry.name[0 .. entry.name.len - (".json").len]);

        const objects: []json.Object = switch (json_parsed.value) {
            .array => |json_array| try json.parseObjects(json_array, allocator),
            .object => |json_object| init: {
                const object = try json.parseObject(json_object, allocator);
                const array = try allocator.alloc(json.Object, 1);
                array[0] = object;
                break :init array;
            },
            else => return error.InvalidAsset,
        };
        errdefer allocator.free(objects);

        try self.assets.append(allocator, objects);
        try self.names.append(allocator, name_sentinel);
    }
}
