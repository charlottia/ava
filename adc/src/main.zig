const std = @import("std");
const Allocator = std.mem.Allocator;
const serial = @import("serial");
const SDL = @import("sdl2");

const proto = @import("avacore").proto;
const Parser = @import("avabasic").Parser;
const Compiler = @import("avabasic").Compiler;
const Args = @import("./Args.zig");
const EventThread = @import("./EventThread.zig");
const Kyuubey = @import("./Kyuubey.zig");
const Font = @import("./Font.zig");
const Imtui = @import("./Imtui.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try Args.parse(allocator);
    defer args.deinit();

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

    try SDL.init(.{ .video = true, .events = true });
    defer SDL.quit();

    var font = try Font.fromGlyphTxt(allocator, @embedFile("fonts/9x16.txt"));
    defer font.deinit();

    const request_width: usize = @intFromFloat(@as(f32, @floatFromInt(80 * font.char_width)) * scale);
    const request_height: usize = @intFromFloat(@as(f32, @floatFromInt(25 * font.char_height)) * scale);

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

    if ((try renderer.getOutputSize()).width_pixels == request_width * 2)
        try renderer.setScale(scale * 2, scale * 2)
    else
        try renderer.setScale(scale, scale);

    _ = try SDL.showCursor(false);

    // _ = filename;
    // var qb = try Kyuubey.init(allocator, renderer, font, filename);
    // defer qb.deinit();

    var imtui = try Imtui.init(allocator, renderer, font, scale);
    defer imtui.deinit();

    var primary_source = try Imtui.Controls.Editor.Source.createUntitled(allocator);
    defer primary_source.release();

    var immediate_source = try Imtui.Controls.Editor.Source.createImmediate(allocator);
    defer immediate_source.release();

    while (imtui.running) {
        while (SDL.pollEvent()) |ev|
            imtui.processEvent(ev);

        try imtui.newFrame();

        var editor = try imtui.editor(1, 0, 21, 80, 0);
        editor.source(primary_source);
        editor.end();

        var imm_editor = try imtui.editor(21, 0, 24, 80, 1);
        imm_editor.immediate();
        imm_editor.source(immediate_source);
        imm_editor.end();

        var menubar = try imtui.menubar(0, 0, 80);

        var file_menu = try menubar.menu("&File", 16);
        _ = (try file_menu.item("&New Program")).help("Removes currently loaded program from memory");
        _ = (try file_menu.item("&Open Program...")).help("Loads new program into memory");
        _ = (try file_menu.item("&Merge...")).help("Inserts specified file into current module");
        _ = (try file_menu.item("&Save")).help("Writes current module to file on disk");
        _ = (try file_menu.item("Save &As...")).help("Saves current module with specified name and format");
        _ = (try file_menu.item("Sa&ve All")).help("Writes all currently loaded modules to files on disk");
        try file_menu.separator();
        _ = (try file_menu.item("&Create File...")).help("Creates a module, include file, or document; retains loaded modules");
        _ = (try file_menu.item("&Load File...")).help("Loads a module, include file, or document; retains loaded modules");
        _ = (try file_menu.item("&Unload File...")).help("Removes a loaded module, include file, or document from memory");
        try file_menu.separator();
        _ = (try file_menu.item("&Print...")).help("Prints specified text or module");
        _ = (try file_menu.item("&DOS Shell")).help("Temporarily suspends ADC and invokes DOS shell"); // uhh
        try file_menu.separator();
        var exit = (try file_menu.item("E&xit")).help("Exits ADC and returns to DOS");
        if (exit.chosen()) {
            imtui.running = false;
        }
        try file_menu.end();

        var edit_menu = try menubar.menu("&Edit", 20);
        _ = (try edit_menu.item("&Undo")).disabled().shortcut(.backspace, .alt).help("Restores current edited line to its original condition");
        _ = (try edit_menu.item("Cu&t")).disabled().shortcut(.delete, .shift).help("Deletes selected text and copies it to buffer");
        _ = (try edit_menu.item("&Copy")).disabled().shortcut(.insert, .ctrl).help("Copies selected text to buffer");
        _ = (try edit_menu.item("&Paste")).shortcut(.insert, .shift).help("Inserts buffer contents at current location");
        _ = (try edit_menu.item("Cl&ear")).disabled().shortcut(.delete, null).help("Deletes selected text without copying it to buffer");
        try edit_menu.separator();
        _ = (try edit_menu.item("New &SUB...")).help("Opens a window for a new subprogram");
        _ = (try edit_menu.item("New &FUNCTION...")).help("Opens a window for a new FUNCTION procedure");
        try edit_menu.end();

        var view_menu = try menubar.menu("&View", 21);
        _ = (try view_menu.item("&SUBs...")).shortcut(.f2, null).help("Displays a loaded SUB, FUNCTION, module, include file, or document");
        _ = (try view_menu.item("N&ext SUB")).shortcut(.f2, .shift).help("Displays next SUB or FUNCTION procedure in the active window");
        _ = (try view_menu.item("S&plit")).help("Divides screen into two View windows");
        try view_menu.separator();
        _ = (try view_menu.item("&Next Statement")).help("Displays next statement to be executed");
        _ = (try view_menu.item("O&utput Screen")).shortcut(.f4, null).help("Displays output screen");
        try view_menu.separator();
        _ = (try view_menu.item("&Included File")).help("Displays include file for editing");
        _ = (try view_menu.item("Included &Lines")).help("Displays include file for viewing only (not for editing)");
        try view_menu.end();

        var search_menu = try menubar.menu("&Search", 24);
        _ = (try search_menu.item("&Find...")).help("Finds specified text");
        _ = (try search_menu.item("&Selected Text")).shortcut(.backslash, .ctrl).help("Finds selected text");
        _ = (try search_menu.item("&Repeat Last Find")).shortcut(.f3, null).help("Finds next occurrence of text specified in previous search");
        _ = (try search_menu.item("&Change...")).help("Finds and changes specified text");
        _ = (try search_menu.item("&Label...")).help("Finds specified line label");
        try search_menu.end();

        var run_menu = try menubar.menu("&Run", 19);
        _ = (try run_menu.item("&Start")).shortcut(.f5, .shift).help("Runs current program");
        _ = (try run_menu.item("&Restart")).help("Clears variables in preparation for restarting single stepping");
        _ = (try run_menu.item("Co&ntinue")).shortcut(.f5, null).help("Continues execution after a break");
        _ = (try run_menu.item("Modify &COMMAND$...")).help("Sets string returned by COMMAND$ function");
        try run_menu.separator();
        _ = (try run_menu.item("Make E&XE File...")).help("Creates executable file on disk");
        _ = (try run_menu.item("Make &Library...")).help("Creates Quick library and stand-alone (.LIB) library on disk"); // XXX ?
        try run_menu.separator();
        _ = (try run_menu.item("Set &Main Module...")).help("Makes the specified module the main module");
        try run_menu.end();

        var debug_menu = try menubar.menu("&Debug", 27);
        _ = (try debug_menu.item("&Add Watch...")).help("Adds specified expression to the Watch window");
        _ = (try debug_menu.item("&Instant Watch...")).shortcut(.f9, .shift).help("Displays the value of a variable or expression");
        _ = (try debug_menu.item("&Watchpoint...")).help("Causes program to stop when specified expression is TRUE");
        _ = (try debug_menu.item("&Delete Watch...")).disabled().help("Deletes specified entry from Watch window");
        _ = (try debug_menu.item("De&lete All Watch")).disabled().help("Deletes all Watch window entries");
        try debug_menu.separator();
        _ = (try debug_menu.item("&Trace On")).help("Highlights statement currently executing");
        _ = (try debug_menu.item("&History On")).help("Records statement execution order");
        try debug_menu.separator();
        _ = (try debug_menu.item("Toggle &Breakpoint")).shortcut(.f9, null).help("Sets/clears breakpoint at cursor location");
        _ = (try debug_menu.item("&Clear All Breakpoints")).help("Removes all breakpoints");
        _ = (try debug_menu.item("Break on &Errors")).help("Stops execution at first statement in error handler");
        _ = (try debug_menu.item("&Set Next Statement")).disabled().help("Indicates next statement to be executed");
        try debug_menu.end();

        var calls_menu = try menubar.menu("&Calls", 10);
        _ = (try calls_menu.item("&Untitled")).help("Displays next statement to be executed in module or procedure");
        try calls_menu.end();

        var options_menu = try menubar.menu("&Options", 15);
        _ = (try options_menu.item("&Display...")).help("Changes display attributes");
        _ = (try options_menu.item("Set &Paths...")).help("Sets default search paths");
        _ = (try options_menu.item("Right &Mouse...")).help("Changes action of right mouse click");
        // TODO: bullet point 'check boxes' to left of these items
        _ = (try options_menu.item("&Syntax Checking")).help("Turns editor's syntax checking on or off."); // This '.' is [sic].
        _ = (try options_menu.item("&Full Menus")).help("Toggles between Easy and Full Menu usage");
        try options_menu.end();

        var help_menu = try menubar.menu("&Help", 25);
        _ = (try help_menu.item("&Index")).help("Displays help index");
        _ = (try help_menu.item("&Contents")).help("Displays help table of contents");
        _ = (try help_menu.item("&Topic: XXX")).shortcut(.f1, null).help("Displays information about the BASIC keyword the cursor is on");
        _ = (try help_menu.item("&Help on Help")).shortcut(.f1, .shift).help("Displays help on help");
        try help_menu.end();

        imtui.text_mode.paint(24, 0, 25, 80, 0x30, .Blank);
        var show_ruler = true;
        switch (imtui.focus) {
            .menu => |m| {
                const help_text = menubar.itemAt(m).help_text.?;
                imtui.text_mode.write(24, 1, "F1=Help");
                imtui.text_mode.draw(24, 9, 0x30, .Vertical);
                imtui.text_mode.write(24, 11, help_text);
                show_ruler = (11 + help_text.len) <= 62;
            },
            .menubar => imtui.text_mode.write(24, 1, "F1=Help   Enter=Display Menu   Esc=Cancel   Arrow=Next Item"),
            else => {
                var help_button = try imtui.button(24, 1, 0x30, "<Shift+F1=Help>");
                if (help_button.chosen()) {
                    // TODO do same as "&Help on Help"
                }
                var window_button = try imtui.button(24, 17, 0x30, "<F6=Window>");
                if (window_button.chosen()) {
                    // XXX
                    imtui.focus_editor = (imtui.focus_editor + 1) % 2;
                }

                _ = try imtui.button(24, 29, 0x30, "<F2=Subs>");
                if ((try imtui.button(24, 39, 0x30, "<F5=Run>")).chosen()) {
                    std.debug.print("run!\n", .{});
                }
                _ = try imtui.button(24, 48, 0x30, "<F8=Step>");

                // TODO During active execution, these change to:
                // <Shift+F1=Help> <F5=Continue> <F9=Toggle Bkpt> <F8=Step>

                // TODO: When the Immediate window is focussed (regardless of
                // active execution), these change to:
                // <Shift+F1=Help> <F6=Window> <Enter=Execute Line>
            },
        }

        var f6 = try imtui.shortcut(.f6, null);
        if (f6.chosen()) {
            // XXX
            imtui.focus_editor = (imtui.focus_editor + 1) % 2;
        }

        if (show_ruler) {
            imtui.text_mode.draw(24, 62, 0x30, .Vertical);
            var buf: [9]u8 = undefined;
            // _ = try std.fmt.bufPrint(&buf, "{d:0>5}:{d:0>3}", .{ active_editor.cursor_row + 1, active_editor.cursor_col + 1 });
            _ = try std.fmt.bufPrint(&buf, "{d:0>5}:{d:0>3}", .{ 1, 1 });
            imtui.text_mode.write(24, 70, &buf);
        }

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
