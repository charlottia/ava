const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Dialog = @This();

pub const Position = union(enum) {
    centred,
    at: struct { row: usize, col: usize },
};

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    title: []const u8,
    r1: usize = undefined,
    c1: usize = undefined,
    r2: usize = undefined,
    c2: usize = undefined,

    applied_initial_focus: bool = false,
    controls: std.ArrayListUnmanaged(Imtui.Control) = .{},
    controls_at: usize = undefined,
    show_acc: bool = false,
    default_button: ?*Imtui.Controls.DialogButton.Impl = undefined,
    cancel_button: ?*Imtui.Controls.DialogButton.Impl = undefined,
    pending_accel: ?u8 = null,

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .orphan = true,
                .no_mouse = true,
                .no_key = true,
                .deinit = deinit,
            },
        };
    }

    pub fn describe(self: *Impl, _: []const u8, height: usize, width: usize, position: Position) void {
        switch (position) {
            .centred => {
                self.r1 = (self.imtui.text_mode.H - height) / 2;
                self.c1 = (self.imtui.text_mode.W - width) / 2;
            },
            .at => |at| {
                self.r1 = at.row;
                self.c1 = at.col;
            },
        }
        self.r2 = self.r1 + height;
        self.c2 = self.c1 + width;
        self.controls_at = 0;
        self.default_button = null;
        self.cancel_button = null;

        (Dialog{ .impl = self }).groupbox(self.title, 0, 0, height, width, 0x70);
        for (1..height + 1) |r| {
            self.imtui.text_mode.shadow(self.r1 + r, self.c1 + width);
            self.imtui.text_mode.shadow(self.r1 + r, self.c1 + width + 1);
        }
        for (2..width) |c|
            self.imtui.text_mode.shadow(self.r1 + height, self.c1 + c);
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        // Controls deallocate themselves, this is just for safekeeping.
        self.controls.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn commonKeyPress(self: *Impl, ix: usize, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        switch (keycode) {
            .left_alt, .right_alt => self.show_acc = true,
            .tab => {
                const reverse = modifiers.get(.left_shift) or modifiers.get(.right_shift);
                const inc = if (reverse) self.controls.items.len - 1 else 1;

                var nix = ix;
                if (self.controls.items[nix].is(Imtui.Controls.DialogRadio.Impl)) |s| {
                    while (true) {
                        const r = self.controls.items[nix].is(Imtui.Controls.DialogRadio.Impl) orelse break;
                        if (r.group_id != s.group_id) break;
                        nix = (nix + inc) % self.controls.items.len;
                    }
                } else {
                    nix = (nix + inc) % self.controls.items.len;
                    if (reverse and self.controls.items[nix].is(Imtui.Controls.DialogRadio.Impl) != null)
                        while (!self.controls.items[nix].is(Imtui.Controls.DialogRadio.Impl).?.selected) {
                            nix -= 1;
                        };
                }

                try self.imtui.focus(self.controls.items[nix]);
            },
            .@"return" => if (self.default_button) |db| {
                db.chosen = true;
            },
            .escape => if (self.cancel_button) |cb| {
                cb.chosen = true;
            },
            else => try self.handleAccelerator(keycode),
        }
    }

    pub fn commonMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        for (self.controls.items) |c|
            if (c.isMouseOver()) {
                return c.handleMouseDown(b, clicks, cm);
            };

        return null;
    }

    fn handleAccelerator(self: *Impl, keycode: SDL.Keycode) !void {
        for (self.controls.items) |c|
            if (c.accelGet()) |a|
                if (std.ascii.toLower(a) == @intFromEnum(keycode)) {
                    try c.accelerate();
                    return;
                };
    }

    pub fn pendingAccel(self: *Impl) ?u8 {
        defer self.pending_accel = null;
        return self.pending_accel;
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, title: []const u8, _: usize, _: usize, _: Position) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{s}", .{ "core.Dialog", title });
}

pub fn create(imtui: *Imtui, title: []const u8, height: usize, width: usize, position: Position) !Dialog {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .title = title,
    };
    d.describe(title, height, width, position);
    return .{ .impl = d };
}

pub fn end(self: Dialog) !void {
    const impl = self.impl;
    if (!impl.applied_initial_focus) {
        try impl.imtui.focus(impl.controls.items[0]);
        impl.applied_initial_focus = true;
    }

    for (impl.controls.items) |i|
        if (i.is(Imtui.Controls.DialogButton.Impl)) |b|
            b.draw();
}

pub fn groupbox(self: Dialog, title: []const u8, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8) void {
    self.impl.imtui.text_mode.box(self.impl.r1 + r1, self.impl.c1 + c1, self.impl.r1 + r2, self.impl.c1 + c2, colour);

    if (title.len > 0) {
        const start = self.impl.c1 + c1 + (c2 - c1 - title.len) / 2;
        self.impl.imtui.text_mode.paint(self.impl.r1 + r1, start - 1, self.impl.r1 + r1 + 1, start + title.len + 1, colour, 0);
        self.impl.imtui.text_mode.write(self.impl.r1 + r1, start, title);
    }
}

pub fn hrule(self: Dialog, r1: usize, c1: usize, c2: usize, colour: u8) void {
    self.impl.imtui.text_mode.paint(self.impl.r1 + r1, self.impl.c1 + c1, self.impl.r1 + r1 + 1, self.impl.c1 + c2, colour, .Horizontal);
    if (c1 == 0)
        self.impl.imtui.text_mode.draw(self.impl.r1 + r1, self.impl.c1 + c1, colour, .VerticalRight);
    if (c2 == self.impl.c2 - self.impl.c1)
        self.impl.imtui.text_mode.draw(self.impl.r1 + r1, self.impl.c1 + c2 - 1, colour, .VerticalLeft);
}

pub fn label(self: Dialog, r: usize, c: usize, l: []const u8) void {
    self.impl.imtui.text_mode.writeAccelerated(self.impl.r1 + r, self.impl.c1 + c, l, self.impl.show_acc);
    if (Imtui.Controls.acceleratorFor(l)) |accel| {
        std.debug.assert(self.impl.pending_accel == null);
        self.impl.pending_accel = accel;
    }
}

pub fn radio(self: Dialog, group_id: usize, item_id: usize, r: usize, c: usize, l: []const u8) !Imtui.Controls.DialogRadio {
    return self.impl.imtui.dialogradio(self.impl, group_id, item_id, r, c, l);
}

pub fn select(self: Dialog, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !Imtui.Controls.DialogSelect {
    return self.impl.imtui.dialogselect(self.impl, r1, c1, r2, c2, colour, selected);
}

pub fn checkbox(self: Dialog, r: usize, c: usize, l: []const u8, selected: bool) !Imtui.Controls.DialogCheckbox {
    return self.impl.imtui.dialogcheckbox(self.impl, r, c, l, selected);
}

pub fn input(self: Dialog, r: usize, c1: usize, c2: usize) !Imtui.Controls.DialogInput {
    return self.impl.imtui.dialoginput(self.impl, r, c1, c2);
}

pub fn button(self: Dialog, r: usize, c: usize, l: []const u8) !Imtui.Controls.DialogButton {
    return self.impl.imtui.dialogbutton(self.impl, r, c, l);
}
