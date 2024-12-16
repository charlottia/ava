const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");
const Editor = Imtui.Controls.Editor;

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

    pub fn deinit(self: *Impl) void {
        // Controls deallocate themselves, this is just for safekeeping.
        self.controls.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn describe(self: *Impl, height: usize, width: usize) void {
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

    pub fn commonKeyPress(self: *Impl, ix: usize, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        switch (keycode) {
            .left_alt, .right_alt => self.show_acc = true,
            .tab => {
                const reverse = modifiers.get(.left_shift) or modifiers.get(.right_shift);
                const inc = if (reverse) self.controls.items.len - 1 else 1;

                // XXX XXX extended vtable for dialog controls?
                switch (self.controls.items[ix]) {
                    inline else => |c| if (@hasDecl(@TypeOf(c.*), "blur")) {
                        try c.blur();
                    },
                }

                var nix = ix;
                if (self.controls.items[nix] == .dialog_radio) {
                    const rg = self.controls.items[nix].dialog_radio.group_id;
                    while (self.controls.items[nix] == .dialog_radio and
                        self.controls.items[nix].dialog_radio.group_id == rg)
                        nix = (nix + inc) % self.controls.items.len;
                } else {
                    nix = (nix + inc) % self.controls.items.len;
                    if (reverse and self.controls.items[nix] == .dialog_radio)
                        while (!self.controls.items[nix].dialog_radio.selected) {
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
                return try c.handleMouseDown(b, clicks, cm);
            };

        return .{ .dialog = self }; // nothing matched. eat the events.
    }

    fn handleAccelerator(self: *Impl, keycode: SDL.Keycode) !void {
        for (self.controls.items) |c|
            if (c.accel()) |a|
                if (std.ascii.toLower(a) == @intFromEnum(keycode)) {
                    try c.accelerate();
                    return;
                };
    }
};

impl: *Impl,

pub fn create(imtui: *Imtui, title: []const u8, height: usize, width: usize) !Dialog {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .title = title,
    };
    d.describe(height, width);
    return .{ .impl = d };
}

pub fn end(self: Dialog) !void {
    const impl = self.impl;
    if (!impl.applied_initial_focus) {
        try impl.imtui.focus(impl.controls.items[0]);
        impl.applied_initial_focus = true;
    }

    for (impl.controls.items) |i|
        switch (i) {
            .dialog_button => |b| b.draw(),
            else => {},
        };

    // impl.imtui.text_mode.cursor_inhibit = false; // XXX
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

// pub fn select(self: Dialog, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !Imtui.Controls.DialogSelect {
//     const impl = self.impl;
//     defer impl.controls_at += 1;
//     if (impl.controls_at == impl.controls.items.len) {
//         const b = try Imtui.Controls.DialogSelect.create(impl, impl.controls_at, r1, c1, r2, c2, colour, selected);
//         try impl.controls.append(impl.imtui.allocator, .{ .select = b.impl });
//         return b;
//     } else {
//         const b = impl.controls.items[impl.controls_at].select;
//         b.describe(impl.controls_at, r1, c1, r2, c2, colour);
//         return .{ .impl = b };
//     }
// }

// pub fn checkbox(self: Dialog, r: usize, c: usize, label: []const u8, selected: bool) !Imtui.Controls.DialogCheckbox {
//     const impl = self.impl;
//     defer impl.controls_at += 1;
//     if (impl.controls_at == impl.controls.items.len) {
//         const b = try Imtui.Controls.DialogCheckbox.create(impl, impl.controls_at, r, c, label, selected);
//         try impl.controls.append(impl.imtui.allocator, .{ .checkbox = b.impl });
//         return b;
//     } else {
//         const b = impl.controls.items[impl.controls_at].checkbox;
//         b.describe(impl.controls_at, r, c, label);
//         return .{ .impl = b };
//     }
// }

// pub fn input(self: Dialog, r: usize, c1: usize, c2: usize) !Imtui.Controls.DialogInput {
//     const impl = self.impl;
//     defer impl.controls_at += 1;
//     if (impl.controls_at == impl.controls.items.len) {
//         const b = try Imtui.Controls.DialogInput.create(impl, impl.controls_at, r, c1, c2);
//         try impl.controls.append(impl.imtui.allocator, .{ .input = b.impl });
//         return b;
//     } else {
//         const b = impl.controls.items[impl.controls_at].input;
//         b.describe(impl.controls_at, r, c1, c2);
//         return .{ .impl = b };
//     }
// }

pub fn button(self: Dialog, r: usize, c: usize, label: []const u8) !Imtui.Controls.DialogButton {
    return self.impl.imtui.dialogbutton(self.impl, r, c, label);
}
