const std = @import("std");
const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const Imtui = @import("../Imtui.zig");

const DialogRadio = @This();

pub const Impl = struct {
    dialog: *Dialog.Impl,
    ix: usize = undefined,
    generation: usize,
    group_id: usize = undefined,
    item_id: usize = undefined,
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,
    accel: ?u8 = undefined,
    selected: bool,
    selected_read: bool = false,
    targeted: bool = false,

    pub fn deinit(self: *Impl) void {
        self.dialog.imtui.allocator.destroy(self);
    }

    pub fn describe(self: *Impl, ix: usize, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) void {
        self.dialog.imtui.text_mode.write(r, c, "( ) ");
        if (self.selected)
            self.dialog.imtui.text_mode.draw(r, c + 1, 0x70, .Bullet);
        self.dialog.imtui.text_mode.writeAccelerated(r, c + 4, label, self.dialog.show_acc);

        self.ix = ix;
        self.group_id = group_id;
        self.item_id = item_id;
        self.r = self.dialog.imtui.text_mode.offset_row + r;
        self.c = self.dialog.imtui.text_mode.offset_col + c;
        self.label = label;
        self.accel = Imtui.Controls.acceleratorFor(label);

        if (self.dialog.focus_ix == ix) {
            self.dialog.imtui.text_mode.cursor_row = self.r;
            self.dialog.imtui.text_mode.cursor_col = self.c + 1;
        }
    }

    pub fn up(self: *Impl) void {
        std.debug.assert(self.selected);
        self.selected = false;
        self.findKin(self.item_id -% 1).select();
    }

    pub fn down(self: *Impl) void {
        std.debug.assert(self.selected);
        self.selected = false;
        self.findKin(self.item_id + 1).select();
    }

    pub fn space(self: *Impl) void {
        self.accelerate();
    }

    fn select(self: *Impl) void {
        self.selected = true;
        self.selected_read = false;
        self.dialog.focus_ix = self.ix;
    }

    pub fn accelerate(self: *Impl) void {
        for (self.dialog.controls.items) |c|
            switch (c) {
                .radio => |b| if (b.group_id == self.group_id) {
                    b.selected = false;
                },
                else => {},
            };

        self.select();
    }

    fn findKin(self: *Impl, id: usize) *Impl {
        var zero: ?*Impl = null;
        var high: ?*Impl = null;
        for (self.dialog.controls.items) |c|
            switch (c) {
                .radio => |b| if (b.group_id == self.group_id) {
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

    pub fn mouseIsOver(self: *const Impl) bool {
        return self.dialog.imtui.mouse_row == self.r and self.dialog.imtui.mouse_col >= self.c and self.dialog.imtui.mouse_col < self.c + self.label.len + 4;
    }

    pub fn handleMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8, cm: bool) !void {
        _ = clicks;

        if (b != .left or cm) return;

        self.dialog.focus_ix = self.ix;
        self.targeted = true;
    }

    pub fn handleMouseDrag(self: *Impl, b: SDL.MouseButton) !void {
        if (b != .left) return;

        self.targeted = self.mouseIsOver();
    }

    pub fn handleMouseUp(self: *Impl, b: SDL.MouseButton, clicks: u8) !void {
        _ = clicks;

        if (b != .left) return;

        if (self.targeted) {
            self.targeted = false;
            self.accelerate();
        }
    }
};

impl: *Impl,

pub fn create(dialog: *Dialog.Impl, ix: usize, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) !DialogRadio {
    var b = try dialog.imtui.allocator.create(Impl);
    b.* = .{
        .dialog = dialog,
        .generation = dialog.imtui.generation,
        .selected = item_id == 0,
    };
    b.describe(ix, group_id, item_id, r, c, label);
    return .{ .impl = b };
}

pub fn selected(self: DialogRadio) bool {
    defer self.impl.selected_read = true;
    return self.impl.selected and !self.impl.selected_read;
}
