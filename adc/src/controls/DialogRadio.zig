const std = @import("std");

const Dialog = @import("./Dialog.zig");
const Imtui = @import("../Imtui.zig");

const DialogRadio = @This();

dialog: *Dialog,
ix: usize = undefined,
generation: usize,
group_id: usize = undefined,
item_id: usize = undefined,
r: usize = undefined,
c: usize = undefined,
label: []const u8 = undefined,
_accel: ?u8 = undefined,
_selected: bool,
_selected_read: bool = false,

pub fn create(dialog: *Dialog, ix: usize, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) !*DialogRadio {
    var b = try dialog.imtui.allocator.create(DialogRadio);
    b.* = .{
        .dialog = dialog,
        .generation = dialog.imtui.generation,
        ._selected = item_id == 0,
    };
    b.describe(ix, group_id, item_id, r, c, label);
    return b;
}

pub fn deinit(self: *DialogRadio) void {
    self.dialog.imtui.allocator.destroy(self);
}

pub fn describe(self: *DialogRadio, ix: usize, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) void {
    self.ix = ix;
    self.group_id = group_id;
    self.item_id = item_id;
    self.r = r;
    self.c = c;
    self.label = label;
    self._accel = Imtui.Controls.acceleratorFor(label);

    self.dialog.imtui.text_mode.write(r, c, "( ) ");
    if (self._selected)
        self.dialog.imtui.text_mode.draw(r, c + 1, 0x70, .Bullet);
    self.dialog.imtui.text_mode.writeAccelerated(r, c + 4, label, self.dialog.show_acc);

    if (self.dialog.focus_ix == ix) {
        self.dialog.imtui.text_mode.cursor_row = self.dialog.imtui.text_mode.offset_row + r;
        self.dialog.imtui.text_mode.cursor_col = self.dialog.imtui.text_mode.offset_col + c + 1;
    }
}

pub fn up(self: *DialogRadio) void {
    std.debug.assert(self._selected);
    self._selected = false;
    self.findKin(self.item_id -% 1).select();
}

pub fn down(self: *DialogRadio) void {
    std.debug.assert(self._selected);
    self._selected = false;
    self.findKin(self.item_id + 1).select();
}

fn select(self: *DialogRadio) void {
    self._selected = true;
    self._selected_read = false;
    self.dialog.focus_ix = self.ix;
}

pub fn focus(self: *DialogRadio) void {
    for (self.dialog.controls.items) |c|
        switch (c) {
            .radio => |b| if (b.group_id == self.group_id) {
                b._selected = false;
            },
            else => {},
        };

    self.select();
}

pub fn selected(self: *DialogRadio) bool {
    defer self._selected_read = true;
    return self._selected and !self._selected_read;
}

fn findKin(self: *DialogRadio, id: usize) *DialogRadio {
    var zero: ?*DialogRadio = null;
    var high: ?*DialogRadio = null;
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
