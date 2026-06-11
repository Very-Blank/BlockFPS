const std = @import("std");
const math = @import("math");

const Vector3 = math.f32.Vector3;

const Model = @import("components/model.zig").Model;
const Position = @import("components/position.zig").Position;
const Rotation = @import("components/rotation.zig").Rotation;
const Scale = @import("components/scale.zig").Scale;
const Camera = @import("components/Camera.zig");
const Collider = @import("components/collider.zig").Collider;
const Mask = Collider.Mask;
const Rigidbody = @import("components/Rigidbody.zig");

const Enemy = @import("components/Enemy.zig");
const Health = @import("components/Health.zig");
const Bullet = @import("components/Bullet.zig");
const Grounded = @import("components/Grounded.zig");

const RigidbodyObject = struct { Position, Scale, Rotation, Model, Collider, Rigidbody };
const StaticbodyObject = struct { Position, Scale, Rotation, Model, Collider };
const ModelObject = struct { Position, Scale, Rotation, Model };

const Type = enum {
    RigidbodyObject,
    StaticbodyObject,
    ModelObject,

    pub fn parse(value: std.json.Value) !Type {
        switch (value) {
            .string => |string| {
                if (std.mem.eql(u8, "rigidbody", string)) return .RigidbodyObject;
                if (std.mem.eql(u8, "staticbody", string)) return .StaticbodyObject;
                if (std.mem.eql(u8, "model", string)) return .ModelObject;
            },
            else => {},
        }

        return error.InvalidValue;
    }
};

const Object = union(enum) {
    asset: u32,
    rigidbody: RigidbodyObject,
    staticbody: StaticbodyObject,
    model: ModelObject,
};

pub fn parseObjects(value: std.json.Value, allocator: std.mem.Allocator) []Object {
    var list: std.ArrayList(Object) = .empty;
    errdefer list.deinit(allocator);

    switch (value) {
        .array => |array| {
            for (array.items) |item| list.append(allocator, try parseObject(item, allocator));
        },
        else => return error.InvalidValue,
    }

    return list.toOwnedSlice(allocator);
}

