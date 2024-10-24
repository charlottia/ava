const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Font = @import("./Font.zig");
const TextMode = @import("./TextMode.zig").TextMode;
const Editor = @import("./Editor.zig");

const Kyuubey = @This();

allocator: Allocator,
text_mode: TextMode(25, 80),
char_width: usize, // XXX: abstraction leak, should happen in IMTK
char_height: usize, // XXX: abstraction leak, should happen in IMTK

mouse_x: usize = 100,
mouse_y: usize = 100,

alt_held: bool = false,
menubar_focus: bool = false,
selected_menu: usize = 0,
menu_open: bool = false,
selected_menu_item: usize = 0,

editors: [3]Editor,
editor_active: usize,
split_active: bool,

pub fn init(allocator: Allocator, renderer: SDL.Renderer, font: *Font, filename: ?[]const u8) !*Kyuubey {
    const qb = try allocator.create(Kyuubey);
    qb.* = Kyuubey{
        .allocator = allocator,
        .text_mode = try TextMode(25, 80).init(renderer, font),
        .char_width = font.char_width,
        .char_height = font.char_height,
        .editors = .{
            try Editor.init(allocator, "Untitled", 1, 19, .primary),
            try Editor.init(allocator, "Untitled", 11, 9, .secondary),
            try Editor.init(allocator, "Immediate", 21, 2, .immediate),
        },
        .editor_active = 0,
        .split_active = false,
    };
    if (filename) |f| {
        try qb.editors[0].load(f);
        // try qb.editors[1].load(f);
    }
    qb.render();
    return qb;
}

pub fn deinit(self: *Kyuubey) void {
    for (&self.editors) |*e| e.deinit();
    self.allocator.destroy(self);
}

fn activeEditor(self: *Kyuubey) *Editor {
    return &self.editors[self.editor_active];
}

pub fn keyDown(self: *Kyuubey, sym: SDL.Keycode, mod: SDL.KeyModifierSet) !void {
    _ = mod;
    if ((sym == .left_alt or sym == .right_alt) and !self.alt_held) {
        self.alt_held = true;
        self.render();
        try self.text_mode.present();
        return;
    }

    if (sym == .@"return" and self.menubar_focus) {
        if (!self.menu_open) {
            self.menu_open = true;
            self.selected_menu_item = 0;
        }
    }
}

pub fn keyUp(self: *Kyuubey, sym: SDL.Keycode) !void {
    if ((sym == .left_alt or sym == .right_alt) and self.alt_held) {
        self.alt_held = false;

        if (self.menu_open) {
            self.menu_open = false;
        } else if (!self.menubar_focus) {
            self.text_mode.cursor_inhibit = true;
            self.menubar_focus = true;
            self.selected_menu = 0;
        } else {
            self.text_mode.cursor_inhibit = false;
            self.menubar_focus = false;
        }

        self.render();
        try self.text_mode.present();
    }
}

