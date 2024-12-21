const std = @import("std");
const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const EditorLike = @import("./EditorLike.zig");
const Source = @import("./Source.zig");
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

    // state
    el: EditorLike,
    source: *Source,
    value: *std.ArrayListUnmanaged(u8), // points straight into `source.lines`
    initted: bool = false,
    changed: bool = false,

    pub fn deinit(self: *Impl) void {
        self.source.release();
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

        self.el.describe(self.r, self.c1, self.r + 1, self.c2);

        self.el.draw(self.imtui.focused(self), 0x07); // XXX
    }

    pub fn accelerate(self: *Impl) !void {
        if (!self.imtui.focused(self))
            try self.focusAndSelectAll();
    }

    pub fn blur(self: *Impl) void {
        self.el.cursor_col = 0;
        self.el.selection_start = null;
    }

    pub fn focusAndSelectAll(self: *Impl) !void {
        try self.imtui.focus(self);
        self.el.cursor_col = self.value.items.len;
        self.el.selection_start = .{
            .cursor_row = 0,
            .cursor_col = 0,
        };
    }

    pub fn handleKeyPress(self: *Impl, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        // XXX is this all dialog inputs, or just Display's Tab Stops?
        // Note this is the default MAX_LINE for full-screen editors, less Tab
        // Stops' exact c1 (255 - 48 = 207). Hah.
        // const MAX_LINE = 207; // XXX: unused; fit into EditorLike.

        if (keycode != .tab)
            if (try self.el.handleKeyPress(keycode, modifiers)) {
                self.changed = true;
                return;
            };

        try self.dialog.commonKeyPress(self.ix, keycode, modifiers);
    }

    pub fn isMouseOver(self: *const Impl) bool {
        return self.dialog.imtui.mouse_row == self.r and
            self.dialog.imtui.mouse_col >= self.c1 and self.dialog.imtui.mouse_col < self.c2;
    }

    pub fn handleMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const active = self.imtui.focused(self);

        if (!cm) {
            if (!self.isMouseOver()) {
                const new = try self.dialog.commonMouseDown(b, clicks, cm);
                if (new != null and new.? != .dialog)
                    self.blur();
                return new;
            }
        } else {
            // cm
            if (try self.el.handleMouseDown(active, b, clicks, cm))
                return .{ .dialog_input = self };
            return null;
        }

        if (try self.el.handleMouseDown(active, b, clicks, cm)) {
            if (!active)
                try self.focusAndSelectAll()
            else
                // clicking on already selected; set cursor where clicked.
                self.el.cursor_col = self.el.scroll_col + self.dialog.imtui.mouse_col - self.c1;

            return .{ .dialog_input = self };
        }

        return null;
    }

    pub fn handleMouseDrag(self: *Impl, b: SDL.MouseButton) !void {
        return self.el.handleMouseDrag(b);
    }
};

impl: *Impl,

pub fn create(dialog: *Dialog.Impl, ix: usize, r: usize, c1: usize, c2: usize) !DialogInput {
    var source = try Source.createSingleLine(dialog.imtui.allocator);
    var b = try dialog.imtui.allocator.create(Impl);
    b.* = .{
        .imtui = dialog.imtui,
        .dialog = dialog,
        .generation = dialog.imtui.generation,
        .ix = ix,
        .el = .{
            .imtui = dialog.imtui,
            .source = source,
        },
        .source = source,
        .value = &source.lines.items[0],
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
    return self.impl.value;
}

pub fn changed(self: DialogInput) ?[]const u8 {
    defer self.impl.changed = false;
    return if (self.impl.changed) self.impl.value.items else null;
}
