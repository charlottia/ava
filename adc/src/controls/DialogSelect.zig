const std = @import("std");
const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");

const DialogSelect = @This();

dialog: *Dialog,
ix: usize = undefined,
generation: usize,
r1: usize = undefined,
c1: usize = undefined,
r2: usize = undefined,
c2: usize = undefined,
colour: u8 = undefined,
_items: []const []const u8 = undefined,
_accel: ?u8 = undefined,
_selected_ix: usize,
_scroll_row: usize = 0,

pub fn create(dialog: *Dialog, ix: usize, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !*DialogSelect {
    var b = try dialog.imtui.allocator.create(DialogSelect);
    b.* = .{
        .dialog = dialog,
        .generation = dialog.imtui.generation,
        ._selected_ix = selected,
    };
    b.describe(ix, r1, c1, r2, c2, colour);
    return b;
}

pub fn deinit(self: *DialogSelect) void {
    self.dialog.imtui.allocator.destroy(self);
}

pub fn describe(self: *DialogSelect, ix: usize, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8) void {
    self.ix = ix;
    self.r1 = r1;
    self.c1 = c1;
    self.r2 = r2;
    self.c2 = c2;
    self.colour = colour;
    self._items = &.{};
    self._accel = null;

    self.dialog.imtui.text_mode.box(r1, c1, r2, c2, colour);

    if (self.dialog.focus_ix == ix) {
        self.dialog.imtui.text_mode.cursor_row = self.dialog.imtui.text_mode.offset_row + r1 + 1 + self._selected_ix - self._scroll_row;
        self.dialog.imtui.text_mode.cursor_col = self.dialog.imtui.text_mode.offset_col + c1 + 2;
    }
}

pub fn accel(self: *DialogSelect, key: u8) void {
    self._accel = key;
}

pub fn items(self: *DialogSelect, it: []const []const u8) void {
    self._items = it;
}

pub fn end(self: *DialogSelect) void {
    for (self._items[self._scroll_row..], 0..) |it, ix| {
        const r = self.r1 + 1 + ix;
        if (r == self.r2 - 1) break;
        if (ix + self._scroll_row == self._selected_ix)
            self.dialog.imtui.text_mode.paint(r, self.c1 + 1, r + 1, self.c2 - 1, ((self.colour & 0x0f) << 4) | ((self.colour & 0xf0) >> 4), .Blank);
        self.dialog.imtui.text_mode.write(r, self.c1 + 2, it);
    }
    _ = self.dialog.imtui.text_mode.vscrollbar(self.c2 - 1, self.r1 + 1, self.r2 - 1, self._scroll_row, self._items.len -| 8);
}

pub fn focus(self: *DialogSelect) void {
    self.dialog.focus_ix = self.ix;
}

pub fn value(self: *DialogSelect, ix: usize) void {
    self._selected_ix = ix;
    if (self._scroll_row > ix)
        self._scroll_row = ix
    else if (ix >= self._scroll_row + self.r2 - self.r1 - 2)
        self._scroll_row = ix + self.r1 + 3 - self.r2;
}

pub fn up(self: *DialogSelect) void {
    self.value(self._selected_ix -| 1);
}

pub fn down(self: *DialogSelect) void {
    self.value(@min(self._items.len - 1, self._selected_ix + 1));
}

pub fn handleKeyPress(self: *DialogSelect, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    _ = modifiers;

    if (@intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.a) and
        @intFromEnum(keycode) <= @intFromEnum(SDL.Keycode.z))
    {
        // advance to next item starting with pressed key (if any)
        var next = (self._selected_ix + 1) % self._items.len;
        while (next != self._selected_ix) : (next = (next + 1) % self._items.len) {
            // SDLK_a..SDLK_z correspond to 'a'..'z' in ASCII.
            if (std.ascii.toLower(self._items[next][0]) == @intFromEnum(keycode)) {
                self.value(next);
                return;
            }
        }
        return;
    }
}
