const std = @import("std");
const ecs = @import("ecs");
const math = @import("math");

const Ecs = @import("ecs.zig").Ecs;
const Template = ecs.Template;

const Position = @import("components/position.zig").Position;
const Collider = @import("components/collider.zig").Collider;
const Rigidbody = @import("components/Rigidbody.zig");

const Sphere = Collider.Sphere;
const Capsule = Collider.Capsule;
const Box = Collider.Box;

// collisions: std.AutoHashMapUnmanaged(
//     ecs.EntityPointer,
//     Collision,
// ),

pub const Collision = struct {
    normal: math.f32.Vector3,
    depth: f32,
};

const Info = struct {
    normal: math.f32.Vector3,
    depth: f32,
};

pub fn update(delta_time: f32, ecs_engine: *Ecs) void {
    var rigidbodies = if (ecs_engine.getTupleIterator(.{
        .include = ecs.Template{ .components = &.{ Position, Collider, Rigidbody } },
    })) |tuple_iterator| tuple_iterator else return;

    update_sb_rb_physics: {
        var staticbodies = if (ecs_engine.getTupleIterator(.{
            .include = ecs.Template{ .components = &.{ Position, Collider } },
            .exclude = ecs.Template{ .components = &.{Rigidbody} },
        })) |tuple_iterator| tuple_iterator else break :update_sb_rb_physics;

        simulateSbRb(delta_time, &rigidbodies, &staticbodies);
        rigidbodies.reset();
    }

    simulateRb(delta_time, &rigidbodies);
}

pub fn simulateSbRb(
    _: f32,
    rigidbodies: *Ecs.TupleIterator(.{ .include = .{ .components = &.{ Position, Collider, Rigidbody } } }),
    staticbodies: *Ecs.TupleIterator(.{ .include = .{ .components = &.{ Position, Collider } }, .exclude = .{ .components = &.{Rigidbody} } }),
) void {
    while (rigidbodies.next()) |rigidbody| {
        while (staticbodies.next()) |staticbody| {
            if (collision(
                .{ .position = rigidbody[0].*, .collider = rigidbody[1].* },
                .{ .position = staticbody[0].*, .collider = staticbody[1].* },
            )) |info| {
                const body1_pos: *Position = rigidbody[0];
                const body1_rb: *Rigidbody = rigidbody[2];

                const normal = if (body1_pos.subtract(staticbody[0].*).dot(info.normal) < 0) info.normal.negate() else info.normal;

                body1_pos.* = body1_pos.add(normal.scale(info.depth));

                const dot = body1_rb.velocity.dot(normal);

                body1_rb.velocity = body1_rb.velocity.subtract(normal.scale(dot).scale(body1_rb.restitution));
            }
        }

        staticbodies.reset();
    }
}

pub fn simulateRb(delta_time: f32, iterator: *Ecs.TupleIterator(.{
    .include = ecs.Template{ .components = &.{ Position, Collider, Rigidbody } },
})) void {
    const friction: f32 = 0.0005;

    while (iterator.next()) |body| {
        const rigidbody: *Rigidbody = body[2];
        rigidbody.velocity.y += rigidbody.gravity * delta_time;
        rigidbody.velocity = rigidbody.velocity.scale(1.0 - friction);
    }

    iterator.reset();

    var inner_iterator = iterator.*;

    while (iterator.next()) |body1| {
        inner_iterator.current_index = iterator.current_index;
        inner_iterator.current_buffer = iterator.current_buffer;

        while (inner_iterator.next()) |body2| {
            if (collision(
                .{ .position = body1[0].*, .collider = body1[1].* },
                .{ .position = body2[0].*, .collider = body2[1].* },
            )) |info| {
                const body1_pos: *Position = body1[0];
                const body1_rb: *Rigidbody = body1[2];

                const body2_pos: *Position = body2[0];
                const body2_rb: *Rigidbody = body2[2];

                std.debug.assert(body1_rb.mass != 0.0);
                std.debug.assert(body2_rb.mass != 0.0);

                const normal = if (body1_pos.subtract(body2_pos.*).dot(info.normal) < 0) info.normal.negate() else info.normal;

                const ratio: f32 = body2_rb.mass / (body1_rb.mass + body2_rb.mass);

                body1_pos.* = body1_pos.add(normal.scale(ratio * info.depth));
                body2_pos.* = body2_pos.add(normal.scale((1.0 - ratio) * info.depth).negate());

                if (0 <= body1_rb.velocity.subtract(body2_rb.velocity).dot(normal)) continue;

                const e = (body1_rb.restitution + body2_rb.restitution) / 2.0;

                const v_1 = normal.scale(body1_rb.velocity.dot(normal));
                const v_2 = normal.scale(body2_rb.velocity.dot(normal));

                const @"m_1*v_1 + m_2*v_1" = v_1.scale(body1_rb.mass).add(v_2.scale(body2_rb.mass));
                const @"m_1+m_2" = body1_rb.mass + body2_rb.mass;

                body1_rb.velocity = body1_rb.velocity.subtract(v_1).add(@"m_1*v_1 + m_2*v_1".add(v_2.subtract(v_1).scale(e * body2_rb.mass)).segment(@"m_1+m_2"));
                body2_rb.velocity = body2_rb.velocity.subtract(v_2).add(@"m_1*v_1 + m_2*v_1".add(v_1.subtract(v_2).scale(e * body1_rb.mass)).segment(@"m_1+m_2"));
            }
        }
    }

    iterator.reset();

    while (iterator.next()) |body| {
        const position: *Position = body[0];
        const rigidbody: *Rigidbody = body[2];

        position.* = position.add(rigidbody.velocity.scale(delta_time));
    }
}

