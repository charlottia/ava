const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const Imtui = @import("../Imtui.zig");

const DialogButton = @This();

pub const Impl = struct {
    imtui: *Imtui,
    dialog: *Dialog.Impl,
    ix: usize = undefined,
    generation: usize,
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,
    accel: ?u8 = undefined,

    chosen: bool = false,
    inverted: bool = false,

    pub fn deinit(self: *Impl) void {
        @import("std").log.debug("DialogButton.Impl self is {*}", .{self});
        self.imtui.allocator.destroy(self);
    }

    pub fn describe(self: *Impl, ix: usize, r: usize, c: usize, label: []const u8) void {
        self.ix = ix;
        self.r = self.dialog.r1 + r;
        self.c = self.dialog.c1 + c;
        self.label = label;
        self.accel = Imtui.Controls.acceleratorFor(label);
    }

    pub fn draw(self: *Impl) void {
        var arrowcolour: u8 =
            if (self.dialog.focus_ix == self.ix or
            (self.dialog.default_button == self and self.dialog.controls.items[self.dialog.focus_ix] != .button))
            0x7f
        else
            0x70;
        var textcolour: u8 = 0x70;

        if (self.inverted) {
            arrowcolour = 0x07;
            textcolour = 0x07;
        }

        const ec = self.c + 2 + Imtui.Controls.lenWithoutAccelerators(self.label) + 1;
        self.imtui.text_mode.paint(self.r, self.c + 1, self.r + 1, ec, textcolour, .Blank);

        self.imtui.text_mode.paint(self.r, self.c, self.r + 1, self.c + 1, arrowcolour, '<');
        self.imtui.text_mode.writeAccelerated(self.r, self.c + 2, self.label, self.dialog.show_acc and !self.inverted);
        self.imtui.text_mode.paint(self.r, ec, self.r + 1, ec + 1, arrowcolour, '>');

        if (self.dialog.focus_ix == self.ix) {
            self.imtui.text_mode.cursor_row = self.r;
            self.imtui.text_mode.cursor_col = self.c + 2;
        }
    }

    pub fn accelerate(self: *Impl) void {
        self.dialog.focus_ix = self.ix;
        self.chosen = true;
    }

    pub fn space(self: *Impl) void {
        self.inverted = true;
    }

    pub fn handleKeyUp(self: *Impl, keycode: SDL.Keycode) !void {
        if (keycode == .space and self.inverted and self.dialog.focus_ix == self.ix) {
            self.inverted = false;
            self.chosen = true;
        }
    }

    pub fn blur(self: *Impl) !void {
        self.inverted = false;
    }

    pub fn mouseIsOver(self: *const Impl) bool {
        return self.imtui.mouse_row == self.r and self.imtui.mouse_col >= self.c and self.imtui.mouse_col < self.c + self.label.len + 4;
    }

    pub fn handleMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8, cm: bool) !bool {
        _ = clicks;

        if (!self.mouseIsOver())
            return false;

        if (b != .left or cm) return true;

        self.dialog.focus_ix = self.ix;
        self.inverted = true;

        return true;
    }

    pub fn handleMouseDrag(self: *Impl, b: SDL.MouseButton) !void {
        if (b != .left) return;

        self.inverted = self.mouseIsOver();
    }

    pub fn handleMouseUp(self: *Impl, b: SDL.MouseButton, clicks: u8) !void {
        _ = clicks;

        if (b != .left) return;

        if (self.inverted) {
            self.inverted = false;
            self.accelerate();
        }
    }
};

impl: *Impl,

pub fn create(dialog: *Dialog.Impl, ix: usize, r: usize, c: usize, label: []const u8) !DialogButton {
    var b = try dialog.imtui.allocator.create(Impl);
    b.* = .{
        .imtui = dialog.imtui,
        .dialog = dialog,
        .generation = dialog.imtui.generation,
    };
    b.describe(ix, r, c, label);
    return .{ .impl = b };
}

pub fn default(self: DialogButton) void {
    self.impl.dialog.default_button = self.impl;
}

pub fn cancel(self: DialogButton) void {
    self.impl.dialog.cancel_button = self.impl;
}

pub fn chosen(self: DialogButton) bool {
    defer self.impl.chosen = false;
    return self.impl.chosen;
}
