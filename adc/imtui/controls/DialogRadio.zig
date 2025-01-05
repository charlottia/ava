const std = @import("std");
const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const Imtui = @import("../Imtui.zig");

const DialogRadio = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    dialog: *Dialog.Impl,

    // id
    ix: usize,

    // config
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,
    accel: ?u8 = undefined,

    // state
    selected: bool,
    selected_read: bool = false,
    targeted: bool = false,

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .parent = parent,
                .deinit = deinit,
                .accelGet = accelGet,
                .accelerate = accelerate,
                .handleKeyPress = handleKeyPress,
                .handleKeyUp = handleKeyUp,
                .isMouseOver = isMouseOver,
                .handleMouseDown = handleMouseDown,
                .handleMouseDrag = handleMouseDrag,
                .handleMouseUp = handleMouseUp,
            },
        };
    }

    pub fn describe(self: *Impl, _: *Dialog.Impl, _: usize, r: usize, c: usize, label: []const u8) void {
        self.r = self.dialog.r1 + r;
        self.c = self.dialog.c1 + c;
        self.label = label;
        self.accel = Imtui.Controls.acceleratorFor(label);

        self.dialog.imtui.text_mode.write(self.r, self.c, "( ) ");
        if (self.selected)
            self.dialog.imtui.text_mode.draw(self.r, self.c + 1, 0x70, .Bullet);
        self.dialog.imtui.text_mode.writeAccelerated(self.r, self.c + 4, label, self.dialog.show_acc);

        if (self.imtui.focused(self.control())) {
            self.dialog.imtui.text_mode.cursor_row = self.r;
            self.dialog.imtui.text_mode.cursor_col = self.c + 1;
        }
    }

    fn parent(ptr: *const anyopaque) ?Imtui.Control {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.dialog.control();
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.imtui.allocator.destroy(self);
    }

    fn accelGet(ptr: *const anyopaque) ?u8 {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.accel;
    }

    fn select(self: *Impl) !void {
        self.selected = true;
        self.selected_read = false;
        try self.imtui.focus(self.control());
    }

    fn accelerate(ptr: *anyopaque) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        for (self.dialog.controls.items) |c|
            if (c.is(Impl)) |b| {
                b.selected = false;
            };

        try self.select();
    }

    fn findKin(self: *Impl, dir: enum { before, after }) *Impl {
        var ix = self.ix;
        while (true) {
            ix = switch (dir) {
                .before => if (ix == 0) self.dialog.controls.items.len - 1 else ix - 1,
                .after => if (ix == self.dialog.controls.items.len - 1) 0 else ix + 1,
            };

            if (self.dialog.controls.items[ix].is(Impl)) |b| {
                std.debug.assert(b.ix != self.ix);
                return b;
            }
        }
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        switch (keycode) {
            .space => try accelerate(ptr),
            .up, .left => {
                std.debug.assert(self.selected);
                self.selected = false;
                try self.findKin(.before).select();
            },
            .down, .right => {
                std.debug.assert(self.selected);
                self.selected = false;
                try self.findKin(.after).select();
            },
            else => try self.dialog.commonKeyPress(self.ix, keycode, modifiers),
        }
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.dialog.imtui.mouse_row == self.r and
            self.dialog.imtui.mouse_col >= self.c and self.dialog.imtui.mouse_col < self.c + self.label.len + 3;
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        if (cm) return null;
        if (!isMouseOver(ptr)) return self.dialog.commonMouseDown(b, clicks, cm);
        if (b != .left) return null;

        try self.imtui.focus(self.control());
        self.targeted = true;

        return self.control();
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;

        self.targeted = isMouseOver(ptr);
    }

    fn handleMouseUp(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;
        _ = clicks;

        if (self.targeted) {
            self.targeted = false;
            try accelerate(ptr);
        }
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, dialog: *Dialog.Impl, ix: usize, _: usize, _: usize, _: []const u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{d}/{d}", .{ "core.DialogRadio", dialog.id, ix });
}

pub fn create(imtui: *Imtui, dialog: *Dialog.Impl, ix: usize, r: usize, c: usize, label: []const u8) !DialogRadio {
    var b = try imtui.allocator.create(Impl);
    defer dialog.radio_index += 1;
    b.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .dialog = dialog,
        .ix = ix,
        .selected = dialog.radio_index == 0,
    };
    b.describe(dialog, ix, r, c, label);
    try dialog.controls.append(imtui.allocator, b.control());
    return .{ .impl = b };
}

pub fn selected(self: DialogRadio) bool {
    defer self.impl.selected_read = true;
    return self.impl.selected and !self.impl.selected_read;
}
