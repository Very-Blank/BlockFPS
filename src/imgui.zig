const std = @import("std");
const imgui = @import("imgui");
const math = @import("math");

pub fn itoa(comptime value: anytype) [:0]const u8 {
    comptime var string: [:0]const u8 = "";
    comptime var num = value;

    if (num == 0) {
        string = string ++ .{'0'};
    } else {
        while (num != 0) {
            string = .{'0' + (num % 10)} ++ string;
            num = num / 10;
        }
    }

    return string;
}

pub fn pad(comptime value: [:0]const u8, comptime len: usize, comptime side: enum { left, right }) [:0]const u8 {
    comptime var string: [:0]const u8 = value;
    switch (side) {
        .left => {
            while (string.len < len) {
                string = .{' '} ++ string;
            }

            return string;
        },
        .right => {
            while (string.len < len) {
                string = string ++ .{' '};
            }

            return string;
        },
    }
}

pub inline fn vectorField(
    comptime T: type,
    value: *T,
    suffix: [:0]const u8,
    options: struct { speed: f32 = 0.01, min: f32 = -1000.0, max: f32 = 1000.0 },
) void {
    switch (@typeInfo(T)) {
        .@"struct" => {},
        else => @compileError("Unexpected type was given: " ++ @typeName(T) ++ "."),
    }

    if (!@hasDecl(T, "InnerType") or (T.InnerType != math.Type.vector3 and T.InnerType != math.Type.vector2))
        @compileError("Unexpected type was given: " ++ @typeName(T) ++ ".");

    inline for (std.meta.fieldNames(T)) |field| {
        _ = imgui.ImGui_DragFloatEx(.{std.ascii.toUpper(field)} ++ suffix, @ptrCast(&@field(value, field)), options.speed, options.min, options.max, "%.3f", 0);
    }
}

pub inline fn quaternionField(
    comptime T: type,
    value: *T,
    suffix: [:0]const u8,
    options: struct { speed: f32 = 0.01, min: f32 = -1.0, max: f32 = 1.0 },
) void {
    math.assertCompatible(T, .quaternion);
    inline for (.{ "W", "X", "Y", "Z" }, 0..) |field, i| {
        _ = imgui.ImGui_DragFloatEx(field ++ suffix, @ptrCast(&value.fields[i]), options.speed, options.min, options.max, "%.3f", 0);
    }
}

pub inline fn enumSelector(comptime T: type, value: *T, name: [:0]const u8) void {
    switch (@typeInfo(T)) {
        .@"enum" => |@"enum"| if (@typeInfo(@"enum".tag_type) != .int) @compileError("Unexpected tag type."),
        else => @compileError("Unexpected type: " ++ @typeName(T) ++ "."),
    }

    const names: []const u8 = comptime init: {
        var names: []const u8 = "";

        for (@typeInfo(T).@"enum".fields) |field| {
            names = names ++ field.name ++ .{0};
        }

        names = names ++ .{0};

        break :init names;
    };

    var current: i32 = 0;

    inline for (@typeInfo(T).@"enum".fields, 0..) |field, i| {
        if (value.* == @as(T, @enumFromInt(field.value))) {
            current = i;
        }
    }

    if (imgui.ImGui_ComboEx(name, &current, names.ptr, -1)) {
        inline for (@typeInfo(T).@"enum".fields, 0..) |field, i| {
            if (current == i) {
                value.* = @enumFromInt(field.value);
            }
        }
    }
}
