const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const SDL = @import("sdl2");

const Font = @import("./Font.zig");
const fonts = @import("./root.zig").fonts;

extern fn SetProcessDPIAware() bool;

const App = @This();

pub const Config = struct {
    title: [:0]const u8 = "Imtui App",
    scale: ?f32 = null,
    sdl_image: bool = false,
};

config: Config,
font: Font,
window: SDL.Window,
renderer: SDL.Renderer,
eff_scale: f32,

pub fn init(allocator: Allocator, config: Config) !App {
    try SDL.init(.{ .video = true, .events = true });
    errdefer SDL.quit();

    if (config.sdl_image)
        try SDL.image.init(.{ .png = true });
    errdefer if (config.sdl_image) SDL.image.quit();

    if ((comptime builtin.target.os.tag == .windows) and !SetProcessDPIAware())
        std.log.info("failed to set process DPI aware", .{});

    var font = try Font.fromGlyphTxt(allocator, fonts.@"9x16");
    errdefer font.deinit();

    var hdpi: f32 = -1;
    var vdpi: f32 = -1;

    // TODO: expose this in SDL.zig. (And adjust the C stub to allow nulls!)
    if (SDL.c.SDL_GetDisplayDPI(0, null, &hdpi, &vdpi) < 0)
        std.debug.panic("couldn't get display dpi", .{});

    const dm = try SDL.DisplayMode.getDesktopInfo(0);
    std.log.debug("display 0: {d}x{d} px, dpi {d}x{d} ppi", .{ dm.w, dm.h, hdpi, vdpi });

    var eff_scale = config.scale orelse 1.0;

    const request_width: usize = @intFromFloat(@as(f32, @floatFromInt(80 * font.char_width)) * eff_scale);
    const request_height: usize = @intFromFloat(@as(f32, @floatFromInt(25 * font.char_height)) * eff_scale);

    var window = try SDL.createWindow(
        config.title,
        .default,
        .default,
        request_width,
        request_height,
        .{ .allow_high_dpi = true },
    );
    errdefer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{ .accelerated = true, .target_texture = true, .present_vsync = true });
    errdefer renderer.destroy();

    if ((try renderer.getOutputSize()).width_pixels == window.getSize().width * 2) {
        // We got given a hidpi window. (e.g. macOS)
        std.log.debug("native hidpi", .{});
        try renderer.setScale(eff_scale * 2, eff_scale * 2);
    } else if ((hdpi >= 100 or vdpi >= 100) and config.scale == null) {
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

    return .{
        .config = config,
        .font = font,
        .window = window,
        .renderer = renderer,
        .eff_scale = eff_scale,
    };
}

pub fn deinit(self: *const App) void {
    self.renderer.destroy();
    self.window.destroy();
    self.font.deinit();

    if (self.config.sdl_image)
        SDL.image.quit();

    SDL.quit();
}
