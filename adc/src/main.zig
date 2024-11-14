const std = @import("std");
const Allocator = std.mem.Allocator;
const serial = @import("serial");
const SDL = @import("sdl2");

const proto = @import("avacore").proto;
const Parser = @import("avabasic").Parser;
const Compiler = @import("avabasic").Compiler;
const Args = @import("./Args.zig");
const EventThread = @import("./EventThread.zig");
const Font = @import("./Font.zig");
const Imtui = @import("./Imtui.zig");

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

    var imtui = try Imtui.init(allocator, renderer, font, scale);
    defer imtui.deinit();

    // QB has files loaded in background, so we too should notice that not every
    // Source need correspond with an Editor, and thus we need an owner for the
    // library of open Sources.
    // Initial Untitled doesn't behave any different to a regular Source in
    // QBASIC, with the exception that it knows it lacks a name and/or backing
    // filename to write back out to.
    // Immediate is its whole own beast and is never confused for any other; it
    // stays separate.

    const primary_source = if (filename) |f|
        try Imtui.Controls.Editor.Source.createFromFile(allocator, f)
    else
        try Imtui.Controls.Editor.Source.createUntitled(allocator);

    var adc = try Adc.init(imtui, primary_source);
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

const Adc = struct {
    imtui: *Imtui,

    sources: std.ArrayList(*Imtui.Controls.Editor.Source),

    // primary + secondary don't do their own acquire; sources holds all the
    // lifetimes.
    primary_source: *Imtui.Controls.Editor.Source,
    secondary_source: *Imtui.Controls.Editor.Source,

    immediate_source: *Imtui.Controls.Editor.Source,

    view: union(enum) {
        two: [2]usize,
        three: [3]usize,
    } = .{ .two = [2]usize{ 20, 3 } },
    fullscreen: bool = false,

    fn init(imtui: *Imtui, primary_source: *Imtui.Controls.Editor.Source) !Adc {
        errdefer primary_source.release();

        var sources = std.ArrayList(*Imtui.Controls.Editor.Source).init(imtui.allocator);
        errdefer sources.deinit();
        try sources.append(primary_source);

        var immediate_source = try Imtui.Controls.Editor.Source.createImmediate(imtui.allocator);
        errdefer immediate_source.release();

        return .{
            .imtui = imtui,
            .sources = sources,
            .primary_source = primary_source,
            .secondary_source = primary_source,
            .immediate_source = immediate_source,
        };
    }

    fn deinit(self: Adc) void {
        for (self.sources.items) |s|
            s.release();
        self.sources.deinit();
        self.immediate_source.release();
    }

    fn render(self: *Adc) !void {
        // We have 23 lines to work with in total.
        // An editor must be at least 1 line long.
        // Initial state is 2 editors, of heights 20 and 3.
        // Post-split divides the first height in half, rounding onto the second;
        // e.g. 19 and 4 splits into 9, 10 and 4.
        // Undoing the split absorbs the second into the first.
        // Immediate can be at most 11 lines high.
        // Fullscreen shows only one editor on all 23 lines, including immediate.

        // XXX ??? estupendo
        const editor_height: usize = if (self.fullscreen)
            if (self.imtui.focus_editor == 0)
                23
            else
                0
        else switch (self.view) {
            inline .two, .three => |a| a[0],
        };
        const secondary_editor_height: usize = if (self.fullscreen)
            if (self.imtui.focus_editor == 1)
                23
            else
                0
        else switch (self.view) {
            .two => |_| 0,
            .three => |a| a[1],
        };
        const imm_editor_height: usize = if (self.fullscreen)
            if (self.imtui.focus_editor == 2)
                23
            else
                0
        else switch (self.view) {
            .two => |a| a[1],
            .three => |a| a[2],
        };

        const editor_top = 1;
        const editor_bottom = editor_top + editor_height;

        const secondary_editor_top = editor_bottom;
        const secondary_editor_bottom = secondary_editor_top + secondary_editor_height;

        const imm_editor_top = secondary_editor_bottom;
        const imm_editor_bottom = imm_editor_top + imm_editor_height;
        std.debug.assert(imm_editor_bottom == 24);

        var editor = try self.imtui.editor(0, editor_top, 0, editor_bottom, 80);
        editor.source(self.primary_source);
        if (self.fullscreen and self.imtui.focus_editor != 0)
            editor.hidden();
        editor.end();

        var secondary_editor = try self.imtui.editor(1, secondary_editor_top, 0, secondary_editor_bottom, 80);
        secondary_editor.source(self.secondary_source);
        if (self.view == .two or (self.fullscreen and self.imtui.focus_editor != 1))
            secondary_editor.hidden()
        else if (secondary_editor.headerDraggedTo()) |row| if (row >= 2 and row <= 22) {
            const a = &self.view.three;
            if (row > secondary_editor_top) {
                for (0..row - secondary_editor_top) |_|
                    secondaryDown(a);
            } else if (row < secondary_editor_top) {
                for (0..secondary_editor_top - row) |_|
                    secondaryUp(a);
            }
        };
        secondary_editor.end();

        var imm_editor = try self.imtui.editor(2, imm_editor_top, 0, imm_editor_bottom, 80);
        if (self.fullscreen and self.imtui.focus_editor != 2)
            imm_editor.hidden()
        else if (!self.fullscreen)
            if (imm_editor.headerDraggedTo()) |row| if (row >= 13 and row <= 23) {
                const new_imm_h = 24 - row;
                switch (self.view) {
                    .two => |_| self.view = .{ .two = [2]usize{ 23 - new_imm_h, new_imm_h } },
                    .three => |*a| {
                        if (new_imm_h < a[2]) {
                            for (0..a[2] - new_imm_h) |_|
                                immDown(a);
                        } else if (new_imm_h > a[2]) {
                            for (0..new_imm_h - a[2]) |_|
                                immUp(a);
                        }
                    },
                }
            };

        imm_editor.immediate();
        imm_editor.source(self.immediate_source);
        imm_editor.end();

        if (editor.toggledFullscreen() or secondary_editor.toggledFullscreen() or imm_editor.toggledFullscreen())
            self.fullscreen = !self.fullscreen;

        var menubar = try self.imtui.menubar(0, 0, 80);

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
            self.imtui.running = false;
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
        var split_item = (try view_menu.item("S&plit")).help("Divides screen into two View windows");
        if (split_item.chosen())
            self.toggleSplit();
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

        self.imtui.text_mode.paint(24, 0, 25, 80, 0x30, .Blank);
        var show_ruler = true;
        switch (self.imtui.focus) {
            .menu => |m| {
                const help_text = menubar.itemAt(m).help_text.?;
                self.imtui.text_mode.write(24, 1, "F1=Help");
                self.imtui.text_mode.draw(24, 9, 0x30, .Vertical);
                self.imtui.text_mode.write(24, 11, help_text);
                show_ruler = (11 + help_text.len) <= 62;
            },
            .menubar => self.imtui.text_mode.write(24, 1, "F1=Help   Enter=Display Menu   Esc=Cancel   Arrow=Next Item"),
            else => {
                var help_button = try self.imtui.button(24, 1, 0x30, "<Shift+F1=Help>");
                if (help_button.chosen()) {
                    // TODO do same as "&Help on Help"
                }
                var window_button = try self.imtui.button(24, 17, 0x30, "<F6=Window>");
                if (window_button.chosen()) {
                    self.windowFunction();
                }

                _ = try self.imtui.button(24, 29, 0x30, "<F2=Subs>");
                if ((try self.imtui.button(24, 39, 0x30, "<F5=Run>")).chosen()) {
                    std.debug.print("run!\n", .{});
                }
                _ = try self.imtui.button(24, 48, 0x30, "<F8=Step>");

                // TODO During active execution, these change to:
                // <Shift+F1=Help> <F5=Continue> <F9=Toggle Bkpt> <F8=Step>

                // TODO: When the Immediate window is focussed (regardless of
                // active execution), these change to:
                // <Shift+F1=Help> <F6=Window> <Enter=Execute Line>
            },
        }

        var f6 = try self.imtui.shortcut(.f6, null);
        if (f6.chosen()) {
            self.windowFunction();
        }

        if (show_ruler) {
            self.imtui.text_mode.draw(24, 62, 0x30, .Vertical);
            const e = try self.imtui.focusedEditor();
            var buf: [9]u8 = undefined;
            _ = try std.fmt.bufPrint(&buf, "{d:0>5}:{d:0>3}", .{ e.cursor_row + 1, e.cursor_col + 1 });
            self.imtui.text_mode.write(24, 70, &buf);
        }
    }

    fn windowFunction(self: *Adc) void {
        if (self.view == .two) {
            self.imtui.focus_editor = if (self.imtui.focus_editor == 0) 2 else 0;
        } else {
            self.imtui.focus_editor = (self.imtui.focus_editor + 1) % 3;
        }
    }

    fn toggleSplit(self: *Adc) void {
        self.fullscreen = false;
        self.imtui.focus_editor = 0;

        switch (self.view) {
            .two => |a| {
                self.secondary_source = self.primary_source;
                self.view = .{ .three = [3]usize{ a[0] / 2, a[0] - (a[0] / 2), a[1] } };
            },
            .three => |a| self.view = .{ .two = [2]usize{ a[0] + a[1], a[2] } },
        }
    }

    fn immDown(a: *[3]usize) void {
        a[1] += 1;
        a[2] -= 1;
    }

    fn immUp(a: *[3]usize) void {
        a[2] += 1;
        if (a[1] > 1)
            a[1] -= 1
        else
            a[0] -= 1;
    }

    fn secondaryDown(a: *[3]usize) void {
        // gives from secondary to primary
        // if secondary empty, gives from imm
        if (a[1] == 1) {
            if (a[2] > 1) {
                a[0] += 1;
                a[2] -= 1;
            }
        } else {
            a[0] += 1;
            a[1] -= 1;
        }
    }

    fn secondaryUp(a: *[3]usize) void {
        if (a[0] > 1) {
            a[0] -= 1;
            a[1] += 1;
        }
    }
};