pub fn keyPress(self: *Kyuubey, sym: SDL.Keycode, mod: SDL.KeyModifierSet) !void {
    if (self.menubar_focus) {
        switch (sym) {
            .left => self.selected_menu = if (self.selected_menu == 0) 8 else self.selected_menu - 1,
            .right => self.selected_menu = if (self.selected_menu == 8) 0 else self.selected_menu + 1,
            .up => {
                if (!self.menu_open) {
                    self.menu_open = true;
                    self.selected_menu_item = 0;
                } else {
                    // TODO: needs to know about the menu to wrap!!
                    self.selected_menu_item -= 1;
                }
            },
            .down => {
                if (!self.menu_open) {
                    self.menu_open = true;
                    self.selected_menu_item = 0;
                } else {
                    self.selected_menu_item += 1;
                }
            },
            .escape => {
                self.text_mode.cursor_inhibit = false;
                self.menubar_focus = false;
                self.menu_open = false;
            },
            else => {},
        }

        self.render();
        try self.text_mode.present();
        return;
    }

    if (sym == .f6) {
        const prev = self.activeEditor();
        var next_index = (self.editor_active + 1) % self.editors.len;
        if (self.editors[next_index].kind == .secondary and !self.split_active)
            next_index += 1;
        const next = &self.editors[next_index];
        self.editor_active = next_index;

        if (prev.fullscreened != null) {
            prev.toggleFullscreen();
            next.toggleFullscreen();
        }
        self.render();
        try self.text_mode.present();
        return;
    }

    if (sym == .f7) {
        // XXX: this doesn't belong on F7, I just don't have menus yet.
        try self.toggleSplit();
        self.render();
        try self.text_mode.present();
        return;
    }

    var editor = self.activeEditor();

    if (sym == .down and editor.cursor_row < editor.lines.items.len) {
        editor.cursor_row += 1;
    } else if (sym == .up and editor.cursor_row > 0) {
        editor.cursor_row -= 1;
    } else if (sym == .left and editor.cursor_col > 0) {
        editor.cursor_col -= 1;
    } else if (sym == .right) {
        if (editor.cursor_col < Editor.MAX_LINE)
            editor.cursor_col += 1;
    } else if (sym == .tab) {
        var line = try editor.currentLine();
        while (line.items.len < 254) {
            try line.insert(editor.cursor_col, ' ');
            editor.cursor_col += 1;
            if (editor.cursor_col % 8 == 0)
                break;
        }
    } else if (isPrintableKey(sym) and (try editor.currentLine()).items.len < 254) {
        var line = try editor.currentLine();
        if (line.items.len < editor.cursor_col)
            try line.appendNTimes(' ', editor.cursor_col - line.items.len);
        try line.insert(editor.cursor_col, getCharacter(sym, mod));
        editor.cursor_col += 1;
    } else if (sym == .@"return") {
        try editor.splitLine();
    } else if (sym == .backspace) {
        try editor.deleteAt(.backspace);
    } else if (sym == .delete) {
        try editor.deleteAt(.delete);
    } else if (sym == .home) {
        editor.cursor_col = if (editor.maybeCurrentLine()) |line|
            Editor.lineFirst(line.items)
        else
            0;
    } else if (sym == .end) {
        editor.cursor_col = if (editor.maybeCurrentLine()) |line|
            line.items.len
        else
            0;
    } else if (sym == .page_up) {
        editor.pageUp();
    } else if (sym == .page_down) {
        editor.pageDown();
    }

    const adjust: usize = if (editor.kind == .immediate or editor.height == 1) 1 else 2;
    if (editor.cursor_row < editor.scroll_row) {
        editor.scroll_row = editor.cursor_row;
    } else if (editor.cursor_row > editor.scroll_row + editor.height - adjust) {
        editor.scroll_row = editor.cursor_row + adjust - editor.height;
    }

    if (editor.cursor_col < editor.scroll_col) {
        editor.scroll_col = editor.cursor_col;
    } else if (editor.cursor_col > editor.scroll_col + 77) {
        editor.scroll_col = editor.cursor_col - 77;
    }

    self.render();
    try self.text_mode.present();
}

pub fn mouseAt(self: *Kyuubey, mouse_x: i32, mouse_y: i32, scale: f32) bool {
    const old_mouse_x = self.mouse_x;
    const old_mouse_y = self.mouse_y;

    self.mouse_x = @intFromFloat(@as(f32, @floatFromInt(mouse_x)) / scale);
    self.mouse_y = @intFromFloat(@as(f32, @floatFromInt(mouse_y)) / scale);

    if (old_mouse_x != self.mouse_x or old_mouse_y != self.mouse_y) {
        self.text_mode.positionMouseAt(self.mouse_x, self.mouse_y);
        return true;
    }

    return false;
}

pub fn mouseDown(self: *Kyuubey, button: SDL.MouseButton, clicks: u8) !void {
    const x = self.mouse_x / self.char_width;
    const y = self.mouse_y / self.char_height;

    const active_editor = self.activeEditor();
    if (active_editor.fullscreened != null) {
        _ = active_editor.handleMouseDown(true, button, clicks, x, y);
    } else for (&self.editors, 0..) |*e, i| {
        if (!self.split_active and e.kind == .secondary)
            continue;
        if (e.handleMouseDown(self.editor_active == i, button, clicks, x, y)) {
            self.editor_active = i;
            break;
        }
    }

    self.render();
    try self.text_mode.present();
}

