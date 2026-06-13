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

const AssetObject = struct {
    buffer: [100]u8,
    len: u8,

    pub fn getName(self: *const AssetObject) []const u8 {
        return self.name.buffer[0..self.name.len];
    }
};
const RigidbodyObject = struct { Position, Scale, Rotation, Model, Collider, Rigidbody };
const StaticbodyObject = struct { Position, Scale, Rotation, Model, Collider };
const ModelObject = struct { Position, Scale, Rotation, Model };

const Type = enum {
    AssetObject,
    RigidbodyObject,
    StaticbodyObject,
    ModelObject,

    pub fn parse(value: std.json.Value) !Type {
        switch (value) {
            .string => |string| {
                if (std.mem.eql(u8, "asset", string)) return .AssetObject;
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
    asset: AssetObject,
    rigidbody: RigidbodyObject,
    staticbody: StaticbodyObject,
    model: ModelObject,
};

pub fn parseObjects(value: std.json.Value, allocator: std.mem.Allocator) ![]Object {
    var list: std.ArrayList(Object) = .empty;
    defer list.deinit(allocator);

    switch (value) {
        .array => |array| {
            for (array.items) |item| try list.append(allocator, try parseObject(item, allocator));
        },
        else => return error.InvalidValue,
    }

    return list.toOwnedSlice(allocator);
}

pub fn parseObject(value: std.json.Value, allocator: std.mem.Allocator) !Object {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();

    switch (value) {
        .object => |object| {
            const @"type" = try Type.parse(object.get("type") orelse return error.InvalidValue);

            return switch (@"type") {
                .AssetObject => .{
                    .asset = .{
                        .buffer = try std.json.parseFromValueLeaky([100]u8, arena_allocator, object.get("buffer") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        .len = try std.json.parseFromValueLeaky(u8, arena_allocator, object.get("len") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                    },
                },
                .RigidbodyObject => .{
                    .rigidbody = init: {
                        var rigidbody: RigidbodyObject = undefined;

                        inline for (std.meta.fields(RigidbodyObject), 0..) |field, i| {
                            rigidbody[i] = try parseComponent(field.type, object, arena_allocator);
                        }

                        break :init rigidbody;
                    },
                },
                .StaticbodyObject => .{
                    .staticbody = init: {
                        var staticbody: StaticbodyObject = undefined;

                        inline for (std.meta.fields(StaticbodyObject), 0..) |field, i| {
                            staticbody[i] = try parseComponent(field.type, object, arena_allocator);
                        }

                        break :init staticbody;
                    },
                },
                .ModelObject => .{
                    .model = init: {
                        var model: ModelObject = undefined;

                        inline for (std.meta.fields(ModelObject), 0..) |field, i| {
                            model[i] = try parseComponent(field.type, object, arena_allocator);
                        }

                        break :init model;
                    },
                },
            };
        },
        else => return error.InvalidValue,
    }
}

pub fn parseComponent(comptime T: type, object: @FieldType(std.json.Value, "object"), arena: std.mem.Allocator) !T {
    return switch (T) {
        Position, Scale, Model, Collider, Rigidbody => try std.json.parseFromValueLeaky(T, arena, object.get(switch (T) {
            Position => "position",
            Scale => "scale",
            Model => "model",
            Collider => "collider",
            Rigidbody => "rigidbody",
            else => @compileError("Unreachable."),
        }) orelse return error.InvalidValue, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_if_needed,
        }),
        Rotation => Rotation{
            .fields = try std.json.parseFromValueLeaky([4]f32, arena, switch (object.get("rotation") orelse return error.InvalidValue) {
                .object => |fields| fields.get("fields") orelse return error.InvalidValue,
                else => return error.InvalidValue,
            }, .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_if_needed,
            }),
        },
        else => @compileError("Unexpected component type: " ++ @typeName(T)),
    };
}

pub fn jsonifyObject(object: Object, allocator: std.mem.Allocator) ![]u8 {
    var object_buffer: [1 << 10]u8 = .{0} ** (1 << 10);
    var object_writer = std.Io.Writer.fixed(&object_buffer);

    var buffer: [1 << 10]u8 = .{0} ** (1 << 10);
    var writer = std.Io.Writer.fixed(&buffer);

    var json: std.ArrayList(u8) = .empty;
    defer json.deinit(allocator);

    try json.appendSlice(allocator, "{\"type\":");

    try switch (object) {
        .asset => json.appendSlice(allocator, "\"asset\""),
        .rigidbody => json.appendSlice(allocator, "\"rigidbody\""),
        .staticbody => json.appendSlice(allocator, "\"staticbody\""),
        .model => json.appendSlice(allocator, "\"model\""),
    };

    switch (object) {
        .asset => |value| {
            try json.appendSlice(allocator, ",");
            try std.json.fmt(value, .{}).format(&object_writer);

            try json.appendSlice(allocator, writer.buffered());
            _ = writer.consumeAll();
        },
        .rigidbody => |value| {
            inline for (std.meta.fields(RigidbodyObject), 0..) |field, i| {
                try json.appendSlice(allocator, ",");

                try jsonifyComponent(field.type, value[i], &writer, &object_writer);
                try json.appendSlice(allocator, writer.buffered());
                _ = writer.consumeAll();
            }
        },
        .staticbody => |value| {
            inline for (std.meta.fields(StaticbodyObject), 0..) |field, i| {
                try json.appendSlice(allocator, ",");

                try jsonifyComponent(field.type, value[i], &writer, &object_writer);
                try json.appendSlice(allocator, writer.buffered());
                _ = writer.consumeAll();
            }
        },
        .model => |value| {
            inline for (std.meta.fields(ModelObject), 0..) |field, i| {
                try json.appendSlice(allocator, ",");

                try jsonifyComponent(field.type, value[i], &writer, &object_writer);
                try json.appendSlice(allocator, writer.buffered());
                _ = writer.consumeAll();
            }
        },
    }

    try json.appendSlice(allocator, "}");

    return try json.toOwnedSlice(allocator);
}

pub fn jsonifyComponent(comptime T: type, value: T, writer: *std.Io.Writer, object_writer: *std.Io.Writer) !void {
    try std.json.fmt(value, .{}).format(object_writer);

    try writer.print("\"{s}\":{s}", .{ switch (T) {
        Position => "position",
        Scale => "scale",
        Model => "model",
        Collider => "collider",
        Rigidbody => "rigidbody",
        Rotation => "rotation",
        else => @compileError("Unexpected component type: " ++ @typeName(T)),
    }, object_writer.buffered() });

    _ = object_writer.consumeAll();
}

test "Rigidbody jsonify/parse" {
    const allocator = std.testing.allocator;

    const json = try jsonifyObject(.{ .rigidbody = .{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .one } },
        Rigidbody{ .restitution = 0.5, .mass = 10.0 },
    } }, allocator);

    defer allocator.free(json);

    const json_value = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
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

test "Staticbody jsonify/parse" {
    const allocator = std.testing.allocator;

    const json = try jsonifyObject(.{ .staticbody = .{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .one } },
    } }, allocator);

    defer allocator.free(json);

    const json_value = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer json_value.deinit();

    try std.testing.expectEqual(Object{ .staticbody = .{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .one } },
    } }, try parseObject(json_value.value, allocator));
}