pub fn parseObject(value: std.json.Value, allocator: std.mem.Allocator) !Object {
    const arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    switch (value) {
        .object => |object| {
            const @"type" = try Type.parse(object.get("type") orelse return error.InvalidValue);

            return switch (@"type") {
                .RigidbodyObject => .{
                    .rigidbody = .{
                        try std.json.parseFromValueLeaky(Position, allocator, object.get("position") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        try std.json.parseFromValueLeaky(Scale, allocator, object.get("scale") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        Rotation{
                            .fields = try std.json.parseFromValueLeaky([4]f32, allocator, switch (object.get("rotation") orelse return error.InvalidValue) {
                                .object => |fields| fields.get("fields") orelse return error.InvalidValue,
                                else => return error.InvalidValue,
                            }, .{
                                .ignore_unknown_fields = true,
                                .allocate = .alloc_if_needed,
                            }),
                        },
                        try std.json.parseFromValueLeaky(Model, allocator, object.get("model") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        try std.json.parseFromValueLeaky(Collider, allocator, object.get("collider") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        try std.json.parseFromValueLeaky(Rigidbody, allocator, object.get("rigidbody") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                    },
                },
                .StaticbodyObject => .{
                    .staticbody = .{
                        try std.json.parseFromValueLeaky(Position, allocator, object.get("position") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        try std.json.parseFromValueLeaky(Scale, allocator, object.get("scale") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        Rotation{
                            .fields = try std.json.parseFromValueLeaky([4]f32, allocator, switch (object.get("rotation") orelse return error.InvalidValue) {
                                .object => |fields| fields.get("fields") orelse return error.InvalidValue,
                                else => return error.InvalidValue,
                            }, .{
                                .ignore_unknown_fields = true,
                                .allocate = .alloc_if_needed,
                            }),
                        },
                        try std.json.parseFromValueLeaky(Model, allocator, object.get("model") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        try std.json.parseFromValueLeaky(Collider, allocator, object.get("collider") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                    },
                },
                .ModelObject => .{
                    .model = .{
                        try std.json.parseFromValueLeaky(Position, allocator, object.get("position") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        try std.json.parseFromValueLeaky(Scale, allocator, object.get("scale") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        Rotation{
                            .fields = try std.json.parseFromValueLeaky([4]f32, allocator, switch (object.get("rotation") orelse return error.InvalidValue) {
                                .object => |fields| fields.get("fields") orelse return error.InvalidValue,
                                else => return error.InvalidValue,
                            }, .{
                                .ignore_unknown_fields = true,
                                .allocate = .alloc_if_needed,
                            }),
                        },
                        try std.json.parseFromValueLeaky(Model, allocator, object.get("model") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                    },
                },
            };
        },
        else => return error.InvalidValue,
    }
}

test "Rigidbody object parsing" {
    const allocator = std.testing.allocator;

    var object_buffer: [1 << 10]u8 = .{0} ** (1 << 10);
    var buffer: [1 << 10]u8 = .{0} ** (1 << 10);
    var object_writer = std.Io.Writer.fixed(&object_buffer);
    var writer = std.Io.Writer.fixed(&buffer);

    var json: std.ArrayList(u8) = .empty;
    defer json.deinit(allocator);
    try json.appendSlice(allocator, "{\"type\":\"rigidbody\"");

    inline for (.{
        .{ "position", Position.zero },
        .{ "scale", Scale.one },
        .{ "rotation", Rotation.identity },
        .{ "model", Model{} },
        .{ "collider", Collider{ .type = .{ .box = .one } } },
        .{ "rigidbody", Rigidbody{ .restitution = 0.5, .mass = 10.0 } },
    }) |value| {
        try std.json.fmt(value[1], .{}).format(&object_writer);
        try writer.print(",\"{s}\":{s}", .{ value[0], object_writer.buffered() });
        try json.appendSlice(allocator, writer.buffered());
        _ = object_writer.consumeAll();
        _ = writer.consumeAll();
    }

    try json.append(allocator, '}');

    const json_value = try std.json.parseFromSlice(std.json.Value, allocator, json.items, .{});
    defer json_value.deinit();

    try std.testing.expectEqual(Object{ .rigidbody = .{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .one } },
        Rigidbody{ .restitution = 0.5, .mass = 10.0 },
    } }, try parseObject(json_value.value, allocator));
}

test "Staticbody object parsing" {
    const allocator = std.testing.allocator;

    var object_buffer: [1 << 10]u8 = .{0} ** (1 << 10);
    var buffer: [1 << 10]u8 = .{0} ** (1 << 10);
    var object_writer = std.Io.Writer.fixed(&object_buffer);
    var writer = std.Io.Writer.fixed(&buffer);

    var json: std.ArrayList(u8) = .empty;
    defer json.deinit(allocator);
    try json.appendSlice(allocator, "{\"type\":\"staticbody\"");

    inline for (.{
        .{ "position", Position.zero },
        .{ "scale", Scale.one },
        .{ "rotation", Rotation.identity },
        .{ "model", Model{} },
        .{ "collider", Collider{ .type = .{ .box = .one } } },
    }) |value| {
        try std.json.fmt(value[1], .{}).format(&object_writer);
        try writer.print(",\"{s}\":{s}", .{ value[0], object_writer.buffered() });
        try json.appendSlice(allocator, writer.buffered());
        _ = object_writer.consumeAll();
        _ = writer.consumeAll();
    }

    try json.append(allocator, '}');

    const json_value = try std.json.parseFromSlice(std.json.Value, allocator, json.items, .{});
    defer json_value.deinit();

    try std.testing.expectEqual(Object{ .staticbody = .{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .one } },
    } }, try parseObject(json_value.value, allocator));
}

test "Model object parsing" {
    const allocator = std.testing.allocator;

    var object_buffer: [1 << 10]u8 = .{0} ** (1 << 10);
    var buffer: [1 << 10]u8 = .{0} ** (1 << 10);
    var object_writer = std.Io.Writer.fixed(&object_buffer);
    var writer = std.Io.Writer.fixed(&buffer);

    var json: std.ArrayList(u8) = .empty;
    defer json.deinit(allocator);
    try json.appendSlice(allocator, "{\"type\":\"model\"");

    inline for (.{
        .{ "position", Position.zero },
        .{ "scale", Scale.one },
        .{ "rotation", Rotation.identity },
        .{ "model", Model{} },
    }) |value| {
        try std.json.fmt(value[1], .{}).format(&object_writer);
        try writer.print(",\"{s}\":{s}", .{ value[0], object_writer.buffered() });
        try json.appendSlice(allocator, writer.buffered());
        _ = object_writer.consumeAll();
        _ = writer.consumeAll();
    }

    try json.append(allocator, '}');

    const json_value = try std.json.parseFromSlice(std.json.Value, allocator, json.items, .{});
    defer json_value.deinit();

    try std.testing.expectEqual(Object{ .model = .{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model{},
    } }, try parseObject(json_value.value, allocator));
}

test "Objects parsing" {
    const allocator = std.testing.allocator;

    var object_buffer: [1 << 10]u8 = .{0} ** (1 << 10);
    var buffer: [1 << 10]u8 = .{0} ** (1 << 10);
    var object_writer = std.Io.Writer.fixed(&object_buffer);
    var writer = std.Io.Writer.fixed(&buffer);

    var json: std.ArrayList(u8) = .empty;
    defer json.deinit(allocator);
    try json.appendSlice(allocator, "[");

    // FIXME:  THIS SHOULD BE MOVED TO IT'S OWN FUNCTION!
    { // NOTE: Staticbody
        try json.appendSlice(allocator, "{\"type\":\"staticbody\"");

        inline for (.{
            .{ "position", Position.zero },
            .{ "scale", Scale.one },
            .{ "rotation", Rotation.identity },
            .{ "model", Model{} },
            .{ "collider", Collider{ .type = .{ .box = .one } } },
        }) |value| {
            try std.json.fmt(value[1], .{}).format(&object_writer);
            try writer.print(",\"{s}\":{s}", .{ value[0], object_writer.buffered() });
            try json.appendSlice(allocator, writer.buffered());
            _ = object_writer.consumeAll();
            _ = writer.consumeAll();
        }

        try json.appendSlice(allocator, "},");
    }

    { // NOTE: Model
        try json.appendSlice(allocator, "{\"type\":\"model\"");

        inline for (.{
            .{ "position", Position.zero },
            .{ "scale", Scale.one },
            .{ "rotation", Rotation.identity },
            .{ "model", Model{} },
        }) |value| {
            try std.json.fmt(value[1], .{}).format(&object_writer);
            try writer.print(",\"{s}\":{s}", .{ value[0], object_writer.buffered() });
            try json.appendSlice(allocator, writer.buffered());
            _ = object_writer.consumeAll();
            _ = writer.consumeAll();
        }

        try json.append(allocator, '}');
    }

    try json.appendSlice(allocator, "]");
}
