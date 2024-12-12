const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const Imtui = @import("../Imtui.zig");

const DialogCheckbox = @This();

pub const Impl = struct {
    dialog: *Dialog.Impl,
    generation: usize,
    ix: usize = undefined,
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,
    accel: ?u8 = undefined,

    selected: bool,
    changed: bool = false,
    targeted: bool = false,

    pub fn deinit(self: *Impl) void {
        self.dialog.imtui.allocator.destroy(self);
    }

    pub fn describe(self: *Impl, ix: usize, r: usize, c: usize, label: []const u8) void {
        self.dialog.imtui.text_mode.write(r, c, if (self.selected) "[X] " else "[ ] ");
        self.dialog.imtui.text_mode.writeAccelerated(r, c + 4, label, self.dialog.show_acc);

        self.ix = ix;
        self.r = self.dialog.imtui.text_mode.offset_row + r;
        self.c = self.dialog.imtui.text_mode.offset_col + c;
        self.label = label;
        self.accel = Imtui.Controls.acceleratorFor(label);

        if (self.dialog.focus_ix == self.dialog.controls_at) {
            self.dialog.imtui.text_mode.cursor_row = self.r;
            self.dialog.imtui.text_mode.cursor_col = self.c + 1;
        }
    }

    pub fn up(self: *Impl) void {
        self.changed = !self.selected;
        self.selected = true;
    }

    pub fn down(self: *Impl) void {
        self.changed = self.selected;
        self.selected = false;
    }

    pub fn space(self: *Impl) void {
        self.changed = true;
        self.selected = !self.selected;
    }

    pub fn accelerate(self: *Impl) void {
        self.space();
        self.dialog.focus_ix = self.ix;
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

pub fn create(dialog: *Dialog.Impl, ix: usize, r: usize, c: usize, label: []const u8, selected: bool) !DialogCheckbox {
    var b = try dialog.imtui.allocator.create(Impl);
    b.* = .{
        .dialog = dialog,
        .generation = dialog.imtui.generation,
        .selected = selected,
    };
    b.describe(ix, r, c, label);
    return .{ .impl = b };
}

pub fn changed(self: *DialogCheckbox) ?bool {
    defer self.impl.changed = false;
    return if (self.impl.changed) self.impl.selected else null;
}