pub fn mouseUp(self: *Kyuubey, button: SDL.MouseButton, clicks: u8) !void {
    const x = self.mouse_x / self.char_width;
    const y = self.mouse_y / self.char_height;

    self.activeEditor().handleMouseUp(button, clicks, x, y);

    self.render();
    try self.text_mode.present();
}

pub fn mouseDrag(self: *Kyuubey, button: SDL.MouseButton, old_x_px: usize, old_y_px: usize) !void {
    const old_x = old_x_px / self.char_width;
    const old_y = old_y_px / self.char_height;

    const x = self.mouse_x / self.char_width;
    const y = self.mouse_y / self.char_height;

    if (old_x == x and old_y == y)
        return;

    const active_editor = self.activeEditor();
    if (active_editor.top != 1 and old_y == active_editor.top and y != old_y) {
        // Resizing a window. Constraints:
        // * Immediate can be at most 10 high.
        // * Any window can be as small as 0 high.
        // * Pulling a window across another one moves that one along with it.

    }

    _ = button;
}

fn toggleSplit(self: *Kyuubey) !void {
    // TODO: does QB do anything fancy with differently-sized immediates? For now
    // we just reset to the default view.
    //
    // Immediate window max height is 10.
    // Means there's always room to split with 5+5. Uneven split favours bottom.

    // QB always leaves the view in non-fullscreen, with primary editor selected.

    for (&self.editors) |*e|
        if (e.fullscreened != null)
            e.toggleFullscreen();

    self.editor_active = 0;

    if (!self.split_active) {
        std.debug.assert(self.editors[0].height >= 11);
        try self.editors[1].loadFrom(&self.editors[0]);
        self.editors[0].height = 9;
        self.editors[1].height = 9;
        self.editors[1].top = 11;
        self.split_active = true;
    } else {
        self.editors[0].height += self.editors[1].height + 1;
        self.split_active = false;
    }
}

const MENUS = .{
    .@"&File" = .{
        .width = 16,
        .items = .{
            .{ "&New Program", "Removes currently loaded program from memory" },
            .{ "&Open Program...", "Loads new program into memory" },
            .{ "&Merge...", "Inserts specified file into current module" },
            .{ "&Save", "Writes current module to file on disk" },
            .{ "Save &As...", "Saves current module with specified name and format" },
            .{ "Sa&ve All", "Writes all currently loaded modules to files on disk" },
            null,
            .{ "&Create File...", "Creates a module, include file, or document; retains loaded modules" },
            .{ "&Load File...", "Loads a module, include file, or document; retains loaded modules" },
            .{ "&Unload File...", "Removes a loaded module, include file, or document from memory" },
            null,
            .{ "&Print...", "Prints specified text or module" },
            .{ "&DOS Shell", "Temporarily suspends ADC and invokes DOS shell" }, // uhh
            null,
            .{ "E&xit", "Exits ADC and returns to DOS" }, // uhhhhh
        },
    },
    .@"&Edit" = .{ .width = 20, .items = .{
        .{ "&Undo", "Restores current edited line to its original condition", "Alt+Backspace" },
        .{ "Cu&t", "Deletes selected text and copies it to buffer", "Shift+Del" },
        .{ "&Copy", "Copies selected text to buffer", "Ctrl+Ins" },
        .{ "&Paste", "Inserts buffer contents at current location", "Shift+Ins" },
        .{ "Cl&ear", "Deletes selected text without copying it to buffer", "Del" },
        null,
        .{ "New &SUB...", "Opens a window for a new subprogram" },
        .{ "New &FUNCTION...", "Opens a window for a new FUNCTION procedure" },
    } },
    .@"&View" = .{ .width = 21, .items = .{
        .{ "&SUBs...", "Displays a loaded SUB, FUNCTION, module, include file, or document", "F2" },
        .{ "N&ext SUB", "Displays next SUB or FUNCTION procedure in the active window", "Shift+F2" },
        .{ "S&plit", "Divides screen into two View windows" },
        null,
        .{ "&Next Statement", "Displays next statement to be executed" },
        .{ "O&utput Screen", "Displays output screen", "F4" },
        null,
        .{ "&Included File", "Displays include file for editing" },
        .{ "Included &Lines", "Displays include file for viewing only (not for editing)" },
    } },
    .@"&Search" = .{ .width = 24, .items = .{
        .{ "&Find...", "Finds specified text" },
        .{ "&Selected Text", "Finds selected text", "Ctrl+\\" },
        .{ "&Repeat Last Find", "Finds next occurrence of text specified in previous search", "F3" },
        .{ "&Change...", "Finds and changes specified text" },
        .{ "&Label...", "Finds specified line label" },
    } },
    .@"&Run" = .{
        .width = 19,
        .items = .{
            .{ "&Start", "Runs current program", "Shift+F5" },
            .{ "&Restart", "Clears variables in preparation for restarting single stepping" },
            .{ "Co&ntinue", "Continues execution after a break", "F5" },
            .{ "Modify &COMMAND$...", "Sets string returned by COMMAND$ function" },
            null,
            .{ "Make E&XE File...", "Creates executable file on disk" },
            .{ "Make &Library...", "Creates Quick library and stand-alone (.LIB) library on disk" }, // XXX ?
            null,
            .{ "Set &Main Module...", "Makes the specified module the main module" },
        },
    },
    .@"&Debug" = .{ .width = 27, .items = .{} },
    .@"&Calls" = .{ .width = 10, .items = .{} }, // ???
    .@"&Options" = .{ .width = 15, .items = .{} },
    .@"&Help" = .{ .width = 25, .items = .{} },
};

