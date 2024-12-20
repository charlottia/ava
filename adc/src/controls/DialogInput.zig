const std = @import("std");
const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const Editor = @import("./Editor.zig");
const Imtui = @import("../Imtui.zig");

const DialogInput = @This();

pub const Impl = struct {
    imtui: *Imtui,
    dialog: *Dialog.Impl,
    generation: usize,

    // id
    ix: usize,

    // config
    r: usize = undefined,
    c1: usize = undefined,
    c2: usize = undefined,
    accel: ?u8 = undefined,

    value: std.ArrayListUnmanaged(u8) = .{},

    // state
    initted: bool = false,
    changed: bool = false,

    cursor_col: usize = 0,
    scroll_col: usize = 0,

    pub fn deinit(self: *Impl) void {
        self.value.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn parent(self: *const Impl) Imtui.Control {
        return .{ .dialog = self.dialog };
    }

    pub fn describe(self: *Impl, r: usize, c1: usize, c2: usize) void {
        self.r = self.dialog.r1 + r;
        self.c1 = self.dialog.c1 + c1;
        self.c2 = self.dialog.c1 + c2;
        self.accel = null;

        if (self.cursor_col < self.scroll_col)
            self.scroll_col = self.cursor_col
        else if (self.cursor_col > self.scroll_col + (c2 - c1 - 1))
            self.scroll_col = self.cursor_col - (c2 - c1 - 1);

        const clipped = if (self.scroll_col < self.value.items.len) self.value.items[self.scroll_col..] else "";
        self.dialog.imtui.text_mode.write(self.r, self.c1, clipped[0..@min(self.c2 - self.c1, clipped.len)]);

        if (self.imtui.focused(self)) {
            self.dialog.imtui.text_mode.cursor_row = self.r;
            self.dialog.imtui.text_mode.cursor_col = self.c1 + self.cursor_col - self.scroll_col;
        }
    }

    pub fn accelerate(self: *Impl) !void {
        try self.imtui.focus(self);
    }

    pub fn handleKeyPress(self: *Impl, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        // XXX is this all dialog inputs, or just Display's Tab Stops?
        // Note this is the default MAX_LINE for full-screen editors, less Tab
        // Stops' exact c1 (255 - 48 = 207). Hah.
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
            else => if (!self.imtui.alt_held and Editor.isPrintableKey(keycode) and self.value.items.len < MAX_LINE) {
                if (self.value.items.len < self.cursor_col)
                    try self.value.appendNTimes(self.imtui.allocator, ' ', self.cursor_col - self.value.items.len);
                try self.value.insert(self.imtui.allocator, self.cursor_col, Editor.getCharacter(keycode, modifiers));
                self.cursor_col += 1;
                self.changed = true;
            } else try self.dialog.commonKeyPress(self.ix, keycode, modifiers),
        }
    }

    fn deleteAt(self: *Impl, mode: enum { backspace, delete }) !void {
        if (mode == .backspace and self.cursor_col == 0) {
            // can't backspace at 0
        } else if (mode == .backspace) {
            // self.cursor_col > 0
            if (self.cursor_col - 1 < self.value.items.len) {
                _ = self.value.orderedRemove(self.cursor_col - 1);
                self.changed = true;
            }
            self.cursor_col -= 1;
        } else if (self.cursor_col >= self.value.items.len) {
            // mode == .delete
            // can't delete at/past EOL
        } else {
            // model == .delete, self.cursor_col < self.value.items.len
            _ = self.value.orderedRemove(self.cursor_col);
            self.changed = true;
        }
    }

    pub fn isMouseOver(self: *const Impl) bool {
        return self.dialog.imtui.mouse_row == self.r and
            self.dialog.imtui.mouse_col >= self.c1 and self.dialog.imtui.mouse_col < self.c2;
    }

    pub fn handleMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        if (cm)
            // XXX ignore clickmatic for now.
            return .{ .dialog_input = self };

        if (!self.isMouseOver())
            return self.dialog.commonMouseDown(b, clicks, cm); // <- pretty sure this is wrong cf `cm`; check XXX

        if (!self.imtui.focused(self)) {
            try self.imtui.focus(self);
            // TODO: select all by default, but we currently don't support selections
        } else {
            // clicking on already selected; set cursor where clicked.
            self.cursor_col = self.scroll_col + self.dialog.imtui.mouse_col - self.c1;
        }

        return .{ .dialog_input = self };
    }
};

impl: *Impl,

pub fn create(dialog: *Dialog.Impl, ix: usize, r: usize, c1: usize, c2: usize) !DialogInput {
    var b = try dialog.imtui.allocator.create(Impl);
    b.* = .{
        .imtui = dialog.imtui,
        .dialog = dialog,
        .generation = dialog.imtui.generation,
        .ix = ix,
    };
    b.describe(r, c1, c2);
    return .{ .impl = b };
}

pub fn accel(self: DialogInput, key: u8) void {
    self.impl.accel = key;
}

pub fn initial(self: DialogInput) ?*std.ArrayListUnmanaged(u8) {
    if (self.impl.initted) return null;
    self.impl.initted = true;
    return &self.impl.value;
}

pub fn changed(self: DialogInput) ?[]const u8 {
    defer self.impl.changed = false;
    return if (self.impl.changed) self.impl.value.items else null;
}
