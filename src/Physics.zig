const std = @import("std");
const ecs = @import("ecs");
const math = @import("math");

const Ecs = @import("ecs.zig").Ecs;
const Template = ecs.Template;
const EntityPointer = ecs.EntityPointer;

const Position = @import("components/position.zig").Position;
const Collider = @import("components/collider.zig").Collider;
const Rigidbody = @import("components/Rigidbody.zig");
const Grounded = @import("components/Grounded.zig");

const Sphere = Collider.Sphere;
const Capsule = Collider.Capsule;
const Box = Collider.Box;
const Mask = Collider.Mask;

const fixed_step: f32 = 1.0 / 120.0;
const max_accumulation: f32 = 0.1;

accumulator: f32 = 0.0,
collisions: std.AutoHashMapUnmanaged(u64, void) = .empty,
rbVsRb_collisions: std.ArrayList(Collision) = .empty,
sbVsRb_collisions: std.ArrayList(Collision) = .empty,

rbVsRb_infos: std.ArrayList(struct {
    normal: math.f32.Vector3,
    depth: f32,
    angle1: f32,
    angle2: f32,
}) = .empty,

sbVsRb_infos: std.ArrayList(struct {
    normal: math.f32.Vector3,
    depth: f32,
    angle: f32,
}) = .empty,

allocator: std.mem.Allocator,

const Self = @This();

pub const Collision = struct {
    body1: EntityPointer,
    body2: EntityPointer,
};

pub const CollisionInfo = struct {
    normal: math.f32.Vector3,
    detph: f32,
    angle1: f32,
    angle2: f32,
};

pub const Info = struct {
    normal: math.f32.Vector3,
    depth: f32,
};

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.collisions.deinit(self.allocator);
    self.rbVsRb_collisions.deinit(self.allocator);
    self.rbVsRb_infos.deinit(self.allocator);

    self.sbVsRb_collisions.deinit(self.allocator);
    self.sbVsRb_infos.deinit(self.allocator);
}

pub fn clear(self: *Self) void {
    self.collisions.clearRetainingCapacity();
    self.rbVsRb_collisions.clearRetainingCapacity();
    self.rbVsRb_infos.clearRetainingCapacity();

    self.sbVsRb_collisions.clearRetainingCapacity();
    self.sbVsRb_infos.clearRetainingCapacity();
}

pub fn hasCollision(self: *Self, a: EntityPointer, b: EntityPointer) bool {
    return (self.collisions.getOrPut(self.allocator, key(a, b)) catch @panic("OOM")).found_existing;
}

fn key(a: EntityPointer, b: EntityPointer) u64 {
    if (a.entity.value() < b.entity.value()) return @as(u64, a.entity.value()) << 32 | b.entity.value();
    return @as(u64, b.entity.value()) << 32 | a.entity.value();
}

pub fn update(self: *Self, ecs_engine: *Ecs, delta_time: f32) void {
    self.accumulator = @min(self.accumulator + delta_time, max_accumulation);

    if (fixed_step <= self.accumulator) {
        grounded: {
            var iterator = ecs_engine.getIterator(.{ .component = Grounded }) orelse break :grounded;

            while (iterator.next()) |grounded| {
                grounded.*.grounded = false;
            }
        }

        var rigidbodies = ecs_engine.getTupleIterator(.{
            .include = ecs.Template{ .components = &.{ Position, Collider, Rigidbody } },
        }) orelse return;

        if (ecs_engine.getTupleIterator(.{
            .include = ecs.Template{ .components = &.{ Position, Collider } },
            .exclude = ecs.Template{ .components = &.{Rigidbody} },
        })) |tuple_iterator| {
            var staticbodies = tuple_iterator;

            while (fixed_step <= self.accumulator) {
                self.simulateSbRb(delta_time, &rigidbodies, &staticbodies);

                rigidbodies.reset();
                staticbodies.reset();

                self.simulateRb(delta_time, &rigidbodies);

                rigidbodies.reset();

                self.accumulator -= fixed_step;
            }

            return;
        }

        while (fixed_step <= self.accumulator) {
            self.simulateRb(delta_time, &rigidbodies);
            rigidbodies.reset();

            self.accumulator -= fixed_step;
        }
    }
}

