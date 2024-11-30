const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const serial = @import("serial");
const SDL = @import("sdl2");

const proto = @import("avacore").proto;
const Parser = @import("avabasic").Parser;
const Compiler = @import("avabasic").Compiler;
const Args = @import("./Args.zig");
const EventThread = @import("./EventThread.zig");
const Font = @import("./Font.zig");
const Imtui = @import("./Imtui.zig");
const Preferences = @import("./Preferences.zig").Preferences;

extern fn SetProcessDPIAware() bool;

const Prefs = Preferences(struct {
    full_menus: bool = false,
    colours_normal: u8 = 0x17,
    colours_current: u8 = 0x1f,
    colours_breakpoint: u8 = 0x47,
    scrollbars: bool = true,
    tab_stops: u8 = 8,
});

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

    var prefs = try Prefs.init(allocator);
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

const Adc = struct {
    imtui: *Imtui,
    prefs: Prefs,

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
    full_menus: bool,

    display_dialog_visible: bool = false,
    display_dialog_colours_normal: u8 = undefined,
    display_dialog_colours_current: u8 = undefined,
    display_dialog_colours_breakpoint: u8 = undefined,
    display_dialog_scrollbars: bool = undefined,
    display_dialog_tab_stops: u8 = undefined,

    fn init(imtui: *Imtui, prefs: Prefs, primary_source: *Imtui.Controls.Editor.Source) !Adc {
        errdefer primary_source.release();

        var sources = std.ArrayList(*Imtui.Controls.Editor.Source).init(imtui.allocator);
        errdefer sources.deinit();
        try sources.append(primary_source);

        var immediate_source = try Imtui.Controls.Editor.Source.createImmediate(imtui.allocator);
        errdefer immediate_source.release();

        return .{
            .imtui = imtui,
            .prefs = prefs,
            .sources = sources,
            .primary_source = primary_source,
            .secondary_source = primary_source,
            .immediate_source = immediate_source,
            .full_menus = prefs.settings.full_menus,
        };
    }

    fn deinit(self: Adc) void {
        for (self.sources.items) |s|
            s.release();
        self.sources.deinit();
        self.immediate_source.release();
    }

    fn render(self: *Adc) !void {
        try self.renderEditors();
        const menubar = try self.renderMenus();
        try self.renderHelpLine(menubar);

        if (self.display_dialog_visible)
            try self.renderDisplayDialog();
    }

    fn renderEditors(self: *Adc) !void {
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
        editor.colours(
            self.prefs.settings.colours_normal,
            self.prefs.settings.colours_current,
            self.prefs.settings.colours_breakpoint,
        );
        editor.scrollbars(self.prefs.settings.scrollbars);
        editor.tab_stops(self.prefs.settings.tab_stops);
        editor.source(self.primary_source);
        if (self.fullscreen and self.imtui.focus_editor != 0)
            editor.hidden();
        editor.end();

        var secondary_editor = try self.imtui.editor(1, secondary_editor_top, 0, secondary_editor_bottom, 80);
        secondary_editor.colours(
            self.prefs.settings.colours_normal,
            self.prefs.settings.colours_current,
            self.prefs.settings.colours_breakpoint,
        );
        secondary_editor.scrollbars(self.prefs.settings.scrollbars);
        secondary_editor.tab_stops(self.prefs.settings.tab_stops);
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
        imm_editor.colours(
            self.prefs.settings.colours_normal,
            self.prefs.settings.colours_current,
            self.prefs.settings.colours_breakpoint,
        );
        imm_editor.tab_stops(self.prefs.settings.tab_stops);
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
    }

    fn renderMenus(self: *Adc) !*Imtui.Controls.Menubar {
        var menubar = try self.imtui.menubar(0, 0, 80);

        var file_menu = try menubar.menu("&File", 16);
        _ = (try file_menu.item("&New Program")).help("Removes currently loaded program from memory");
        _ = (try file_menu.item("&Open Program...")).help("Loads new program into memory");
        if (self.full_menus) {
            _ = (try file_menu.item("&Merge...")).help("Inserts specified file into current module");
            _ = (try file_menu.item("&Save")).help("Writes current module to file on disk");
        }
        _ = (try file_menu.item("Save &As...")).help("Saves current module with specified name and format");
        if (self.full_menus) {
            _ = (try file_menu.item("Sa&ve All")).help("Writes all currently loaded modules to files on disk");
            try file_menu.separator();
            _ = (try file_menu.item("&Create File...")).help("Creates a module, include file, or document; retains loaded modules");
            _ = (try file_menu.item("&Load File...")).help("Loads a module, include file, or document; retains loaded modules");
            _ = (try file_menu.item("&Unload File...")).help("Removes a loaded module, include file, or document from memory");
        }
        try file_menu.separator();
        _ = (try file_menu.item("&Print...")).help("Prints specified text or module");
        if (self.full_menus)
            _ = (try file_menu.item("&DOS Shell")).help("Temporarily suspends ADC and invokes DOS shell"); // uhh
        try file_menu.separator();
        var exit = (try file_menu.item("E&xit")).help("Exits ADC and returns to DOS");
        if (exit.chosen()) {
            self.imtui.running = false;
        }
        try file_menu.end();

        var edit_menu = try menubar.menu("&Edit", 20);
        if (self.full_menus)
            _ = (try edit_menu.item("&Undo")).disabled().shortcut(.backspace, .alt).help("Restores current edited line to its original condition");
        _ = (try edit_menu.item("Cu&t")).disabled().shortcut(.delete, .shift).help("Deletes selected text and copies it to buffer");
        _ = (try edit_menu.item("&Copy")).disabled().shortcut(.insert, .ctrl).help("Copies selected text to buffer");
        _ = (try edit_menu.item("&Paste")).disabled().shortcut(.insert, .shift).help("Inserts buffer contents at current location");
        if (self.full_menus) {
            _ = (try edit_menu.item("Cl&ear")).disabled().shortcut(.delete, null).help("Deletes selected text without copying it to buffer");
            try edit_menu.separator();
            _ = (try edit_menu.item("New &SUB...")).help("Opens a window for a new subprogram");
            _ = (try edit_menu.item("New &FUNCTION...")).help("Opens a window for a new FUNCTION procedure");
        }
        try edit_menu.end();

        var view_menu = try menubar.menu("&View", 21);
        _ = (try view_menu.item("&SUBs...")).shortcut(.f2, null).help("Displays a loaded SUB, FUNCTION, module, include file, or document");
        if (self.full_menus) {
            _ = (try view_menu.item("N&ext SUB")).shortcut(.f2, .shift).help("Displays next SUB or FUNCTION procedure in the active window");
            var split_item = (try view_menu.item("S&plit")).help("Divides screen into two View windows");
            if (split_item.chosen())
                self.toggleSplit();
            try view_menu.separator();
            _ = (try view_menu.item("&Next Statement")).help("Displays next statement to be executed");
        }
        _ = (try view_menu.item("O&utput Screen")).shortcut(.f4, null).help("Displays output screen");
        if (self.full_menus) {
            try view_menu.separator();
            _ = (try view_menu.item("&Included File")).help("Displays include file for editing");
        }
        _ = (try view_menu.item("Included &Lines")).help("Displays include file for viewing only (not for editing)");
        try view_menu.end();

        var search_menu = try menubar.menu("&Search", 24);
        _ = (try search_menu.item("&Find...")).help("Finds specified text");
        if (self.full_menus) {
            _ = (try search_menu.item("&Selected Text")).shortcut(.backslash, .ctrl).help("Finds selected text");
            _ = (try search_menu.item("&Repeat Last Find")).shortcut(.f3, null).help("Finds next occurrence of text specified in previous search");
        }
        _ = (try search_menu.item("&Change...")).help("Finds and changes specified text");
        if (self.full_menus)
            _ = (try search_menu.item("&Label...")).help("Finds specified line label");
        try search_menu.end();

        var run_menu = try menubar.menu("&Run", 19);
        _ = (try run_menu.item("&Start")).shortcut(.f5, .shift).help("Runs current program");
        _ = (try run_menu.item("&Restart")).help("Clears variables in preparation for restarting single stepping");
        _ = (try run_menu.item("Co&ntinue")).shortcut(.f5, null).help("Continues execution after a break");
        if (self.full_menus)
            _ = (try run_menu.item("Modify &COMMAND$...")).help("Sets string returned by COMMAND$ function");
        try run_menu.separator();
        _ = (try run_menu.item("Make E&XE File...")).help("Creates executable file on disk");
        if (self.full_menus) {
            _ = (try run_menu.item("Make &Library...")).help("Creates Quick library and stand-alone (.LIB) library on disk"); // XXX ?
            try run_menu.separator();
            _ = (try run_menu.item("Set &Main Module...")).help("Makes the specified module the main module");
        }
        try run_menu.end();

        var debug_menu = try menubar.menu("&Debug", 27);
        _ = (try debug_menu.item("&Add Watch...")).help("Adds specified expression to the Watch window");
        _ = (try debug_menu.item("&Instant Watch...")).shortcut(.f9, .shift).help("Displays the value of a variable or expression");
        if (self.full_menus)
            _ = (try debug_menu.item("&Watchpoint...")).help("Causes program to stop when specified expression is TRUE");
        _ = (try debug_menu.item("&Delete Watch...")).disabled().help("Deletes specified entry from Watch window");
        if (self.full_menus) {
            _ = (try debug_menu.item("De&lete All Watch")).disabled().help("Deletes all Watch window entries");
            try debug_menu.separator();
            _ = (try debug_menu.item("&Trace On")).help("Highlights statement currently executing");
            _ = (try debug_menu.item("&History On")).help("Records statement execution order");
        }
        try debug_menu.separator();
        _ = (try debug_menu.item("Toggle &Breakpoint")).shortcut(.f9, null).help("Sets/clears breakpoint at cursor location");
        _ = (try debug_menu.item("&Clear All Breakpoints")).help("Removes all breakpoints");
        if (self.full_menus) {
            _ = (try debug_menu.item("Break on &Errors")).help("Stops execution at first statement in error handler");
            _ = (try debug_menu.item("&Set Next Statement")).disabled().help("Indicates next statement to be executed");
        }
        try debug_menu.end();

        if (self.full_menus) {
            var calls_menu = try menubar.menu("&Calls", 10);
            _ = (try calls_menu.item("&Untitled")).help("Displays next statement to be executed in module or procedure");
            try calls_menu.end();
        }

        var options_menu = try menubar.menu("&Options", 15);
        var display = (try options_menu.item("&Display...")).help("Changes display attributes");
        if (display.chosen())
            self.openDisplayDialog();

        _ = (try options_menu.item("Set &Paths...")).help("Sets default search paths");
        if (self.full_menus) {
            _ = (try options_menu.item("Right &Mouse...")).help("Changes action of right mouse click");
            var syntax_checking = (try options_menu.item("&Syntax Checking")).help("Turns editor's syntax checking on or off."); // This '.' is inconsistent, and [sic].
            syntax_checking.bullet();
        }
        var full_menus = (try options_menu.item("&Full Menus")).help("Toggles between Easy and Full Menu usage");
        if (self.full_menus)
            full_menus.bullet();
        if (full_menus.chosen()) {
            self.full_menus = !self.full_menus;
            self.prefs.settings.full_menus = self.full_menus;
            try self.prefs.save();
        }
        try options_menu.end();

        var help_menu = try menubar.menu("&Help", 25);
        _ = (try help_menu.item("&Index")).help("Displays help index");
        _ = (try help_menu.item("&Contents")).help("Displays help table of contents");
        _ = (try help_menu.item("&Topic: XXX")).shortcut(.f1, null).help("Displays information about the BASIC keyword the cursor is on");
        _ = (try help_menu.item("&Help on Help")).shortcut(.f1, .shift).help("Displays help on help");
        try help_menu.end();

        return menubar;
    }

    fn renderHelpLine(self: *Adc, menubar: *Imtui.Controls.Menubar) !void {
        const help_line_colour: u8 = if (self.full_menus) 0x30 else 0x3f;
        self.imtui.text_mode.paint(24, 0, 25, 80, help_line_colour, .Blank);
        var show_ruler = true;
        switch (self.imtui.focus) {
            .menu => |m| {
                const help_text = menubar.itemAt(m).help_text.?;
                self.imtui.text_mode.write(24, 1, "F1=Help");
                self.imtui.text_mode.draw(24, 9, help_line_colour, .Vertical);
                self.imtui.text_mode.write(24, 11, help_text);
                show_ruler = (11 + help_text.len) <= 62;
            },
            .menubar => {
                self.imtui.text_mode.write(24, 1, "F1=Help   Enter=Display Menu   Esc=Cancel   Arrow=Next Item");
            },
            .dialog => {
                self.imtui.text_mode.write(24, 1, "F1=Help   Enter=Execute   Esc=Cancel   Tab=Next Field   Arrow=Next Item");
                show_ruler = false;
            },
            else => {
                var help_button = try self.imtui.button(24, 1, help_line_colour, "<Shift+F1=Help>");
                if (help_button.chosen()) {
                    // TODO do same as "&Help on Help"
                }
                var window_button = try self.imtui.button(24, 17, help_line_colour, "<F6=Window>");
                if (window_button.chosen())
                    self.windowFunction();

                _ = try self.imtui.button(24, 29, help_line_colour, "<F2=Subs>");
                if ((try self.imtui.button(24, 39, help_line_colour, "<F5=Run>")).chosen()) {
                    std.debug.print("run!\n", .{});
                }
                _ = try self.imtui.button(24, 48, help_line_colour, "<F8=Step>");

                // TODO During active execution, these change to:
                // <Shift+F1=Help> <F5=Continue> <F9=Toggle Bkpt> <F8=Step>

                // TODO: When the Immediate window is focussed (regardless of
                // active execution), these change to:
                // <Shift+F1=Help> <F6=Window> <Enter=Execute Line>
            },
        }

        var f6 = try self.imtui.shortcut(.f6, null);
        if (f6.chosen())
            self.windowFunction();

        if (show_ruler) {
            self.imtui.text_mode.draw(24, 62, 0x30, .Vertical);
            self.imtui.text_mode.paint(24, 63, 25, 80, 0x30, .Blank);
            const e = try self.imtui.focusedEditor();
            var buf: [9]u8 = undefined;
            if (builtin.mode == .Debug and self.imtui.keydown_mod.get(.left_shift))
                _ = try std.fmt.bufPrint(&buf, "{d:0>5}:{d:0>3}", .{ self.imtui.mouse_row, self.imtui.mouse_col })
            else
                _ = try std.fmt.bufPrint(&buf, "{d:0>5}:{d:0>3}", .{ e.cursor_row + 1, e.cursor_col + 1 });
            self.imtui.text_mode.write(24, 70, &buf);
        }
    }

    fn openDisplayDialog(self: *Adc) void {
        self.display_dialog_visible = true;
        self.display_dialog_colours_normal = self.prefs.settings.colours_normal;
        self.display_dialog_colours_current = self.prefs.settings.colours_current;
        self.display_dialog_colours_breakpoint = self.prefs.settings.colours_breakpoint;
        self.display_dialog_scrollbars = self.prefs.settings.scrollbars;
        self.display_dialog_tab_stops = self.prefs.settings.tab_stops;
    }

    const COLOUR_NAMES: []const []const u8 = &.{
        "Black",
        "Blue",
        "Green",
        "Cyan",
        "Red",
        "Magenta",
        "Brown",
        "White",
        "Gray",
        "BrBlue",
        "BrGreen",
        "BrCyan",
        "BrRed",
        "Pink",
        "Yellow",
        "BrWhite",
    };

    fn renderDisplayDialog(self: *Adc) !void {
        // [x] scroll bar toggle
        // [x] accelerators
        // [-] input tab stops   <- there are universal editing keys we need in
        //                          common here (e.g. ^A/^F) and in Editor.
        //                          Typematic is included, though handled for us
        //                          by Imtui.
        // [ ] mouse control
        // [ ] help sub-dialog

        // It appears the "options" menu may well actually appear to remain
        // opened (i.e. the text " Options " is inverted at the top). TODO
        // confirm and implement. TODO confirmed, do it

        var dialog = try self.imtui.dialog("Display", 22, 60);

        // XXX Colours?
        var colors = dialog.groupbox("Colors", 1, 2, 15, 58, 0x70);

        var r1 = try dialog.radio(0, 0, 3, 2, "&1.");
        self.imtui.text_mode.paint(3, 9, 4, 29, self.display_dialog_colours_normal, .Blank);
        self.imtui.text_mode.write(3, 10, "Normal Text");
        var r2 = try dialog.radio(0, 1, 5, 2, "&2.");
        self.imtui.text_mode.paint(5, 9, 6, 29, self.display_dialog_colours_current, .Blank);
        self.imtui.text_mode.write(5, 10, "Current Statement");
        var r3 = try dialog.radio(0, 2, 7, 2, "&3.");
        self.imtui.text_mode.paint(7, 9, 8, 29, self.display_dialog_colours_breakpoint, .Blank);
        self.imtui.text_mode.write(7, 10, "Breakpoint Lines");

        self.imtui.text_mode.writeAccelerated(1, 31, "&Foreground", dialog.show_acc);
        var fg = try dialog.select(2, 30, 12, 41, 0x70, self.display_dialog_colours_normal & 0x0f);
        fg.accel('f');
        fg.items(COLOUR_NAMES);
        fg.end();

        self.imtui.text_mode.writeAccelerated(1, 43, "&Background", dialog.show_acc);
        var bg = try dialog.select(2, 42, 12, 53, 0x70, (self.display_dialog_colours_normal & 0xf0) >> 4);
        bg.accel('b');
        bg.items(COLOUR_NAMES);
        bg.end();

        if (r1.selected()) {
            fg.value(self.display_dialog_colours_normal & 0x0f);
            bg.value(self.display_dialog_colours_normal >> 4);
        } else if (r1._selected) {
            self.display_dialog_colours_normal = @as(u8, @intCast(fg._selected_ix)) |
                (@as(u8, @intCast(bg._selected_ix)) << 4);
        }

        if (r2.selected()) {
            fg.value(self.display_dialog_colours_current & 0x0f);
            bg.value(self.display_dialog_colours_current >> 4);
        } else if (r2._selected) {
            self.display_dialog_colours_current = @as(u8, @intCast(fg._selected_ix)) |
                (@as(u8, @intCast(bg._selected_ix)) << 4);
        }

        if (r3.selected()) {
            fg.value(self.display_dialog_colours_breakpoint & 0x0f);
            bg.value(self.display_dialog_colours_breakpoint >> 4);
        } else if (r3._selected) {
            self.display_dialog_colours_breakpoint = @as(u8, @intCast(fg._selected_ix)) |
                (@as(u8, @intCast(bg._selected_ix)) << 4);
        }

        colors.end();

        var display_options = dialog.groupbox("Display Options", 16, 2, 19, 58, 0x70);

        var scrollbars = try dialog.checkbox(1, 4, "&Scroll Bars", self.display_dialog_scrollbars);
        if (scrollbars.changed()) |v|
            self.display_dialog_scrollbars = v;

        self.imtui.text_mode.writeAccelerated(1, 37, "&Tab Stops:", dialog.show_acc);
        var tab_stops = try dialog.input(1, 48, 52);
        tab_stops.accel('t');
        if (tab_stops.initial()) |buf|
            try buf.writer().print("{d}", .{self.display_dialog_tab_stops});

        display_options.end();

        self.imtui.text_mode.draw(19, 0, 0x70, .VerticalRight);
        self.imtui.text_mode.paint(19, 1, 19 + 1, 60 - 1, 0x70, .Horizontal);
        self.imtui.text_mode.draw(19, 60 - 1, 0x70, .VerticalLeft);

        var ok = try dialog.button(20, 10, "OK");
        ok.default();
        if (ok.chosen()) {
            self.prefs.settings.colours_normal = self.display_dialog_colours_normal;
            self.prefs.settings.colours_current = self.display_dialog_colours_current;
            self.prefs.settings.colours_breakpoint = self.display_dialog_colours_breakpoint;
            self.prefs.settings.scrollbars = self.display_dialog_scrollbars;
            try self.prefs.save();
            self.display_dialog_visible = false;
            self.imtui.focus = .editor;
        }

        var cancel = try dialog.button(20, 24, "Cancel");
        cancel.cancel();
        if (cancel.chosen()) {
            self.display_dialog_visible = false;
            self.imtui.focus = .editor;
        }

        var help = try dialog.button(20, 42, "&Help");
        if (help.chosen())
            std.log.debug("help", .{});

        dialog.end();
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
