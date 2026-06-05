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
    rigidbody: RigidbodyObject,
    staticbody: StaticbodyObject,
    model: ModelObject,
};

pub fn parseObject(value: std.json.Value, allocator: std.mem.Allocator) !Object {
    const arena = std.heap.ArenaAllocator.init(allocator);
    arena.deinit();

    switch (value) {
        .object => |object| {
            const @"type" = try Type.parse(object.get("type") orelse return error.InvalidValue);

            return switch (@"type") {
                .RigidbodyObject => .{
                    .rigidbody = .{
                        .zero,
                        try std.json.parseFromValueLeaky(Scale, allocator, object.get("scale") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        Rotation{ .fields = try std.json.parseFromValueLeaky([4]f32, allocator, object.get("rotation") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }) },
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
                        try std.json.parseFromValueLeaky(Scale, allocator, object.get("scale") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        Rotation{ .fields = try std.json.parseFromValueLeaky([4]f32, allocator, object.get("rotation") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }) },
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
                        try std.json.parseFromValueLeaky(Scale, allocator, object.get("scale") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }),
                        Rotation{ .fields = try std.json.parseFromValueLeaky([4]f32, allocator, object.get("rotation") orelse return error.InvalidValue, .{
                            .ignore_unknown_fields = true,
                            .allocate = .alloc_if_needed,
                        }) },
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
