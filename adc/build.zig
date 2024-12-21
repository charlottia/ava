const std = @import("std");
const SDL = @import("SDL.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdlsdk = SDL.init(b, null);

    const imtui = b.addStaticLibrary(.{
        .name = "imtui",
        .root_source_file = b.path("imtui/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    imtui.linkLibCpp();
    sdlsdk.link(imtui, .dynamic);
    imtui.root_module.addImport("sdl2", sdlsdk.getWrapperModule());

    const adc = b.addExecutable(.{
        .name = "adc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    adc.linkLibCpp();
    adc.root_module.addImport("imtui", &imtui.root_module);

    const avabasic_mod = b.dependency("avabasic", .{
        .target = target,
        .optimize = optimize,
    }).module("avabasic");
    adc.root_module.addImport("avabasic", avabasic_mod);

    const avacore_mod = b.dependency("avacore", .{
        .target = target,
        .optimize = optimize,
    }).module("avacore");
    adc.root_module.addImport("avacore", avacore_mod);

    const serial_mod = b.dependency("serial", .{
        .target = target,
        .optimize = optimize,
    }).module("serial");
    adc.root_module.addImport("serial", serial_mod);

    const known_folders_mod = b.dependency("known-folders", .{
        .target = target,
        .optimize = optimize,
    }).module("known-folders");
    adc.root_module.addImport("known-folders", known_folders_mod);

    b.installArtifact(adc);

    const run_adc_cmd = b.addRunArtifact(adc);
    run_adc_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_adc_cmd.addArgs(args);
    }

    const run_adc_step = b.step("run", "Run the ADC");
    run_adc_step.dependOn(&run_adc_cmd.step);
}
