const std = @import("std");
const SDL = @import("sdl2");

const Dialog = @import("./Dialog.zig");
const Imtui = @import("../Imtui.zig");

const DialogButton = @This();

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
    padding: usize = undefined,
    accel: ?u8 = undefined,

    // state
    chosen: bool = false,
    inverted: bool = false,

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
        self.padding = 1;
        self.accel = Imtui.Controls.acceleratorFor(label);
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

    fn accelerate(ptr: *anyopaque) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        try self.imtui.focus(self.control());
        self.chosen = true;
    }

    pub fn draw(self: *Impl) void {
        var arrowcolour: u8 =
            if (self.imtui.focused(self.control()) or
            (self.dialog.default_button == self and self.imtui.focus_stack.getLast().is(Impl) == null))
            0x7f
        else
            0x70;
        var textcolour: u8 = 0x70;

        if (self.inverted) {
            arrowcolour = 0x07;
            textcolour = 0x07;
        }

        const ec = self.c + 1 + self.padding + Imtui.Controls.lenWithoutAccelerators(self.label) + self.padding;
        self.imtui.text_mode.paint(self.r, self.c + 1, self.r + 1, ec, textcolour, .Blank);

        self.imtui.text_mode.paint(self.r, self.c, self.r + 1, self.c + 1, arrowcolour, '<');
        self.imtui.text_mode.writeAccelerated(self.r, self.c + 1 + self.padding, self.label, self.dialog.show_acc and !self.inverted);
        self.imtui.text_mode.paint(self.r, ec, self.r + 1, ec + 1, arrowcolour, '>');

        if (self.imtui.focused(self.control())) {
            self.imtui.text_mode.cursor_row = self.r;
            self.imtui.text_mode.cursor_col = self.c + 1 + self.padding;
        }
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        switch (keycode) {
            .@"return" => self.chosen = true,
            .space => self.inverted = true,
            .tab => {
                self.inverted = false;
                try self.dialog.commonKeyPress(self.ix, keycode, modifiers);
            },
            else => try self.dialog.commonKeyPress(self.ix, keycode, modifiers),
        }
    }

    fn handleKeyUp(ptr: *anyopaque, keycode: SDL.Keycode) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        if (keycode == .space and self.inverted and self.imtui.focused(self.control())) {
            self.inverted = false;
            self.chosen = true;
        }
    }

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
        self.inverted = true;

        return self.control();
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;

        self.inverted = isMouseOver(ptr);
    }

    fn handleMouseUp(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;
        _ = clicks;

        if (self.inverted) {
            self.inverted = false;
            try accelerate(ptr);
        }
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, dialog: *Dialog.Impl, ix: usize, _: usize, _: usize, _: []const u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{s}/{d}", .{ "core.DialogButton", dialog.ident, ix });
}

pub fn create(imtui: *Imtui, dialog: *Dialog.Impl, ix: usize, r: usize, c: usize, label: []const u8) !DialogButton {
    var b = try imtui.allocator.create(Impl);
    b.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .dialog = dialog,
        .ix = ix,
    };
    b.describe(dialog, ix, r, c, label);
    try dialog.controls.append(imtui.allocator, b.control());
    return .{ .impl = b };
}

pub fn default(self: DialogButton) void {
    self.impl.dialog.default_button = self.impl;
}

pub fn cancel(self: DialogButton) void {
    self.impl.dialog.cancel_button = self.impl;
}

pub fn padding(self: DialogButton, n: usize) void {
    self.impl.padding = n;
}

pub fn chosen(self: DialogButton) bool {
    defer self.impl.chosen = false;
    return self.impl.chosen;
}
