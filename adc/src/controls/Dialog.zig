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

    controls: std.ArrayListUnmanaged(DialogControl) = .{},
    controls_at: usize = undefined,
    focus_ix: usize = 0,
    show_acc: bool = false,
    default_button: ?*Imtui.Controls.DialogButton.Impl = undefined,
    cancel_button: ?*Imtui.Controls.DialogButton.Impl = undefined,

    pub fn deinit(self: *Impl) void {
        // Controls deallocate themselves, this is just for safekeeping.
        self.controls.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn describe(self: *Impl, height: usize, width: usize) void {
        self.r1 = (@TypeOf(self.imtui.text_mode).H - height) / 2;
        self.c1 = (@TypeOf(self.imtui.text_mode).W - width) / 2;
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

    pub fn handleKeyPress(self: *Impl, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        // XXX this return/handled thing is *really* ugly and commits the sin of
        // high cognitive load.

        switch (keycode) {
            .left_alt, .right_alt => {
                self.show_acc = true;
                return;
            },
            .tab => {
                const reverse = modifiers.get(.left_shift) or modifiers.get(.right_shift);
                const inc = if (reverse) self.controls.items.len - 1 else 1;
                try self.controls.items[self.focus_ix].blur();
                // if (self.controls.items[self.focus_ix] == .radio) {
                //     const rg = self.controls.items[self.focus_ix].radio.group_id;
                //     while (self.controls.items[self.focus_ix] == .radio and
                //         self.controls.items[self.focus_ix].radio.group_id == rg)
                //         self.focus_ix = (self.focus_ix + inc) % self.controls.items.len;
                // } else {
                self.focus_ix = (self.focus_ix + inc) % self.controls.items.len;
                // if (reverse and self.controls.items[self.focus_ix] == .radio)
                //     while (!self.controls.items[self.focus_ix].radio.selected) {
                //         self.focus_ix -= 1;
                //     };
                // }
                return;
            },
            .up, .left => {
                if (self.controls.items[self.focus_ix].up())
                    return;
            },
            .down, .right => {
                if (self.controls.items[self.focus_ix].down())
                    return;
            },
            .space => {
                if (self.controls.items[self.focus_ix].space())
                    return;
            },
            .@"return" => {
                switch (self.controls.items[self.focus_ix]) {
                    .button => |b| b.chosen = true,
                    // else => if (self.default_button) |db| {
                    //     db.chosen = true;
                    // },
                }
                return;
            },
            .escape => {
                if (self.cancel_button) |cb|
                    cb.chosen = true;
                return;
            },
            else => if (self.imtui.alt_held) {
                self.handleAccelerator(keycode);
                return;
            } else switch (self.controls.items[self.focus_ix]) {
                // select box, input box need text input delivered to them
                // otherwise it might be an accelerator
                // .select, .input => {
                //     // fall through
                // },
                else => {
                    self.handleAccelerator(keycode);
                    return;
                },
            },
        }

        // The above nonsense is entirely so non-"overridden" up()/down()/space()
        // correctly make their way to select/input.  Do better.
        switch (self.controls.items[self.focus_ix]) {
            // inline .select, .input => |s| try s.handleKeyPress(keycode, modifiers),
            else => {},
        }
    }

    fn handleAccelerator(self: *Impl, keycode: SDL.Keycode) void {
        for (self.controls.items) |c|
            if (c.accel()) |a| {
                if (std.ascii.toLower(a) == @intFromEnum(keycode))
                    c.accelerate();
            };
    }

    const DialogControl = union(enum) {
        // radio: *Imtui.Controls.DialogRadio.Impl,
        // select: *Imtui.Controls.DialogSelect.Impl,
        // checkbox: *Imtui.Controls.DialogCheckbox.Impl,
        // input: *Imtui.Controls.DialogInput.Impl,
        button: *Imtui.Controls.DialogButton.Impl,

        fn deinit(self: DialogControl) void {
            switch (self) {
                inline else => |c| c.deinit(),
            }
        }

        fn up(self: DialogControl) bool {
            switch (self) {
                inline else => |c| if (@hasDecl(@TypeOf(c.*), "up")) {
                    c.up();
                    return true;
                },
            }
            return false;
        }

        fn down(self: DialogControl) bool {
            switch (self) {
                inline else => |c| if (@hasDecl(@TypeOf(c.*), "down")) {
                    c.down();
                    return true;
                },
            }
            return false;
        }

        fn space(self: DialogControl) bool {
            switch (self) {
                inline else => |c| if (@hasDecl(@TypeOf(c.*), "space")) {
                    c.space();
                    return true;
                },
            }
            return false;
        }

        fn handleKeyUp(self: DialogControl, keycode: SDL.Keycode) !void {
            switch (self) {
                inline else => |c| if (@hasDecl(@TypeOf(c.*), "handleKeyUp")) {
                    return c.handleKeyUp(keycode);
                },
            }
        }

        fn accel(self: DialogControl) ?u8 {
            return switch (self) {
                inline else => |c| c.accel,
            };
        }

        fn accelerate(self: DialogControl) void {
            switch (self) {
                inline else => |c| c.accelerate(),
            }
        }

        fn blur(self: DialogControl) !void {
            switch (self) {
                inline else => |c| if (@hasDecl(@TypeOf(c.*), "blur")) {
                    return c.blur();
                },
            }
        }

        fn handleMouseDown(self: DialogControl, b: SDL.MouseButton, clicks: u8, cm: bool) !void {
            switch (self) {
                inline else => |c| return c.handleMouseDown(b, clicks, cm),
            }
        }

        fn handleMouseDrag(self: DialogControl, b: SDL.MouseButton) !void {
            switch (self) {
                inline else => |c| if (@hasDecl(@TypeOf(c.*), "handleMouseDrag")) {
                    return c.handleMouseDrag(b);
                },
            }
        }

        fn handleMouseUp(self: DialogControl, b: SDL.MouseButton, clicks: u8) !void {
            switch (self) {
                inline else => |c| if (@hasDecl(@TypeOf(c.*), "handleMouseUp")) {
                    return c.handleMouseUp(b, clicks);
                },
            }
        }
    };
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

pub fn end(self: Dialog) void {
    for (self.impl.controls.items) |i|
        switch (i) {
            .button => |b| b.draw(),
            // else => {},
        };

    self.impl.imtui.text_mode.cursor_inhibit = false;
}

pub fn groupbox(self: Dialog, title: []const u8, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8) void {
    self.impl.imtui.text_mode.box(self.impl.r1 + r1, self.impl.c1 + c1, self.impl.r1 + r2, self.impl.c1 + c2, colour);

    const start = self.impl.c1 + c1 + (c2 - c1 - title.len) / 2;
    self.impl.imtui.text_mode.paint(self.impl.r1 + r1, start - 1, self.impl.r1 + r1 + 1, start + title.len + 1, colour, 0);
    self.impl.imtui.text_mode.write(self.impl.r1 + r1, start, title);
}

// pub fn radio(self: Dialog, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) !Imtui.Controls.DialogRadio {
//     const impl = self.impl;
//     defer impl.controls_at += 1;
//     if (impl.controls_at == impl.controls.items.len) {
//         const b = try Imtui.Controls.DialogRadio.create(impl, impl.controls_at, group_id, item_id, r, c, label);
//         try impl.controls.append(impl.imtui.allocator, .{ .radio = b.impl });
//         return b;
//     } else {
//         const b = impl.controls.items[impl.controls_at].radio;
//         b.describe(impl.controls_at, group_id, item_id, r, c, label);
//         return .{ .impl = b };
//     }
// }

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