/// Collision normal isn't guaranteed to be relative to any body.
pub inline fn collision(body1: struct { position: Position, collider: Collider }, body2: struct { position: Position, collider: Collider }) ?Info {
    // FIXME: Write this in a better clean way!
    return switch (body1.collider) {
        .sphere => |sphere1| switch (body2.collider) {
            .sphere => |sphere2| sphereVsSphere(.{
                .position = body1.position,
                .sphere = sphere1,
            }, .{
                .position = body2.position,
                .sphere = sphere2,
            }),
            .capsule => |capsule2| sphereVsCapsule(.{
                .position = body1.position,
                .sphere = sphere1,
            }, .{
                .position = body2.position,
                .capsule = capsule2,
            }),
            .box => |box2| sphereVsBox(.{
                .position = body1.position,
                .sphere = sphere1,
            }, .{
                .position = body2.position,
                .box = box2,
            }),
        },
        .capsule => |capsule1| switch (body2.collider) {
            .capsule => |capsule2| capsuleVsCapsule(.{
                .position = body1.position,
                .capsule = capsule1,
            }, .{
                .position = body2.position,
                .capsule = capsule2,
            }),
            .sphere => |sphere2| sphereVsCapsule(.{
                .position = body2.position,
                .sphere = sphere2,
            }, .{
                .position = body1.position,
                .capsule = capsule1,
            }),
            .box => |box2| capsuleVsBox(.{
                .position = body1.position,
                .capsule = capsule1,
            }, .{
                .position = body2.position,
                .box = box2,
            }),
        },
        .box => |box1| switch (body2.collider) {
            .box => |box2| boxVsBox(.{
                .position = body1.position,
                .box = box1,
            }, .{
                .position = body2.position,
                .box = box2,
            }),
            .capsule => |capsule2| capsuleVsBox(.{
                .position = body2.position,
                .capsule = capsule2,
            }, .{
                .position = body1.position,
                .box = box1,
            }),
            .sphere => |sphere2| sphereVsBox(.{
                .position = body2.position,
                .sphere = sphere2,
            }, .{
                .position = body1.position,
                .box = box1,
            }),
        },
    };
}

// FIXME: Checking distance != 0.0 isn't good enough.

pub fn sphereVsSphere(
    body1: struct { position: Position, sphere: Sphere },
    body2: struct { position: Position, sphere: Sphere },
) ?Info {
    const distance = body1.position.distance(body2.position);
    if (body1.sphere.radius + body2.sphere.radius < distance) return null;

    return .{
        .depth = body1.sphere.radius + body2.sphere.radius - distance,
        .normal = if (distance != 0.0) (math.f32.Vector3{
            .x = body2.position.x - body1.position.x,
            .y = body2.position.y - body1.position.y,
            .z = body2.position.z - body1.position.z,
        }).normalize() else .zero,
    };
}

pub fn sphereVsCapsule(
    body1: struct { position: Position, sphere: Sphere },
    body2: struct { position: Position, capsule: Capsule },
) ?Info {
    const closest = Position.closestPointOnLine(Position{
        .x = body2.position.x,
        .y = body2.position.y - body2.capsule.length / 2,
        .z = body2.position.z,
    }, Position{
        .x = body2.position.x,
        .y = body2.position.y + body2.capsule.length / 2,
        .z = body2.position.z,
    }, body1.position);

    const distance = body1.position.distance(closest);

    if (body1.sphere.radius + body2.capsule.radius < distance) return null;

    return .{
        .depth = body1.sphere.radius + body2.capsule.radius - distance,
        .normal = if (distance != 0.0) (math.f32.Vector3{
            .x = body1.position.x - closest.x,
            .y = body1.position.y - closest.y,
            .z = body1.position.z - closest.z,
        }).normalize() else .zero,
    };
}

