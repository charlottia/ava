const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Args = @import("./Args.zig");
const Font = imtuilib.Font;
const Imtui = imtuilib.Imtui;

extern fn SetProcessDPIAware() bool;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try Args.parse(allocator);
    defer args.deinit();

    const filename = args.filename;
    const scale = args.scale;

    // TODO: refactor init with adc.
    try SDL.init(.{ .video = true, .events = true });
    defer SDL.quit();

    try SDL.image.init(.{ .png = true });
    defer SDL.image.quit();

    if ((comptime builtin.target.os.tag == .windows) and !SetProcessDPIAware())
        std.log.debug("failed to set process DPI aware", .{});

    var font = try Font.fromGlyphTxt(allocator, imtuilib.fonts.@"9x16");
    defer font.deinit();

    var hdpi: f32 = -1;
    var vdpi: f32 = -1;

    // TODO: expose this in SDL.zig. (And adjust the C stub to allow nulls!)
    if (SDL.c.SDL_GetDisplayDPI(0, null, &hdpi, &vdpi) < 0)
        std.debug.panic("couldn't get display dpi", .{});

    const dm = try SDL.DisplayMode.getDesktopInfo(0);
    std.log.debug("display 0: {d}x{d} px, dpi {d}x{d} ppi", .{ dm.w, dm.h, hdpi, vdpi });

    var eff_scale = scale orelse 1.0;

    const request_width: usize = @intFromFloat(@as(f32, @floatFromInt(80 * font.char_width)) * eff_scale);
    const request_height: usize = @intFromFloat(@as(f32, @floatFromInt(25 * font.char_height)) * eff_scale);

    var window = try SDL.createWindow(
        "TextMode Designer",
        .default,
        .default,
        request_width,
        request_height,
        .{ .allow_high_dpi = true },
    );
    defer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{ .accelerated = true, .target_texture = true, .present_vsync = true });
    defer renderer.destroy();

    if ((try renderer.getOutputSize()).width_pixels == window.getSize().width * 2) {
        // We got given a hidpi window. (e.g. macOS)
        std.log.debug("native hidpi", .{});
        try renderer.setScale(eff_scale * 2, eff_scale * 2);
    } else if ((hdpi >= 100 or vdpi >= 100) and scale == null) {
        // We didn't get a hidpi window, but we'd probably like one? (e.g. Wayland??)
        std.log.debug("manual hidpi", .{});
        eff_scale = 2;
        // XXX: this is exposed in more recent SDL.zig, but they're now
        // targetting 0.14.0-dev and we aren't.
        SDL.c.SDL_SetWindowSize(window.ptr, @intCast(request_width * 2), @intCast(request_height * 2));
        try renderer.setScale(eff_scale, eff_scale);
    } else {
        std.log.debug("no hidpi", .{});
        try renderer.setScale(eff_scale, eff_scale);
    }

    _ = try SDL.showCursor(false);

    std.log.debug("request wxh:           {d}x{d}", .{ request_width, request_height });
    std.log.debug("window wxh:            {d}x{d}", .{ window.getSize().width, window.getSize().height });
    std.log.debug("renderer output wxh:   {d}x{d}", .{ (try renderer.getOutputSize()).width_pixels, (try renderer.getOutputSize()).height_pixels });
    std.log.debug("renderer viewport wxh: {d}x{d}", .{ renderer.getViewport().width, renderer.getViewport().height });

    const underlay = if (filename) |f| i: {
        const d = try std.fs.cwd().readFileAllocOptions(allocator, f, 10485760, null, @alignOf(u8), 0);
        defer allocator.free(d);
        const t = try SDL.image.loadTextureMem(renderer, d, .png);
        try t.setAlphaMod(128);
        try t.setBlendMode(.blend);
        break :i t;
    } else null;

    var imtui = try Imtui.init(allocator, renderer, font, eff_scale);
    defer imtui.deinit();

    while (imtui.running) {
        while (SDL.pollEvent()) |ev|
            try imtui.processEvent(ev);

        try imtui.newFrame();

        var button = try imtui.button(10, 10, 0x4f, "hello every-nyan!");
        if (button.chosen()) {
            std.log.debug("wark", .{});
        }

        if (imtui.focus_stack.items.len == 0)
            try imtui.focus_stack.append(imtui.allocator, button.impl.control());

        try imtui.render();

        if (underlay) |t|
            try renderer.copy(t, null, null);

        renderer.present();
    }
}
