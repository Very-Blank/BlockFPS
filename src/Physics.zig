const std = @import("std");
const ecs = @import("ecs");
const math = @import("math");

const Ecs = @import("ecs.zig").Ecs;
const Template = ecs.Template;

const Position = @import("components/position.zig").Position;
const Collider = @import("components/collider.zig").Collider;
const Rigidbody = @import("components/Rigidbody.zig");

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
            if (collision(rigidbody, staticbody)) {
                const body1_pos: *Position = rigidbody[0];
                const body1_rb: *Rigidbody = rigidbody[2];

                const body2_pos: *Position = staticbody[0];

                const normal, const depth = init_info: {
                    var info = overlap(rigidbody, staticbody);
                    const depth = info.length();
                    if (depth < 0.000000001) continue;

                    const normal = info.normalize();

                    break :init_info .{ if (body1_pos.subtract(body2_pos.*).dot(normal) < 0) normal.negate() else normal, depth };
                };

                body1_pos.* = body1_pos.add(normal.scale(depth));

                const dot = body1_rb.velocity.dot(normal);
                body1_rb.velocity = body1_rb.velocity.subtract(normal.scale(1.65 * dot * body1_rb.restitution));
            }
        }

        staticbodies.reset();
    }
}

pub fn simulateRb(delta_time: f32, iterator: *Ecs.TupleIterator(.{
    .include = ecs.Template{ .components = &.{ Position, Collider, Rigidbody } },
})) void {
    const gravity: f32 = 9.81;
    const friction: f32 = 0.0025;

    while (iterator.next()) |body| {
        const rigidbody: *Rigidbody = body[2];

        rigidbody.velocity.y -= gravity * delta_time;
        rigidbody.velocity = rigidbody.velocity.scale(1.0 - friction);
    }

    iterator.reset();

    var inner_iterator = iterator.*;

    while (iterator.next()) |body1| {
        inner_iterator.current_index = iterator.current_index;
        inner_iterator.current_buffer = iterator.current_buffer;

        while (inner_iterator.next()) |body2| {
            if (collision(body1, body2)) {
                const body1_pos: *Position = body1[0];
                const body1_rb: *Rigidbody = body1[2];

                const body2_pos: *Position = body2[0];
                const body2_rb: *Rigidbody = body2[2];

                std.debug.assert(body1_rb.mass != 0.0);
                std.debug.assert(body2_rb.mass != 0.0);

                const normal, const depth = init_info: {
                    var info = overlap(body1, body2);
                    const depth = info.length();
                    if (depth < 0.000000001) continue;

                    const normal = info.normalize();

                    break :init_info .{ if (body1_pos.subtract(body2_pos.*).dot(normal) < 0) normal.negate() else normal, depth };
                };

                const ratio: f32 = body2_rb.mass / (body1_rb.mass + body2_rb.mass);

                body1_pos.* = body1_pos.add(normal.scale(ratio * depth));
                body2_pos.* = body2_pos.add(normal.scale((1.0 - ratio) * depth).negate());

                const e = (body1_rb.restitution + body2_rb.restitution) / 2.0;

                const @"m_a*v_a + m_b*v_b" = body1_rb.velocity.scale(body1_rb.mass).add(body2_rb.velocity.scale(body2_rb.mass));
                const @"m_a+m_b" = body1_rb.mass + body2_rb.mass;

                const v_a = body1_rb.velocity;
                const v_b = body2_rb.velocity;

                body1_rb.velocity = @"m_a*v_a + m_b*v_b".add(v_b.subtract(v_a).scale(e * body2_rb.mass)).segment(@"m_a+m_b");
                body2_rb.velocity = @"m_a*v_a + m_b*v_b".add(v_a.subtract(v_b).scale(e * body1_rb.mass)).segment(@"m_a+m_b");
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

pub inline fn collision(
    body1: anytype,
    body2: anytype,
) bool {
    const body1_pos: *Position = body1[0];
    const body1_col: *Collider = body1[1];

    const body2_pos: *Position = body2[0];
    const body2_col: *Collider = body2[1];

    inline for (.{ "x", "y", "z" }) |axis| {
        const min = @field(body1_pos, axis) - @field(body1_col, axis) / 2.0;
        const max = @field(body1_pos, axis) + @field(body1_col, axis) / 2.0;

        const a = @field(body2_pos, axis) - @field(body2_col, axis) / 2.0;
        const b = @field(body2_pos, axis) + @field(body2_col, axis) / 2.0;

        if (b < min or max < a) return false;
    }

    return true;
}

pub inline fn overlap(
    body1: anytype,
    body2: anytype,
) math.f32.Vector3 {
    const x = axisOverlap("x", body1, body2);
    const y = axisOverlap("y", body1, body2);
    const z = axisOverlap("z", body1, body2);

    if (x <= y and x <= z) return .{ .x = x };
    if (y <= x and y <= z) return .{ .y = y };
    return .{ .z = z };
}

pub inline fn axisOverlap(
    comptime axis: []const u8,
    body1: anytype,
    body2: anytype,
) f32 {
    const body1_pos: *Position = body1[0];
    const body1_col: *Collider = body1[1];

    const body2_pos: *Position = body2[0];
    const body2_col: *Collider = body2[1];

    const min1 = @field(body1_pos, axis) - @field(body1_col, axis) / 2.0;
    const max1 = @field(body1_pos, axis) + @field(body1_col, axis) / 2.0;

    const min2 = @field(body2_pos, axis) - @field(body2_col, axis) / 2.0;
    const max2 = @field(body2_pos, axis) + @field(body2_col, axis) / 2.0;

    return @min(max1, max2) - @max(min1, min2);
}