pub fn simulateSbRb(
    self: *Self,
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
                if (0 < dot) continue;

                const angle: f32 = init: {
                    const length = body1_rb.velocity.length();
                    if (0 < length) break :init body1_rb.velocity.normalize().dot(normal);

                    break :init 0;
                };

                body1_rb.velocity = body1_rb.velocity.subtract(normal.scale(dot).scale(1.0 + body1_rb.restitution));

                if (!self.hasCollision(rigidbodies.getCurrentEntity(), staticbodies.getCurrentEntity())) {
                    self.sbVsRb_collisions.append(self.allocator, .{
                        .body1 = rigidbodies.getCurrentEntity(),
                        .body2 = staticbodies.getCurrentEntity(),
                    }) catch @panic("OOM");

                    self.sbVsRb_infos.append(self.allocator, .{
                        .normal = normal,
                        .depth = info.depth,
                        .angle = angle,
                    }) catch @panic("OOM");
                }
            }
        }

        staticbodies.reset();
    }
}

pub fn simulateRb(self: *Self, delta_time: f32, iterator: *Ecs.TupleIterator(.{
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

                const angle1: f32 = init: {
                    const length = body1_rb.velocity.length();
                    if (0 < length) break :init body1_rb.velocity.normalize().dot(normal);
                    break :init 0;
                };

                const angle2: f32 = init: {
                    const length = body2_rb.velocity.length();
                    if (0 < length) break :init body2_rb.velocity.normalize().dot(normal);
                    break :init 0;
                };

                const v_1 = normal.scale(body1_rb.velocity.dot(normal));
                const v_2 = normal.scale(body2_rb.velocity.dot(normal));

                const @"m_1*v_1 + m_2*v_1" = v_1.scale(body1_rb.mass).add(v_2.scale(body2_rb.mass));
                const @"m_1+m_2" = body1_rb.mass + body2_rb.mass;

                body1_rb.velocity = body1_rb.velocity.subtract(v_1).add(@"m_1*v_1 + m_2*v_1".add(v_2.subtract(v_1).scale(e * body2_rb.mass)).segment(@"m_1+m_2"));
                body2_rb.velocity = body2_rb.velocity.subtract(v_2).add(@"m_1*v_1 + m_2*v_1".add(v_1.subtract(v_2).scale(e * body1_rb.mass)).segment(@"m_1+m_2"));

                if (!self.hasCollision(iterator.getCurrentEntity(), inner_iterator.getCurrentEntity())) {
                    self.rbVsRb_collisions.append(self.allocator, .{
                        .body1 = iterator.getCurrentEntity(),
                        .body2 = inner_iterator.getCurrentEntity(),
                    }) catch unreachable;

                    self.rbVsRb_infos.append(self.allocator, .{
                        .normal = normal,
                        .depth = info.depth,
                        .angle1 = angle1,
                        .angle2 = angle2,
                    }) catch unreachable;
                }
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

pub const RaycastResult = struct {
    position: math.f32.Vector3,
    body: EntityPointer,
};

pub fn raycast(
    ecs_engine: *Ecs,
    origin: math.f32.Vector3,
    direction: math.f32.Vector3,
    length: f32,
    mask: Mask,
) ?RaycastResult {
    var bodies = ecs_engine.getTupleIterator(.{
        .include = ecs.Template{ .components = &.{ Position, Collider } },
    }) orelse return null;

    const line: Line = .{
        .start = origin,
        .end = origin.add(direction.scale(length)),
    };

    var closest: ?RaycastResult = null;

    while (bodies.next()) |body| {
        const position: *Position = body[0];
        const collider: *Collider = body[1];

        if (!mask.contains(collider.layer)) continue;

        const new: ?math.f32.Vector3 = switch (collider.type) {
            .sphere => |sphere| lineVsSphere(line, .{ .position = position.*, .sphere = sphere }),
            .capsule => |capsule| lineVsCapsule(line, .{ .position = position.*, .capsule = capsule }),
            .box => |box| lineVsBox(line, .{ .position = position.*, .box = box }),
        };

        if (new) |capture_new| {
            if (closest) |capture_closest| {
                if (origin.distance(capture_new) < origin.distance(capture_closest.position)) {
                    closest = .{
                        .position = capture_new,
                        .body = bodies.getCurrentEntity(),
                    };
                }
            } else {
                closest = .{
                    .position = capture_new,
                    .body = bodies.getCurrentEntity(),
                };
            }
        }
    }

    return closest;
}

/// Collision normal isn't guaranteed to be relative to any body.
pub inline fn collision(body1: struct { position: Position, collider: Collider }, body2: struct { position: Position, collider: Collider }) ?Info {
    if (!body1.collider.mask.contains(body2.collider.layer) or !body2.collider.mask.contains(body1.collider.layer)) return null;

    // FIXME: Write this in a better clean way!
    return switch (body1.collider.type) {
        .sphere => |sphere1| switch (body2.collider.type) {
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
        .capsule => |capsule1| switch (body2.collider.type) {
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
        .box => |box1| switch (body2.collider.type) {
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

// FIXME: REMOVE subtract radius from height!
pub fn sphereVsCapsule(
    body1: struct { position: Position, sphere: Sphere },
    body2: struct { position: Position, capsule: Capsule },
) ?Info {
    const closest = Position.closestPointOnLine(Position{
        .x = body2.position.x,
        .y = body2.position.y - (body2.capsule.half_height - body2.capsule.radius),
        .z = body2.position.z,
    }, Position{
        .x = body2.position.x,
        .y = body2.position.y + body2.capsule.half_height - body2.capsule.radius,
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
        .y = body1.position.y - (body1.capsule.half_height - body1.capsule.radius),
        .z = body1.position.z,
    }, Position{
        .x = body1.position.x,
        .y = body1.position.y + body1.capsule.half_height - body1.capsule.radius,
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
        .y = body1.position.y - (body1.capsule.half_height - body1.capsule.radius),
        .z = body1.position.z,
    }, Position{
        .x = body1.position.x,
        .y = body1.position.y + body1.capsule.half_height - body1.capsule.radius,
        .z = body1.position.z,
    }, body2.position);

    const body2_closest = Position.closestPointOnLine(Position{
        .x = body2.position.x,
        .y = body2.position.y - (body2.capsule.half_height - body2.capsule.radius),
        .z = body2.position.z,
    }, Position{
        .x = body2.position.x,
        .y = body2.position.y + body2.capsule.half_height - body2.capsule.radius,
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

pub const Line = struct { start: math.f32.Vector3, end: math.f32.Vector3 };

// FIXME: THESE ONLY USE AN ESTIMATE!

pub fn lineVsSphere(
    line: Line,
    body: struct { position: Position, sphere: Sphere },
) ?math.f32.Vector3 {
    const closest = line.start.closestPointOnLine(line.end, body.position);
    const distance = body.position.distance(closest);

    if (body.sphere.radius < distance) return null;
    return closest;
}

pub fn lineVsCapsule(line: Line, body: struct {
    position: Position,
    capsule: Capsule,
}) ?math.f32.Vector3 {
    const closest = line.start.closestPointOnLine(line.end, body.position);

    const clamped_y = std.math.clamp(
        closest.y,
        body.position.y - (body.capsule.half_height - body.capsule.radius),
        body.position.y + body.capsule.half_height - body.capsule.radius,
    );

    const capsule_point = math.f32.Vector3{
        .x = body.position.x,
        .y = clamped_y,
        .z = body.position.z,
    };

    if (body.capsule.radius < closest.distance(capsule_point)) return null;
    return capsule_point;
}

pub fn lineVsBox(
    line: Line,
    body: struct {
        position: Position,
        box: Box,
    },
) ?math.f32.Vector3 {
    const closest = line.start.closestPointOnLine(line.end, body.position);

    inline for (.{ "x", "y", "z" }) |axis| {
        const min = @field(body.position, axis) - @field(body.box, axis) / 2.0;
        const max = @field(body.position, axis) + @field(body.box, axis) / 2.0;

        if (@field(closest, axis) < min or max < @field(closest, axis)) return null;
    }

    return closest;
}