pub fn render(self: *Kyuubey) void {
    self.text_mode.clear(0x17);
    self.text_mode.paint(0, 0, 1, 80, 0x70, .Blank);

    var offset: usize = 2;
    inline for (std.meta.fields(@TypeOf(MENUS)), 0..) |option, i| {
        // XXX option.name.len includes a & -- we currently rely on this!!
        if (std.mem.eql(u8, option.name, "&Help"))
            offset = 73;
        if (self.menubar_focus and self.selected_menu == i)
            self.text_mode.paint(0, offset, 1, offset + option.name.len + 1, 0x07, .Blank);
        self.text_mode.writeAccelerated(
            0,
            offset + 1,
            option.name,
            !self.menu_open and (self.alt_held or self.menubar_focus),
        );
        offset += option.name.len + 1;
    }

    const active_editor = self.activeEditor();
    if (active_editor.fullscreened != null) {
        self.renderEditor(active_editor, true);
    } else for (&self.editors, 0..) |*e, i| {
        if (!self.split_active and e.kind == .secondary)
            continue;
        self.renderEditor(e, self.editor_active == i);
    }

    // Draw open menus on top of anything else.
    var menu_help_text: ?[]const u8 = null;
    if (self.menu_open)
        menu_help_text = self.renderMenu();

    self.text_mode.paint(24, 0, 25, 80, 0x30, .Blank);

    offset = 1;
    if (menu_help_text) |t| {
        self.text_mode.write(24, offset, "F1=Help");
        offset += "F1=Help".len + 1;
        self.text_mode.draw(24, offset, 0x30, .Vertical);
        offset += 2;
        self.text_mode.write(24, offset, t);
        offset += t.len;
    } else if (self.menubar_focus) {
        inline for (&.{ "F1=Help", "Enter=Display Menu", "Esc=Cancel", "Arrow=Next Item" }) |item| {
            self.text_mode.write(24, offset, item);
            offset += item.len + 3;
        }
    } else {
        inline for (&.{ "<Shift+F1=Help>", "<F6=Window>", "<F2=Subs>", "<F5=Run>", "<F8=Step>" }) |item| {
            self.text_mode.write(24, offset, item);
            offset += item.len + 1;
        }
    }

    if (offset <= 62) {
        self.text_mode.draw(24, 62, 0x30, .Vertical);
        var buf: [9]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{d:0>5}:{d:0>3}", .{ active_editor.cursor_row + 1, active_editor.cursor_col + 1 }) catch unreachable;
        self.text_mode.write(24, 70, &buf);
    }

    self.text_mode.cursor_col = active_editor.cursor_col + 1 - active_editor.scroll_col;
    self.text_mode.cursor_row = active_editor.cursor_row + 1 - active_editor.scroll_row + active_editor.top;
}

