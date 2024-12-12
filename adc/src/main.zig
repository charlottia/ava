const std = @import("std");
// const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const SDL = @import("sdl2");

// const proto = @import("avacore").proto;
// const Parser = @import("avabasic").Parser;
// const Compiler = @import("avabasic").Compiler;
// const EventThread = @import("./EventThread.zig");
const Args = @import("./Args.zig");
const Font = @import("./Font.zig");
const Imtui = @import("./Imtui.zig");
const Adc = @import("./Adc.zig");

extern fn SetProcessDPIAware() bool;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try Args.parse(allocator);
    defer args.deinit();

    const filename = args.filename;
    const scale = args.scale;

    //     var handle: std.posix.fd_t = undefined;
    //     var reader: std.io.AnyReader = undefined;
    //     var writer: std.io.AnyWriter = undefined;

    //     switch (args.port) {
    //         .serial => |path| {
    //             const port = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch |err| switch (err) {
    //                 error.FileNotFound => std.debug.panic("file not found accessing '{s}'", .{path}),
    //                 error.Unexpected => std.debug.panic("unexpected error opening '{s}' -- not a serial port?", .{path}),
    //                 else => return err,
    //             };

    //             try serial.configureSerialPort(port, .{
    //                 .baud_rate = 1_500_000,
    //             });

    //             handle = port.handle;
    //             reader = port.reader().any();
    //             writer = port.writer().any();
    //         },
    //         .socket => |path| {
    //             const port = std.net.connectUnixSocket(path) catch |err| switch (err) {
    //                 error.FileNotFound => std.debug.panic("file not found accessing '{s}'", .{path}),
    //                 error.ConnectionRefused => std.debug.panic("connection refused connecting to '{s}' -- cxxrtl not running?", .{path}),
    //                 else => return err,
    //             };

    //             handle = port.handle;
    //             reader = port.reader().any();
    //             writer = port.writer().any();
    //         },
    //     }

    //     return exe(allocator, args.filename, args.scale, handle, reader, writer);
    // }

    // fn exe(
    //     allocator: Allocator,
    //     filename: ?[]const u8,
    //     scale: f32,
    //     handle: std.posix.fd_t,
    //     reader: std.io.AnyReader,
    //     writer: std.io.AnyWriter,
    // ) !void {
    //     var et = try EventThread.init(allocator, reader, handle);
    //     defer et.deinit();

    //     {
    //         try proto.Request.write(.HELLO, writer);
    //         const ev = et.readWait();
    //         defer ev.deinit(allocator);
    //         std.debug.assert(ev == .VERSION);
    //         std.debug.print("connected to {s}\n", .{ev.VERSION});
    //     }

    //     {
    //         try proto.Request.write(.MACHINE_INIT, writer);
    //         const ev = et.readWait();
    //         defer ev.deinit(allocator);
    //         std.debug.assert(ev == .OK);
    //     }

    //     var c = try Compiler.init(allocator, null);
    //     defer c.deinit();

    //     // ---

    var prefs = try Adc.Prefs.init(allocator);
    try prefs.save();
    defer prefs.deinit();

    try SDL.init(.{ .video = true, .events = true });
    defer SDL.quit();

    if ((comptime builtin.target.os.tag == .windows) and !SetProcessDPIAware())
        std.log.debug("failed to set process DPI aware", .{});

    var font = try Font.fromGlyphTxt(allocator, @embedFile("fonts/9x16.txt"));
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
        "Ava BASIC ADC",
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

    var imtui = try Imtui.init(allocator, renderer, font, eff_scale);
    defer imtui.deinit();

    const primary_source = if (filename) |f|
        try Imtui.Controls.Source.createFromFile(allocator, f)
    else
        try Imtui.Controls.Source.createUntitled(allocator);

    var adc = try Adc.init(imtui, prefs, primary_source);
    defer adc.deinit();

    while (imtui.running) {
        while (SDL.pollEvent()) |ev|
            try imtui.processEvent(ev);

        try imtui.newFrame();

        try adc.render();

        try imtui.render();

        // std.debug.print("> ", .{});
        // const inp = try std.io.getStdIn().reader().readUntilDelimiterOrEofAlloc(allocator, '\n', 1048576) orelse return;
        // defer allocator.free(inp);

        // if (std.ascii.eqlIgnoreCase(inp, "~heap")) {
        //     try proto.Request.write(.DUMP_HEAP, writer);
        //     const ev = et.readWait();
        //     defer ev.deinit(allocator);
        //     std.debug.assert(ev == .OK);
        //     continue;
        // }

        // const sx = try Parser.parse(allocator, inp, null);
        // defer Parser.free(allocator, sx);

        // if (sx.len > 0) {
        //     const code = try c.compileStmts(sx);
        //     defer allocator.free(code);

        //     try proto.Request.write(.{ .MACHINE_EXEC = code }, writer);
        //     const ev = et.readWait();
        //     defer ev.deinit(allocator);
        //     std.debug.assert(ev == .OK);
        // }
    }
}
