const std = @import("std");
const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const Imtui = @import("../Imtui.zig");

const DialogCheckbox = @This();

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
    changed: bool = false,
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

    pub fn describe(self: *Impl, _: *Dialog.Impl, _: usize, r: usize, c: usize, label: []const u8, _: bool) void {
        self.r = self.dialog.r1 + r;
        self.c = self.dialog.c1 + c;
        self.label = label;
        self.accel = Imtui.Controls.acceleratorFor(label);

        self.imtui.text_mode.write(self.r, self.c, if (self.selected) "[X] " else "[ ] ");
        self.imtui.text_mode.writeAccelerated(self.r, self.c + 4, label, self.dialog.show_acc);

        if (self.imtui.focused(self.control())) {
            self.imtui.text_mode.cursor_row = self.r;
            self.imtui.text_mode.cursor_col = self.c + 1;
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

    fn space(self: *Impl) void {
        self.changed = true;
        self.selected = !self.selected;
    }

    fn accelerate(ptr: *anyopaque) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.space();
        try self.imtui.focus(self.control());
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
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

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.imtui.mouse_row == self.r and
            self.imtui.mouse_col >= self.c and self.imtui.mouse_col < self.c + self.label.len + 4;
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

pub fn bufPrintImtuiId(buf: []u8, dialog: *Dialog.Impl, ix: usize, _: usize, _: usize, _: []const u8, _: bool) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{d}/{d}", .{ "core.DialogCheckbox", dialog.id, ix });
}

pub fn create(imtui: *Imtui, dialog: *Dialog.Impl, ix: usize, r: usize, c: usize, label: []const u8, selected: bool) !DialogCheckbox {
    var b = try imtui.allocator.create(Impl);
    b.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .dialog = dialog,
        .selected = selected,
        .ix = ix,
    };
    b.describe(dialog, ix, r, c, label, selected);
    try dialog.controls.append(imtui.allocator, b.control());
    return .{ .impl = b };
}

pub fn changed(self: *DialogCheckbox) ?bool {
    defer self.impl.changed = false;
    return if (self.impl.changed) self.impl.selected else null;
}