fn renderEditor(self: *Kyuubey, editor: *Editor, active: bool) void {
    self.text_mode.draw(editor.top, 0, 0x17, if (editor.top == 1) .TopLeft else .VerticalRight);
    for (1..79) |x|
        self.text_mode.draw(editor.top, x, 0x17, .Horizontal);

    const start = 40 - editor.title.len / 2;
    const colour: u8 = if (active) 0x71 else 0x17;
    self.text_mode.paint(editor.top, start - 1, editor.top + 1, start + editor.title.len + 1, colour, 0);
    self.text_mode.write(editor.top, start, editor.title);
    self.text_mode.draw(editor.top, 79, 0x17, if (editor.top == 1) .TopRight else .VerticalLeft);

    if (editor.kind != .immediate) {
        self.text_mode.draw(editor.top, 75, 0x17, .VerticalLeft);
        self.text_mode.draw(editor.top, 76, 0x71, if (editor.fullscreened != null) .ArrowVertical else .ArrowUp);
        self.text_mode.draw(editor.top, 77, 0x17, .VerticalRight);
    }

    self.text_mode.paint(editor.top + 1, 0, editor.top + editor.height + 1, 1, 0x17, .Vertical);
    self.text_mode.paint(editor.top + 1, 79, editor.top + editor.height + 1, 80, 0x17, .Vertical);
    self.text_mode.paint(editor.top + 1, 1, editor.top + editor.height + 1, 79, 0x17, .Blank);

    for (0..@min(editor.height, editor.lines.items.len - editor.scroll_row)) |y| {
        const line = &editor.lines.items[editor.scroll_row + y];
        const upper = @min(line.items.len, 78 + editor.scroll_col);
        if (upper > editor.scroll_col)
            self.text_mode.write(y + editor.top + 1, 1, line.items[editor.scroll_col..upper]);
    }

    if (active and editor.kind != .immediate) {
        if (editor.height > 3) {
            self.text_mode.draw(editor.top + 1, 79, 0x70, .ArrowUp);
            self.text_mode.paint(editor.top + 2, 79, editor.top + editor.height, 80, 0x70, .DotsLight);
            self.text_mode.draw(editor.top + 2 + editor.verticalScrollThumb(), 79, 0x00, .Blank);
            self.text_mode.draw(editor.top + editor.height - 1, 79, 0x70, .ArrowDown);
        }

        if (editor.height > 1) {
            self.text_mode.draw(editor.top + editor.height, 1, 0x70, .ArrowLeft);
            self.text_mode.paint(editor.top + editor.height, 2, editor.top + editor.height + 1, 78, 0x70, .DotsLight);
            self.text_mode.draw(editor.top + editor.height, 2 + editor.horizontalScrollThumb(), 0x00, .Blank);
            self.text_mode.draw(editor.top + editor.height, 78, 0x70, .ArrowRight);
        }
    }
}

