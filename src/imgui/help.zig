const std = @import("std");
const imgui = @import("imgui");
const standards = @import("standards.zig");

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
    name: [:0]const u8,
    options: struct { speed: f32 = 0.01, min: f32 = -1000.0, max: f32 = 1000.0 },
) void {
    inline for (.{ "x", "y", "z" }) |field| {
        _ = imgui.ImGui_DragFloatEx(.{std.ascii.toUpper(field[0])} ++ name, @ptrCast(&@field(value, field)), options.speed, options.min, options.max, "%.3f", 0);
    }
}

pub inline fn enumSelector(comptime T: type, value: *T, name: [:0]const u8) void {
    switch (@typeInfo(T)) {
        .@"enum" => {},
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

    imgui.ImGui_PushItemWidth(standards.width);

    if (imgui.ImGui_ComboEx(name, &current, names.ptr, -1)) {
        inline for (@typeInfo(T).@"enum".fields, 0..) |field, i| {
            if (current == i) {
                value.* = @enumFromInt(field.value);
            }
        }
    }

    imgui.ImGui_PopItemWidth();
}
