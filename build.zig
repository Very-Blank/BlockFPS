const std = @import("std");
const cimgui = @import("cimgui_zig");
const Renderer = cimgui.Renderer;
const Platform = cimgui.Platform;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const glfw_dependency = b.dependency("glfw_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const imqui_dependency = b.dependency("cimgui_zig", .{
        .target = target,
        .optimize = optimize,
        .platforms = &[_]Platform{.GLFW},
        .renderers = &[_]Renderer{.OpenGL3},
        .docking = false,
    });

    const math_dependency = b.dependency("ZigMath", .{ .target = target, .optimize = optimize });
    const ecs_dependency = b.dependency("ECS", .{ .target = target, .optimize = optimize });

    const glad_path = b.path("libs/glad/");

    const glad: std.Build.Module.Import = .{
        .name = "glad",
        .module = init_glad_module: {
            const translate_c = b.addTranslateC(
                .{
                    .root_source_file = glad_path.path(b, "include/glad/glad.h"),
                    .link_libc = true,
                    .optimize = optimize,
                    .target = target,
                },
            );

            translate_c.addAfterIncludePath(glad_path.path(b, "include/"));
            break :init_glad_module translate_c.createModule();
        },
    };

    const glfw: std.Build.Module.Import = .{
        .name = "glfw",
        .module = init_glfw_module: {
            const glfw_path = glfw_dependency.path("glfw/include/GLFW/");
            const translate_c = b.addTranslateC(
                .{
                    .root_source_file = glfw_path.path(b, "glfw3.h"),
                    .link_libc = true,
                    .optimize = optimize,
                    .target = target,
                },
            );

            translate_c.defineCMacro("GLFW_INCLUDE_NONE", null);
            translate_c.addAfterIncludePath(glfw_path);

            break :init_glfw_module translate_c.createModule();
        },
    };

    const imgui: std.Build.Module.Import = .{
        .name = "imgui",
        .module = init_imgui_module: {
            const imgui_path = imqui_dependency.path("dcimgui/master/");

            const write_files = b.addWriteFiles();
            const imgui_header = write_files.add("imgui_all.h",
                \\#include "dcimgui.h"
                \\#include "backends/dcimgui_impl_glfw.h"
                \\#include "backends/dcimgui_impl_opengl3.h"
            );

            const translate_c = b.addTranslateC(.{
                .root_source_file = imgui_header,
                .link_libc = true,
                .optimize = optimize,
                .target = target,
            });

            translate_c.addIncludePath(imgui_path);
            translate_c.addIncludePath(imgui_path.path(b, "backends"));

            break :init_imgui_module translate_c.createModule();
        },
    };

    const exe = b.addExecutable(.{
        .name = "NewFPS",
        .root_module = init_exe_module: {
            const exe_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    glad,
                    glfw,
                    imgui,
                    .{ .name = "math", .module = math_dependency.module("zigmath") },
                    .{ .name = "ecs", .module = ecs_dependency.module("ecs") },
                },
            });

            exe_module.linkLibrary(glfw_dependency.artifact("glfw"));
            exe_module.linkLibrary(imqui_dependency.artifact("cimgui"));

            exe_module.addAfterIncludePath(glad_path.path(b, "include/"));
            exe_module.addCSourceFile(.{ .file = glad_path.path(b, "src/glad.c") });

            exe_module.addOptions("build_options", init_options: {
                const options = b.addOptions();
                options.addOption(bool, "debug", b.option(bool, "debug", "Enables debug mode, otherwise debug mode is not accessible.") orelse false);
                break :init_options options;
            });

            break :init_exe_module exe_module;
        },
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
