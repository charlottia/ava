const std = @import("std");
const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const Imtui = @import("../Imtui.zig");

const DialogRadio = @This();

pub const Impl = struct {
    imtui: *Imtui,
    dialog: *Dialog.Impl,
    generation: usize,

    // id
    ix: usize,

    // config
    group_id: usize = undefined,
    item_id: usize = undefined,
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,
    accel: ?u8 = undefined,

    // state
    selected: bool,
    selected_read: bool = false,
    targeted: bool = false,

    pub fn deinit(self: *Impl) void {
        self.imtui.allocator.destroy(self);
    }

    pub fn parent(self: *const Impl) Imtui.Control {
        return .{ .dialog = self.dialog };
    }

    pub fn describe(self: *Impl, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) void {
        self.group_id = group_id;
        self.item_id = item_id;
        self.r = self.dialog.r1 + r;
        self.c = self.dialog.c1 + c;
        self.label = label;
        self.accel = Imtui.Controls.acceleratorFor(label);

        self.dialog.imtui.text_mode.write(self.r, self.c, "( ) ");
        if (self.selected)
            self.dialog.imtui.text_mode.draw(self.r, self.c + 1, 0x70, .Bullet);
        self.dialog.imtui.text_mode.writeAccelerated(self.r, self.c + 4, label, self.dialog.show_acc);

        if (self.imtui.focused(self)) {
            self.dialog.imtui.text_mode.cursor_row = self.r;
            self.dialog.imtui.text_mode.cursor_col = self.c + 1;
        }
    }

    fn select(self: *Impl) !void {
        self.selected = true;
        self.selected_read = false;
        try self.imtui.focus(self);
    }

    pub fn accelerate(self: *Impl) !void {
        for (self.dialog.controls.items) |c|
            switch (c) {
                .dialog_radio => |b| if (b.group_id == self.group_id) {
                    b.selected = false;
                },
                else => {},
            };

        try self.select();
    }

    fn findKin(self: *Impl, id: usize) *Impl {
        var zero: ?*Impl = null;
        var high: ?*Impl = null;
        for (self.dialog.controls.items) |c|
            switch (c) {
                .dialog_radio => |b| if (b.group_id == self.group_id) {
                    if (b.item_id == 0)
                        zero = b
                    else if (b.item_id == id)
                        return b
                    else if (high) |h|
                        high = if (b.item_id > h.item_id) b else h
                    else
                        high = b;
                },
                else => {},
            };
        return if (id == std.math.maxInt(usize)) high.? else zero.?;
    }

    pub fn isMouseOver(self: *const Impl) bool {
        return self.dialog.imtui.mouse_row == self.r and
            self.dialog.imtui.mouse_col >= self.c and self.dialog.imtui.mouse_col < self.c + self.label.len + 3;
    }

    pub fn handleKeyPress(self: *Impl, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        switch (keycode) {
            .space => try self.accelerate(),
            .up, .left => {
                std.debug.assert(self.selected);
                self.selected = false;
                try self.findKin(self.item_id -% 1).select();
            },
            .down, .right => {
                std.debug.assert(self.selected);
                self.selected = false;
                try self.findKin(self.item_id + 1).select();
            },
            else => try self.dialog.commonKeyPress(self.ix, keycode, modifiers),
        }
    }

    pub fn handleMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        if (!self.isMouseOver())
            return self.dialog.commonMouseDown(b, clicks, cm);

        if (b != .left or cm) return .{ .dialog_radio = self };

        try self.imtui.focus(self);
        self.targeted = true;

        return .{ .dialog_radio = self };
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

pub fn create(dialog: *Dialog.Impl, ix: usize, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) !DialogRadio {
    var b = try dialog.imtui.allocator.create(Impl);
    b.* = .{
        .imtui = dialog.imtui,
        .dialog = dialog,
        .generation = dialog.imtui.generation,
        .ix = ix,
        .selected = item_id == 0,
    };
    b.describe(group_id, item_id, r, c, label);
    return .{ .impl = b };
}

pub fn selected(self: DialogRadio) bool {
    defer self.impl.selected_read = true;
    return self.impl.selected and !self.impl.selected_read;
}
