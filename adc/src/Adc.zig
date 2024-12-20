const std = @import("std");
const builtin = @import("builtin");

const Imtui = @import("./Imtui.zig");
const Preferences = @import("./Preferences.zig").Preferences;

pub const Prefs = Preferences(struct {
    full_menus: bool = false,
    colours_normal: u8 = 0x17,
    colours_current: u8 = 0x1f,
    colours_breakpoint: u8 = 0x47,
    scroll_bars: bool = true,
    tab_stops: u8 = 8,
});

const Adc = @This();

imtui: *Imtui,
prefs: Prefs,

sources: std.ArrayListUnmanaged(*Imtui.Controls.Source),

// primary + secondary don't do their own acquire; sources holds all the
// lifetimes.
primary_source: *Imtui.Controls.Source,
secondary_source: *Imtui.Controls.Source,

// immediate belongs to Adc.
immediate_source: *Imtui.Controls.Source,

primary_editor: ?*Imtui.Controls.Editor.Impl = null,
secondary_editor: ?*Imtui.Controls.Editor.Impl = null,
immediate_editor: ?*Imtui.Controls.Editor.Impl = null,

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
display_dialog_scroll_bars: bool = undefined,
display_dialog_tab_stops: u8 = undefined,
display_dialog_help_dialog_visible: bool = undefined,

