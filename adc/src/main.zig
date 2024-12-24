const std = @import("std");
// const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

// const proto = @import("avacore").proto;
// const Parser = @import("avabasic").Parser;
// const Compiler = @import("avabasic").Compiler;
// const EventThread = @import("./EventThread.zig");
const Args = @import("./Args.zig");
const Font = imtuilib.Font;
const Imtui = imtuilib.Imtui;
const App = imtuilib.App;
const Adc = @import("./Adc.zig");

extern fn SetProcessDPIAware() bool;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try Args.parse(allocator);
    defer args.deinit();

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

    const app = try App.init(allocator, .{
        .title = "Ava BASIC ADC",
        .scale = args.scale,
    });
    defer app.deinit();

    var imtui = try Imtui.init(allocator, app.renderer, app.font, app.eff_scale);
    defer imtui.deinit();

    const primary_source = if (args.filename) |f|
        try Imtui.Controls.Source.createDocumentFromFile(allocator, f)
    else
        try Imtui.Controls.Source.createUntitledDocument(allocator);

    var adc = try Adc.init(imtui, prefs, primary_source);
    defer adc.deinit();

    while (imtui.running) {
        while (SDL.pollEvent()) |ev|
            try imtui.processEvent(ev);

        try imtui.newFrame();
        try adc.render();
        try imtui.render();
        app.renderer.present();

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
