const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const Imtui = @import("../Imtui.zig");

const DialogCheckbox = @This();

pub const Impl = struct {
    imtui: *Imtui,
    dialog: *Dialog.Impl,
    generation: usize,

    // id
    ix: usize,

    // config
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,
    accel: ?u8 = undefined,

    // state
    selected: bool,
    changed: bool = false,
    targeted: bool = false,

    pub fn deinit(self: *Impl) void {
        self.imtui.allocator.destroy(self);
    }

    pub fn parent(self: *const Impl) Imtui.Control {
        return .{ .dialog = self.dialog };
    }

    pub fn describe(self: *Impl, r: usize, c: usize, label: []const u8) void {
        self.r = self.dialog.r1 + r;
        self.c = self.dialog.c1 + c;
        self.label = label;
        self.accel = Imtui.Controls.acceleratorFor(label);

        self.dialog.imtui.text_mode.write(self.r, self.c, if (self.selected) "[X] " else "[ ] ");
        self.dialog.imtui.text_mode.writeAccelerated(self.r, self.c + 4, label, self.dialog.show_acc);

        if (self.imtui.focused(self)) {
            self.dialog.imtui.text_mode.cursor_row = self.r;
            self.dialog.imtui.text_mode.cursor_col = self.c + 1;
        }
    }

    fn space(self: *Impl) void {
        self.changed = true;
        self.selected = !self.selected;
    }

    pub fn accelerate(self: *Impl) !void {
        self.space();
        try self.imtui.focus(self);
    }

    pub fn handleKeyPress(self: *Impl, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        switch (keycode) {
            .up, .left => {
                self.changed = !self.selected;
                self.selected = true;
            },
            .down, .right => {
                self.changed = self.selected;
                self.selected = false;
            },
            .space => self.space(),
            else => try self.dialog.commonKeyPress(self.ix, keycode, modifiers),
        }
    }

    pub fn isMouseOver(self: *const Impl) bool {
        return self.dialog.imtui.mouse_row == self.r and
            self.dialog.imtui.mouse_col >= self.c and self.dialog.imtui.mouse_col < self.c + self.label.len + 4;
    }

    pub fn handleMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        if (!self.isMouseOver())
            return self.dialog.commonMouseDown(b, clicks, cm); // <- pretty sure this is wrong cf `cm`; check XXX

        if (b != .left or cm) return .{ .dialog_checkbox = self };

        try self.imtui.focus(self);
        self.targeted = true;

        return .{ .dialog_checkbox = self };
    }

    pub fn handleMouseDrag(self: *Impl, b: SDL.MouseButton) !void {
        if (b != .left) return;

        self.targeted = self.isMouseOver();
    }

    pub fn handleMouseUp(self: *Impl, b: SDL.MouseButton, clicks: u8) !void {
        _ = clicks;

        if (b != .left) return;

        if (self.targeted) {
            self.targeted = false;
            try self.accelerate();
        }
    }
};

impl: *Impl,

pub fn create(dialog: *Dialog.Impl, ix: usize, r: usize, c: usize, label: []const u8, selected: bool) !DialogCheckbox {
    var b = try dialog.imtui.allocator.create(Impl);
    b.* = .{
        .imtui = dialog.imtui,
        .dialog = dialog,
        .generation = dialog.imtui.generation,
        .selected = selected,
        .ix = ix,
    };
    b.describe(r, c, label);
    return .{ .impl = b };
}

pub fn changed(self: *DialogCheckbox) ?bool {
    defer self.impl.changed = false;
    return if (self.impl.changed) self.impl.selected else null;
}