pub fn sphereVsBox(
    body1: struct { position: Position, sphere: Sphere },
    body2: struct { position: Position, box: Box },
) ?Info {
    var closest: math.f32.Vector3 = .{};

    inline for (.{ "x", "y", "z" }) |axis| {
        const min2 = @field(body2.position, axis) - @field(body2.box, axis) / 2.0;
        const max2 = @field(body2.position, axis) + @field(body2.box, axis) / 2.0;
        @field(closest, axis) = std.math.clamp(@field(body1.position, axis), min2, max2);
    }

    const difference: math.f32.Vector3 = .{
        .x = body1.position.x - closest.x,
        .y = body1.position.y - closest.y,
        .z = body1.position.z - closest.z,
    };

    const distance = difference.length();

    if (body1.sphere.radius < distance) return null;

    return .{
        .depth = body1.sphere.radius - distance,
        .normal = if (distance != 0.0) difference.normalize() else .zero,
    };
}

pub fn capsuleVsBox(
    body1: struct { position: Position, capsule: Capsule },
    body2: struct { position: Position, box: Box },
) ?Info {
    const closest_body1_point = Position.closestPointOnLine(Position{
        .x = body1.position.x,
        .y = body1.position.y - body1.capsule.length / 2,
        .z = body1.position.z,
    }, Position{
        .x = body1.position.x,
        .y = body1.position.y + body1.capsule.length / 2,
        .z = body1.position.z,
    }, body2.position);

    var closest: math.f32.Vector3 = .{};

    inline for (.{ "x", "y", "z" }) |axis| {
        const min2 = @field(body2.position, axis) - @field(body2.box, axis) / 2.0;
        const max2 = @field(body2.position, axis) + @field(body2.box, axis) / 2.0;
        @field(closest, axis) = std.math.clamp(@field(closest_body1_point, axis), min2, max2);
    }

    const difference: math.f32.Vector3 = .{
        .x = closest_body1_point.x - closest.x,
        .y = closest_body1_point.y - closest.y,
        .z = closest_body1_point.z - closest.z,
    };

    const distance = difference.length();

    if (body1.capsule.radius < distance) return null;

    return .{
        .depth = body1.capsule.radius - distance,
        .normal = if (distance != 0.0) difference.normalize() else .zero,
    };
}

pub fn capsuleVsCapsule(
    body1: struct { position: Position, capsule: Capsule },
    body2: struct { position: Position, capsule: Capsule },
) ?Info {
    const body1_closest = Position.closestPointOnLine(Position{
        .x = body1.position.x,
        .y = body1.position.y - body1.capsule.length / 2,
        .z = body1.position.z,
    }, Position{
        .x = body1.position.x,
        .y = body1.position.y + body1.capsule.length / 2,
        .z = body1.position.z,
    }, body2.position);

    const body2_closest = Position.closestPointOnLine(Position{
        .x = body2.position.x,
        .y = body2.position.y - body2.capsule.length / 2,
        .z = body2.position.z,
    }, Position{
        .x = body2.position.x,
        .y = body2.position.y + body2.capsule.length / 2,
        .z = body2.position.z,
    }, body1.position);

    const difference: math.f32.Vector3 = .{
        .x = body1_closest.x - body2_closest.x,
        .y = body1_closest.y - body2_closest.y,
        .z = body1_closest.z - body2_closest.z,
    };

    const distance = difference.length();

    if (body1.capsule.radius + body2.capsule.radius < distance) return null;

    return .{
        .depth = body1.capsule.radius + body2.capsule.radius - distance,
        .normal = if (distance != 0) difference.normalize() else .zero,
    };
}

pub fn boxVsBox(
    body1: struct { position: Position, box: Box },
    body2: struct { position: Position, box: Box },
) ?Info {
    var fields: math.f32.Vector3 = .zero;

    inline for (.{ "x", "y", "z" }) |axis| {
        const min1 = @field(body1.position, axis) - @field(body1.box, axis) / 2.0;
        const max1 = @field(body1.position, axis) + @field(body1.box, axis) / 2.0;

        const min2 = @field(body2.position, axis) - @field(body2.box, axis) / 2.0;
        const max2 = @field(body2.position, axis) + @field(body2.box, axis) / 2.0;

        if (max2 < min1 or max1 < min2) return null;

        @field(fields, axis) = @min(max1, max2) - @max(min1, min2);
    }

    if (fields.x <= fields.y and fields.x <= fields.z) return .{ .depth = fields.x, .normal = .{ .x = 1 } };
    if (fields.y <= fields.x and fields.y <= fields.z) return .{ .depth = fields.y, .normal = .{ .y = 1 } };
    return .{ .depth = fields.z, .normal = .{ .z = 1 } };
}