fn renderMenu(self: *Kyuubey) ?[]const u8 {
    var menu_help_text: ?[]const u8 = null;

    // Note duplication with menubar drawing.
    var offset: usize = 1;
    inline for (std.meta.fields(@TypeOf(MENUS)), 0..) |option, i| {
        if (std.mem.eql(u8, option.name, "&Help"))
            offset = 49;

        if (i == self.selected_menu) {
            const menu = @field(MENUS, option.name);
            self.text_mode.draw(1, offset, 0x70, .TopLeft);
            self.text_mode.paint(1, offset + 1, 2, offset + 1 + menu.width + 2, 0x70, .Horizontal);
            self.text_mode.draw(1, offset + menu.width + 3, 0x70, .TopRight);

            var row: usize = 2;
            var option_number: usize = 0;
            inline for (menu.items) |o| {
                if (@typeInfo(@TypeOf(o)) == .Null) {
                    self.text_mode.draw(row, offset, 0x70, .VerticalRight);
                    self.text_mode.paint(row, offset + 1, row + 1, offset + 1 + menu.width + 2, 0x70, .Horizontal);
                    self.text_mode.draw(row, offset + menu.width + 3, 0x70, .VerticalLeft);
                } else {
                    self.text_mode.draw(row, offset, 0x70, .Vertical);
                    const disabled = std.mem.eql(u8, "&Undo", o.@"0") or std.mem.eql(u8, "Cu&t", o.@"0") or std.mem.eql(u8, "&Copy", o.@"0") or std.mem.eql(u8, "Cl&ear", o.@"0");
                    const colour: u8 = if (self.selected_menu_item == option_number)
                        0x07
                    else if (disabled)
                        0x78
                    else
                        0x70;
                    self.text_mode.paint(row, offset + 1, row + 1, offset + 1 + menu.width + 2, colour, .Blank);

                    self.text_mode.writeAccelerated(row, offset + 2, o.@"0", !disabled);
                    if (self.selected_menu_item == option_number)
                        menu_help_text = o.@"1";

                    if (o.len == 3) {
                        // Shortcut key.
                        const sk = o.@"2";
                        self.text_mode.write(row, offset + menu.width + 2 - sk.len, sk);
                    }
                    self.text_mode.draw(row, offset + menu.width + 3, 0x70, .Vertical);
                    option_number += 1;
                }
                self.text_mode.shadow(row, offset + menu.width + 4);
                self.text_mode.shadow(row, offset + menu.width + 5);
                row += 1;
            }
            self.text_mode.draw(row, offset, 0x70, .BottomLeft);
            self.text_mode.paint(row, offset + 1, row + 1, offset + 1 + menu.width + 2, 0x70, .Horizontal);
            self.text_mode.draw(row, offset + menu.width + 3, 0x70, .BottomRight);
            self.text_mode.shadow(row, offset + menu.width + 4);
            self.text_mode.shadow(row, offset + menu.width + 5);
            row += 1;
            for (2..menu.width + 6) |j|
                self.text_mode.shadow(row, offset + j);
        }
        offset += option.name.len + 1;
    }

    return menu_help_text;
}

fn isPrintableKey(sym: SDL.Keycode) bool {
    return @intFromEnum(sym) >= @intFromEnum(SDL.Keycode.space) and
        @intFromEnum(sym) <= @intFromEnum(SDL.Keycode.z);
}

fn getCharacter(sym: SDL.Keycode, mod: SDL.KeyModifierSet) u8 {
    if (@intFromEnum(sym) >= @intFromEnum(SDL.Keycode.a) and
        @intFromEnum(sym) <= @intFromEnum(SDL.Keycode.z))
    {
        if (mod.get(.left_shift) or mod.get(.right_shift) or mod.get(.caps_lock)) {
            return @as(u8, @intCast(@intFromEnum(sym))) - ('a' - 'A');
        }
        return @intCast(@intFromEnum(sym));
    }

    if (mod.get(.left_shift) or mod.get(.right_shift)) {
        for (ShiftTable) |e| {
            if (e.@"0" == sym)
                return e.@"1";
        }
    }

    return @intCast(@intFromEnum(sym));
}

const ShiftTable = [_]struct { SDL.Keycode, u8 }{
    .{ .apostrophe, '"' },
    .{ .comma, '<' },
    .{ .minus, '_' },
    .{ .period, '>' },
    .{ .slash, '?' },
    .{ .@"0", ')' },
    .{ .@"1", '!' },
    .{ .@"2", '@' },
    .{ .@"3", '#' },
    .{ .@"4", '$' },
    .{ .@"5", '%' },
    .{ .@"6", '^' },
    .{ .@"7", '&' },
    .{ .@"8", '*' },
    .{ .@"9", '(' },
    .{ .semicolon, ':' },
    .{ .left_bracket, '{' },
    .{ .backslash, '|' },
    .{ .right_bracket, '}' },
    .{ .grave, '~' },
    .{ .equals, '+' },
};
