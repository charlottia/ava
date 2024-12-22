const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Dialog = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,
    title: []const u8,
    r1: usize = undefined,
    c1: usize = undefined,

    applied_initial_focus: bool = false,
    controls: std.ArrayListUnmanaged(Imtui.Control) = .{},
    controls_at: usize = undefined,
    show_acc: bool = false,
    default_button: ?*Imtui.Controls.DialogButton.Impl = undefined,
    cancel_button: ?*Imtui.Controls.DialogButton.Impl = undefined,

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .orphan = true,
                .no_mouse = true,
                .no_key = true,
                .deinit = deinit,
                .generationGet = generationGet,
                .generationSet = generationSet,
            },
        };
    }

    pub fn describe(self: *Impl, _: []const u8, height: usize, width: usize) void {
        self.r1 = (self.imtui.text_mode.H - height) / 2;
        self.c1 = (self.imtui.text_mode.W - width) / 2;
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

    fn generationGet(ptr: *const anyopaque) usize {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.generation;
    }

    fn generationSet(ptr: *anyopaque, n: usize) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.generation = n;
    }

    pub fn commonKeyPress(self: *Impl, ix: usize, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        switch (keycode) {
            .left_alt, .right_alt => self.show_acc = true,
            .tab => {
                // HACK but one-off for now:
                if (self.controls.items[ix].is(Imtui.Controls.DialogInput.Impl)) |di|
                    di.blur();

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

                // HACK but one-off for now:
                if (self.controls.items[nix].is(Imtui.Controls.DialogInput.Impl)) |di|
                    try di.focusAndSelectAll()
                else
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
                return try c.handleMouseDown(b, clicks, cm);
            };

        return self.control(); // stop the Editor from getting these
    }

    fn handleAccelerator(self: *Impl, keycode: SDL.Keycode) !void {
        for (self.controls.items) |c|
            if (c.accelGet()) |a|
                if (std.ascii.toLower(a) == @intFromEnum(keycode)) {
                    try c.accelerate();
                    return;
                };
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, title: []const u8, _: usize, _: usize) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{s}", .{ "core.Dialog", title });
}

pub fn create(imtui: *Imtui, title: []const u8, height: usize, width: usize) !Dialog {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .title = title,
    };
    d.describe(title, height, width);
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

    const start = self.impl.c1 + c1 + (c2 - c1 - title.len) / 2;
    self.impl.imtui.text_mode.paint(self.impl.r1 + r1, start - 1, self.impl.r1 + r1 + 1, start + title.len + 1, colour, 0);
    self.impl.imtui.text_mode.write(self.impl.r1 + r1, start, title);
}

pub fn radio(self: Dialog, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) !Imtui.Controls.DialogRadio {
    return self.impl.imtui.dialogradio(self.impl, group_id, item_id, r, c, label);
}

pub fn select(self: Dialog, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !Imtui.Controls.DialogSelect {
    return self.impl.imtui.dialogselect(self.impl, r1, c1, r2, c2, colour, selected);
}

pub fn checkbox(self: Dialog, r: usize, c: usize, label: []const u8, selected: bool) !Imtui.Controls.DialogCheckbox {
    return self.impl.imtui.dialogcheckbox(self.impl, r, c, label, selected);
}

pub fn input(self: Dialog, r: usize, c1: usize, c2: usize) !Imtui.Controls.DialogInput {
    return self.impl.imtui.dialoginput(self.impl, r, c1, c2);
}

pub fn button(self: Dialog, r: usize, c: usize, label: []const u8) !Imtui.Controls.DialogButton {
    return self.impl.imtui.dialogbutton(self.impl, r, c, label);
}
