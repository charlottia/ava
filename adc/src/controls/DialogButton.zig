const Dialog = @import("./Dialog.zig");
const Imtui = @import("../Imtui.zig");

const DialogButton = @This();

dialog: *Dialog,
ix: usize = undefined,
generation: usize,
r: usize = undefined,
c: usize = undefined,
label: []const u8 = undefined,
_accel: ?u8 = undefined,

_chosen: bool = false,

pub fn create(dialog: *Dialog, ix: usize, r: usize, c: usize, label: []const u8) !*DialogButton {
    var b = try dialog.imtui.allocator.create(DialogButton);
    b.* = .{
        .dialog = dialog,
        .generation = dialog.imtui.generation,
    };
    b.describe(ix, r, c, label);
    return b;
}

pub fn deinit(self: *DialogButton) void {
    self.dialog.imtui.allocator.destroy(self);
}

pub fn describe(self: *DialogButton, ix: usize, r: usize, c: usize, label: []const u8) void {
    self.ix = ix;
    self.r = r;
    self.c = c;
    self.label = label;
    self._accel = Imtui.Controls.acceleratorFor(label);
}

pub fn draw(self: *const DialogButton) void {
    const colour: u8 = if (self.dialog.focus_ix == self.ix or
        (self.dialog._default_button == self and self.dialog.controls.items[self.dialog.focus_ix] != .button))
        0x7f
    else
        0x70;

    self.dialog.imtui.text_mode.paint(self.r, self.c, self.r + 1, self.c + 1, colour, '<');
    self.dialog.imtui.text_mode.writeAccelerated(self.r, self.c + 2, self.label, self.dialog.show_acc);
    const ec = self.c + 2 + Imtui.Controls.lenWithoutAccelerators(self.label) + 1;
    self.dialog.imtui.text_mode.paint(self.r, ec, self.r + 1, ec + 1, colour, '>');

    if (self.dialog.focus_ix == self.ix) {
        self.dialog.imtui.text_mode.cursor_row = self.dialog.imtui.text_mode.offset_row + self.r;
        self.dialog.imtui.text_mode.cursor_col = self.dialog.imtui.text_mode.offset_col + self.c + 2;
    }
}

pub fn default(self: *DialogButton) void {
    self.dialog._default_button = self;
}

pub fn cancel(self: *DialogButton) void {
    self.dialog._cancel_button = self;
}

pub fn focus(self: *DialogButton) void {
    self.dialog.focus_ix = self.ix;
    self._chosen = true;
}

pub fn chosen(self: *DialogButton) bool {
    defer self._chosen = false;
    return self._chosen;
}