pub fn init(imtui: *Imtui, prefs: Prefs, primary_source: *Imtui.Controls.Source) !Adc {
    errdefer primary_source.release();

    var sources = std.ArrayListUnmanaged(*Imtui.Controls.Source){};
    errdefer sources.deinit(imtui.allocator);
    try sources.append(imtui.allocator, primary_source);

    var immediate_source = try Imtui.Controls.Source.createImmediate(imtui.allocator);
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

pub fn deinit(self: *Adc) void {
    for (self.sources.items) |s|
        s.release();
    self.sources.deinit(self.imtui.allocator);
    self.immediate_source.release();
}

pub fn render(self: *Adc) !void {
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
    const primary_editor_height: usize = if (self.fullscreen)
        if (self.imtui.focusedEditor().id == 0)
            23
        else
            0
    else switch (self.view) {
        inline .two, .three => |a| a[0],
    };
    const secondary_editor_height: usize = if (self.fullscreen)
        if (self.imtui.focusedEditor().id == 1)
            23
        else
            0
    else switch (self.view) {
        .two => |_| 0,
        .three => |a| a[1],
    };
    const immediate_editor_height: usize = if (self.fullscreen)
        if (self.imtui.focusedEditor().id == 2)
            23
        else
            0
    else switch (self.view) {
        .two => |a| a[1],
        .three => |a| a[2],
    };

    const primary_editor_top = 1;
    const primary_editor_bottom = primary_editor_top + primary_editor_height;

    const secondary_editor_top = primary_editor_bottom;
    const secondary_editor_bottom = secondary_editor_top + secondary_editor_height;

    const immediate_editor_top = secondary_editor_bottom;
    const immediate_editor_bottom = immediate_editor_top + immediate_editor_height;
    std.debug.assert(immediate_editor_bottom == 24);

    var primary_editor = try self.imtui.editor(0, primary_editor_top, 0, primary_editor_bottom, 80);
    self.primary_editor = primary_editor.impl;
    if (self.imtui.focus_stack.items.len == 0)
        try self.imtui.focus_stack.append(self.imtui.allocator, .{ .editor = primary_editor.impl });
    const focused_editor = self.imtui.focusedEditor();
    primary_editor.colours(
        self.prefs.settings.colours_normal,
        self.prefs.settings.colours_current,
        self.prefs.settings.colours_breakpoint,
    );
    primary_editor.scroll_bars(self.prefs.settings.scroll_bars);
    primary_editor.tab_stops(self.prefs.settings.tab_stops);
    primary_editor.source(self.primary_source);
    if (self.fullscreen and focused_editor.id != 0)
        primary_editor.hidden();
    primary_editor.end();

    var secondary_editor = try self.imtui.editor(1, secondary_editor_top, 0, secondary_editor_bottom, 80);
    self.secondary_editor = secondary_editor.impl;
    secondary_editor.colours(
        self.prefs.settings.colours_normal,
        self.prefs.settings.colours_current,
        self.prefs.settings.colours_breakpoint,
    );
    secondary_editor.scroll_bars(self.prefs.settings.scroll_bars);
    secondary_editor.tab_stops(self.prefs.settings.tab_stops);
    secondary_editor.source(self.secondary_source);
    if (self.view == .two or (self.fullscreen and focused_editor.id != 1))
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

    var immediate_editor = try self.imtui.editor(2, immediate_editor_top, 0, immediate_editor_bottom, 80);
    self.immediate_editor = immediate_editor.impl;
    immediate_editor.colours(
        self.prefs.settings.colours_normal,
        self.prefs.settings.colours_current,
        self.prefs.settings.colours_breakpoint,
    );
    immediate_editor.tab_stops(self.prefs.settings.tab_stops);
    if (self.fullscreen and focused_editor.id != 2)
        immediate_editor.hidden()
    else if (!self.fullscreen)
        if (immediate_editor.headerDraggedTo()) |row| if (row >= 13 and row <= 23) {
            const new_immediate_h = 24 - row;
            switch (self.view) {
                .two => |_| self.view = .{ .two = [2]usize{ 23 - new_immediate_h, new_immediate_h } },
                .three => |*a| {
                    if (new_immediate_h < a[2]) {
                        for (0..a[2] - new_immediate_h) |_|
                            immDown(a);
                    } else if (new_immediate_h > a[2]) {
                        for (0..new_immediate_h - a[2]) |_|
                            immUp(a);
                    }
                },
            }
        };
    immediate_editor.immediate();
    immediate_editor.source(self.immediate_source);
    immediate_editor.end();

    if (primary_editor.toggledFullscreen() or secondary_editor.toggledFullscreen() or immediate_editor.toggledFullscreen())
        self.fullscreen = !self.fullscreen;
}

fn renderMenus(self: *Adc) !Imtui.Controls.Menubar {
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
    file_menu.end();

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
    edit_menu.end();

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
    view_menu.end();

    var search_menu = try menubar.menu("&Search", 24);
    _ = (try search_menu.item("&Find...")).help("Finds specified text");
    if (self.full_menus) {
        _ = (try search_menu.item("&Selected Text")).shortcut(.backslash, .ctrl).help("Finds selected text");
        _ = (try search_menu.item("&Repeat Last Find")).shortcut(.f3, null).help("Finds next occurrence of text specified in previous search");
    }
    _ = (try search_menu.item("&Change...")).help("Finds and changes specified text");
    if (self.full_menus)
        _ = (try search_menu.item("&Label...")).help("Finds specified line label");
    search_menu.end();

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
    run_menu.end();

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
    debug_menu.end();

    if (self.full_menus) {
        var calls_menu = try menubar.menu("&Calls", 10);
        _ = (try calls_menu.item("&Untitled")).help("Displays next statement to be executed in module or procedure");
        calls_menu.end();
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
    options_menu.end();

    var help_menu = try menubar.menu("&Help", 25);
    _ = (try help_menu.item("&Index")).help("Displays help index");
    _ = (try help_menu.item("&Contents")).help("Displays help table of contents");
    _ = (try help_menu.item("&Topic: XXX")).shortcut(.f1, null).help("Displays information about the BASIC keyword the cursor is on");
    _ = (try help_menu.item("&Help on Help")).shortcut(.f1, .shift).help("Displays help on help");
    help_menu.end();

    menubar.end();

    return menubar;
}

fn renderHelpLine(self: *Adc, menubar: Imtui.Controls.Menubar) !void {
    const help_line_colour: u8 = if (self.full_menus) 0x30 else 0x3f;
    self.imtui.text_mode.paint(24, 0, 25, 80, help_line_colour, .Blank);

    var show_ruler = true;
    var handled = false;
    if (self.imtui.focus_stack.getLastOrNull()) |c| switch (c) {
        .menubar => |mb| {
            if (mb.focus != null and mb.focus.? == .menu) {
                const help_text = menubar.itemAt(mb.focus.?.menu).help.?;
                self.imtui.text_mode.write(24, 1, "F1=Help");
                self.imtui.text_mode.draw(24, 9, help_line_colour, .Vertical);
                self.imtui.text_mode.write(24, 11, help_text);
                show_ruler = (11 + help_text.len) <= 62;
                handled = true;
            } else if (mb.focus != null and mb.focus.? == .menubar) {
                self.imtui.text_mode.write(24, 1, "F1=Help   Enter=Display Menu   Esc=Cancel   Arrow=Next Item");
                handled = true;
            }
        },
        .dialog => {
            self.imtui.text_mode.write(24, 1, "F1=Help   Enter=Execute   Esc=Cancel   Tab=Next Field   Arrow=Next Item");
            show_ruler = false;
            handled = true;
        },
        else => {},
    };

    if (!handled) {
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

        // TODO: When the Immediate window is focused (regardless of
        // active execution), these change to:
        // <Shift+F1=Help> <F6=Window> <Enter=Execute Line>
    }

    var f6 = try self.imtui.shortcut(.f6, null);
    if (f6.chosen())
        self.windowFunction();

    if (show_ruler) {
        self.imtui.text_mode.draw(24, 62, 0x30, .Vertical);
        self.imtui.text_mode.paint(24, 63, 25, 80, 0x30, .Blank);
        const e = self.imtui.focusedEditor();
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
    self.display_dialog_scroll_bars = self.prefs.settings.scroll_bars;
    self.display_dialog_tab_stops = self.prefs.settings.tab_stops;
    self.display_dialog_help_dialog_visible = false;
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
    // [x] input tab stops   <- there are universal editing keys we need in
    //                          common here (e.g. ^A/^F) and in Editor.
    //                          Typematic is included, though handled for us
    //                          by Imtui.
    // [-] mouse control
    //     [ ] should be able to drag "between" the {checkbox,radio,button}
    //         class of items
    //     [x] select
    //     [-] input
    // [-] help sub-dialog
    // [-] whole-of-Imtui refactor to capture more commonality; ideally we
    //     wouldn't have Imtui having to dispatch to Editor, which sometimes
    //     does its scrollbar stuff; and then Imtui dispatching to Dialog,
    //     which dispatches to its controls, with all this repeated code.

    // It appears the "options" menu may well actually appear to remain
    // opened (i.e. the text " Options " is inverted at the top). TODO
    // confirm and implement. TODO confirmed, do it

    var dialog = try self.imtui.dialog("Display", 22, 60);

    dialog.groupbox("Colors", 1, 2, 15, 58, 0x70);

    var r1 = try dialog.radio(0, 0, 4, 4, "&1. ");
    self.imtui.text_mode.paint(dialog.impl.r1 + 4, dialog.impl.c1 + 11, dialog.impl.r1 + 5, dialog.impl.c1 + 30, self.display_dialog_colours_normal, .Blank);
    self.imtui.text_mode.write(dialog.impl.r1 + 4, dialog.impl.c1 + 12, "Normal Text");
    var r2 = try dialog.radio(0, 1, 6, 4, "&2. ");
    self.imtui.text_mode.paint(dialog.impl.r1 + 6, dialog.impl.c1 + 11, dialog.impl.r1 + 7, dialog.impl.c1 + 30, self.display_dialog_colours_current, .Blank);
    self.imtui.text_mode.write(dialog.impl.r1 + 6, dialog.impl.c1 + 12, "Current Statement");
    var r3 = try dialog.radio(0, 2, 8, 4, "&3. ");
    self.imtui.text_mode.paint(dialog.impl.r1 + 8, dialog.impl.c1 + 11, dialog.impl.r1 + 9, dialog.impl.c1 + 30, self.display_dialog_colours_breakpoint, .Blank);
    self.imtui.text_mode.write(dialog.impl.r1 + 8, dialog.impl.c1 + 12, "Breakpoint Lines");

    self.imtui.text_mode.writeAccelerated(dialog.impl.r1 + 2, dialog.impl.c1 + 32, "&Foreground", dialog.impl.show_acc);
    var fg = try dialog.select(3, 31, 13, 42, 0x70, self.display_dialog_colours_normal & 0x0f);
    fg.accel('f');
    fg.items(COLOUR_NAMES);
    fg.end();

    self.imtui.text_mode.writeAccelerated(dialog.impl.r1 + 2, dialog.impl.c1 + 45, "&Background", dialog.impl.show_acc);
    var bg = try dialog.select(3, 44, 13, 55, 0x70, (self.display_dialog_colours_normal & 0xf0) >> 4);
    bg.accel('b');
    bg.items(COLOUR_NAMES);
    bg.end();

    if (r1.selected()) {
        fg.impl.value(self.display_dialog_colours_normal & 0x0f);
        bg.impl.value(self.display_dialog_colours_normal >> 4);
    } else if (r1.impl.selected) {
        self.display_dialog_colours_normal = @as(u8, @intCast(fg.impl.selected_ix)) |
            (@as(u8, @intCast(bg.impl.selected_ix)) << 4);
    }

    if (r2.selected()) {
        fg.impl.value(self.display_dialog_colours_current & 0x0f);
        bg.impl.value(self.display_dialog_colours_current >> 4);
    } else if (r2.impl.selected) {
        self.display_dialog_colours_current = @as(u8, @intCast(fg.impl.selected_ix)) |
            (@as(u8, @intCast(bg.impl.selected_ix)) << 4);
    }

    if (r3.selected()) {
        fg.impl.value(self.display_dialog_colours_breakpoint & 0x0f);
        bg.impl.value(self.display_dialog_colours_breakpoint >> 4);
    } else if (r3.impl.selected) {
        self.display_dialog_colours_breakpoint = @as(u8, @intCast(fg.impl.selected_ix)) |
            (@as(u8, @intCast(bg.impl.selected_ix)) << 4);
    }

    dialog.groupbox("Display Options", 16, 2, 19, 58, 0x70);

    var scroll_bars = try dialog.checkbox(17, 6, "&Scroll Bars", self.display_dialog_scroll_bars);
    if (scroll_bars.changed()) |v|
        self.display_dialog_scroll_bars = v;

    self.imtui.text_mode.writeAccelerated(dialog.impl.r1 + 17, dialog.impl.c1 + 39, "&Tab Stops:", dialog.impl.show_acc);
    var tab_stops = try dialog.input(17, 50, 54);
    tab_stops.accel('t');
    if (tab_stops.initial()) |buf| {
        try buf.writer(self.imtui.allocator).print("{d}", .{self.display_dialog_tab_stops});
        // TODO: the value should start selected
        tab_stops.impl.cursor_col = buf.items.len; // XXX
    }
    if (tab_stops.changed()) |v| {
        if (std.fmt.parseInt(u8, v, 10)) |n| {
            if (n > 0 and n < 100)
                self.display_dialog_tab_stops = n;
        } else |_| {}
    }

    self.imtui.text_mode.draw(dialog.impl.r1 + 19, dialog.impl.c1, 0x70, .VerticalRight);
    self.imtui.text_mode.paint(dialog.impl.r1 + 19, dialog.impl.c1 + 1, dialog.impl.r1 + 19 + 1, dialog.impl.c1 + 60 - 1, 0x70, .Horizontal);
    self.imtui.text_mode.draw(dialog.impl.r1 + 19, dialog.impl.c1 + 60 - 1, 0x70, .VerticalLeft);

    var ok = try dialog.button(20, 10, "OK");
    ok.default();
    if (ok.chosen()) {
        self.prefs.settings.colours_normal = self.display_dialog_colours_normal;
        self.prefs.settings.colours_current = self.display_dialog_colours_current;
        self.prefs.settings.colours_breakpoint = self.display_dialog_colours_breakpoint;
        self.prefs.settings.scroll_bars = self.display_dialog_scroll_bars;
        self.prefs.settings.tab_stops = self.display_dialog_tab_stops;
        try self.prefs.save();
        self.display_dialog_visible = false;
        self.imtui.unfocus(dialog.impl);
    }

    var cancel = try dialog.button(20, 24, "Cancel");
    cancel.cancel();
    if (cancel.chosen()) {
        self.display_dialog_visible = false;
        self.imtui.unfocus(dialog.impl);
    }

    var help = try dialog.button(20, 42, "&Help");
    if (help.chosen()) {
        std.log.debug("help chosen", .{});
        self.display_dialog_help_dialog_visible = true;
    }

    try dialog.end();

    if (self.display_dialog_help_dialog_visible) {
        var help_dialog = try self.imtui.dialog("HELP: Display Dialog", 21, 70);
        self.imtui.text_mode.draw(help_dialog.impl.r1 + 18, help_dialog.impl.c1, 0x70, .VerticalRight);
        self.imtui.text_mode.paint(help_dialog.impl.r1 + 18, help_dialog.impl.c1 + 1, help_dialog.impl.r1 + 18 + 1, help_dialog.impl.c1 + 70 - 1, 0x70, .Horizontal);
        self.imtui.text_mode.draw(help_dialog.impl.r1 + 18, help_dialog.impl.c1 + 70 - 1, 0x70, .VerticalLeft);
        var help_dialog_ok = try help_dialog.button(19, 31, "OK");
        help_dialog_ok.default();
        help_dialog_ok.cancel();
        if (help_dialog_ok.chosen()) {
            std.log.debug("help OK chosen", .{});
            self.display_dialog_help_dialog_visible = false;
            self.imtui.unfocus(help_dialog.impl);
        }
        try help_dialog.end();
    }
}

fn windowFunction(self: *Adc) void {
    if (self.view == .two) {
        self.imtui.focusEditor(if (self.imtui.focusedEditor().id == 0) self.immediate_editor.? else self.primary_editor.?);
    } else if (self.imtui.focusedEditor().id == 0) {
        self.imtui.focusEditor(self.secondary_editor.?);
    } else if (self.imtui.focusedEditor().id == 1) {
        self.imtui.focusEditor(self.immediate_editor.?);
    } else if (self.imtui.focusedEditor().id == 2) {
        self.imtui.focusEditor(self.primary_editor.?);
    }
}

fn toggleSplit(self: *Adc) void {
    self.fullscreen = false;
    self.imtui.focusEditor(self.primary_editor.?);

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
