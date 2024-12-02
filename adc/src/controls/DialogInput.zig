const std = @import("std");
const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const Editor = @import("./Editor.zig");

const DialogInput = @This();

dialog: *Dialog,
generation: usize,
ix: usize = undefined,
r: usize = undefined,
c1: usize = undefined,
c2: usize = undefined,
_accel: ?u8 = undefined,

value: std.ArrayList(u8),
initted: bool = false,
_changed: bool = false,

cursor_col: usize = 0,
scroll_col: usize = 0,

pub fn create(dialog: *Dialog, ix: usize, r: usize, c1: usize, c2: usize) !*DialogInput {
    var b = try dialog.imtui.allocator.create(DialogInput);
    b.* = .{
        .dialog = dialog,
        .generation = dialog.imtui.generation,
        .value = std.ArrayList(u8).init(dialog.imtui.allocator),
    };
    b.describe(ix, r, c1, c2);
    return b;
}

pub fn deinit(self: *DialogInput) void {
    self.value.deinit();
    self.dialog.imtui.allocator.destroy(self);
}

pub fn describe(self: *DialogInput, ix: usize, r: usize, c1: usize, c2: usize) void {
    self.ix = ix;
    self.r = r;
    self.c1 = c1;
    self.c2 = c2;
    self._accel = null;

    if (self.cursor_col < self.scroll_col)
        self.scroll_col = self.cursor_col
    else if (self.cursor_col > self.scroll_col + (c2 - c1 - 1))
        self.scroll_col = self.cursor_col - (c2 - c1 - 1);

    const clipped = if (self.scroll_col < self.value.items.len) self.value.items[self.scroll_col..] else "";
    self.dialog.imtui.text_mode.write(r, c1, clipped[0..@min(self.c2 - self.c1, clipped.len)]);

    if (self.dialog.focus_ix == self.dialog.controls_at) {
        self.dialog.imtui.text_mode.cursor_row = self.dialog.imtui.text_mode.offset_row + r;
        self.dialog.imtui.text_mode.cursor_col = self.dialog.imtui.text_mode.offset_col + c1 + self.cursor_col - self.scroll_col;
    }
}

pub fn accel(self: *DialogInput, key: u8) void {
    self._accel = key;
}

pub fn initial(self: *DialogInput) ?*std.ArrayList(u8) {
    if (self.initted) return null;
    self.initted = true;
    return &self.value;
}

pub fn focus(self: *DialogInput) void {
    self.dialog.focus_ix = self.ix;
}

pub fn changed(self: *DialogInput) ?[]const u8 {
    defer self._changed = false;
    return if (self._changed) self.value.items else null;
}

pub fn handleKeyPress(self: *DialogInput, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    // XXX is this all dialog inputs, or just Display's Tab Stops?
    const MAX_LINE = 207;

    // TODO: shift for select, ctrl-(everything), etc. -- harmonise with Editor
    switch (keycode) {
        .left => self.cursor_col -|= 1,
        .right => if (self.cursor_col < MAX_LINE) {
            self.cursor_col += 1;
        },
        .home => self.cursor_col = 0,
        .end => self.cursor_col = self.value.items.len,
        .backspace => try self.deleteAt(.backspace),
        .delete => try self.deleteAt(.delete),
        else => if (Editor.isPrintableKey(keycode) and self.value.items.len < MAX_LINE) {
            try self.value.insert(self.cursor_col, Editor.getCharacter(keycode, modifiers));
            self.cursor_col += 1;
            self._changed = true;
        },
    }
}

fn deleteAt(self: *DialogInput, mode: enum { backspace, delete }) !void {
    if (mode == .backspace and self.cursor_col == 0) {
        // can't backspace at 0
    } else if (mode == .backspace) {
        // self.cursor_col > 0
        if (self.cursor_col - 1 < self.value.items.len) {
            _ = self.value.orderedRemove(self.cursor_col - 1);
            self._changed = true;
        }
        self.cursor_col -= 1;
    } else if (self.cursor_col >= self.value.items.len) {
        // mode == .delete
        // can't delete at/past EOL
    } else {
        // model == .delete, self.cursor_col < self.value.items.len
        _ = self.value.orderedRemove(self.cursor_col);
        self._changed = true;
    }
}
