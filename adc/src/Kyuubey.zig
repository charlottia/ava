const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Font = @import("./Font.zig");
const TextMode = @import("./TextMode.zig").TextMode;
const Editor = @import("./Editor.zig");

const Kyuubey = @This();

allocator: Allocator,
text_mode: TextMode(25, 80),
char_width: usize, // XXX: abstraction leak, should happen in IMTUI
char_height: usize, // XXX: abstraction leak, should happen in IMTUI

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

fn activeEditor(self: *Kyuubey) *Editor {
    return &self.editors[self.editor_active];
}

pub fn keyPress(self: *Kyuubey, sym: SDL.Keycode, mod: SDL.KeyModifierSet) !void {
    // if (self.menubar_focus) {
    //     switch (sym) {
    //         .left => self.selected_menu = if (self.selected_menu == 0) 8 else self.selected_menu - 1,
    //         .right => self.selected_menu = if (self.selected_menu == 8) 0 else self.selected_menu + 1,
    //         .up => {
    //             if (!self.menu_open) {
    //                 self.menu_open = true;
    //                 self.selected_menu_item = 0;
    //             } else {
    //                 // TODO: needs to know about the menu to wrap!!
    //                 self.selected_menu_item -= 1;
    //             }
    //         },
    //         .down => {
    //             if (!self.menu_open) {
    //                 self.menu_open = true;
    //                 self.selected_menu_item = 0;
    //             } else {
    //                 self.selected_menu_item += 1;
    //             }
    //         },
    //         .escape => {
    //             self.text_mode.cursor_inhibit = false;
    //             self.menubar_focus = false;
    //             self.menu_open = false;
    //         },
    //         else => {},
    //     }

    //     self.render();
    //     try self.text_mode.present();
    //     return;
    // }

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

    // QB split always leaves the view in non-fullscreen, with primary editor selected.

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