test "Model jsonify/parse" {
    const allocator = std.testing.allocator;

    const json = try jsonifyObject(.{ .model = .{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model{},
    } }, allocator);

    defer allocator.free(json);

    const json_value = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
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
    var json: std.ArrayList(u8) = .empty;
    defer json.deinit(allocator);

    try json.appendSlice(allocator, "[");

    inline for (.{
        Object{ .rigidbody = .{
            Position.zero,
            Scale.one,
            Rotation.identity,
            Model{},
            Collider{ .type = .{ .box = .one } },
            Rigidbody{ .restitution = 0.5, .mass = 10.0 },
        } },
        Object{ .staticbody = .{
            Position.zero,
            Scale.one,
            Rotation.identity,
            Model{},
            Collider{ .type = .{ .box = .one } },
        } },
        Object{ .model = .{
            Position.zero,
            Scale.one,
            Rotation.identity,
            Model{},
        } },
    }, 0..) |object, i| {
        const object_json = try jsonifyObject(object, allocator);
        defer allocator.free(object_json);

        try json.appendSlice(allocator, object_json);
        if (i != 2) try json.appendSlice(allocator, ",");
    }

    try json.appendSlice(allocator, "]");

    const value = try std.json.parseFromSlice(std.json.Value, allocator, json.items, .{});
    defer value.deinit();

    const objects = try parseObjects(value.value, allocator);
    defer allocator.free(objects);

    try std.testing.expectEqualSlices(Object, &.{ Object{ .rigidbody = .{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .one } },
        Rigidbody{ .restitution = 0.5, .mass = 10.0 },
    } }, Object{ .staticbody = .{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model{},
        Collider{ .type = .{ .box = .one } },
    } }, Object{ .model = .{
        Position.zero,
        Scale.one,
        Rotation.identity,
        Model{},
    } } }, objects);
}
