const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");
const Editor = Imtui.Controls.Editor;

const Dialog = @This();

imtui: *Imtui,
generation: usize,
title: []const u8,
r1: usize = undefined,
c1: usize = undefined,

controls: std.ArrayListUnmanaged(DialogControl) = .{},
controls_at: usize = undefined,
focus_ix: usize = 0,
alt_held: bool = false,
show_acc: bool = false,
_default_button: ?*Imtui.Controls.DialogButton = undefined,
_cancel_button: ?*Imtui.Controls.DialogButton = undefined,
mouse_event_target: ?DialogControl = null,

pub fn create(imtui: *Imtui, title: []const u8, height: usize, width: usize) !*Dialog {
    var d = try imtui.allocator.create(Dialog);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .title = title,
    };
    d.describe(height, width);
    return d;
}

pub fn deinit(self: *Dialog) void {
    for (self.controls.items) |c|
        c.deinit();
    self.controls.deinit(self.imtui.allocator);
    self.imtui.allocator.destroy(self);
}

pub fn describe(self: *Dialog, height: usize, width: usize) void {
    self.r1 = (@TypeOf(self.imtui.text_mode).H - height) / 2;
    self.c1 = (@TypeOf(self.imtui.text_mode).W - width) / 2;
    self.controls_at = 0;
    self._default_button = null;
    self._cancel_button = null;

    self.imtui.text_mode.offset_row += self.r1;
    self.imtui.text_mode.offset_col += self.c1;
    _ = self.groupbox(self.title, 0, 0, height, width, 0x70);
    for (1..height + 1) |r| {
        self.imtui.text_mode.shadow(r, width);
        self.imtui.text_mode.shadow(r, width + 1);
    }
    for (2..width) |c|
        self.imtui.text_mode.shadow(height, c);
}

pub fn end(self: *Dialog) void {
    for (self.controls.items) |i|
        switch (i) {
            .button => |b| b.draw(),
            else => {},
        };

    self.imtui.text_mode.offset_row -= self.r1;
    self.imtui.text_mode.offset_col -= self.c1;

    self.imtui.text_mode.cursor_inhibit = false;
}

pub fn handleKeyPress(self: *Dialog, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    // XXX this return/handled thing is *really* ugly and commits the sin of
    // high cognitive load.

    switch (keycode) {
        .left_alt, .right_alt => {
            self.alt_held = true;
            self.show_acc = true;
            return;
        },
        .tab => {
            const reverse = modifiers.get(.left_shift) or modifiers.get(.right_shift);
            const inc = if (reverse) self.controls.items.len - 1 else 1;
            try self.controls.items[self.focus_ix].blur();
            if (self.controls.items[self.focus_ix] == .radio) {
                const rg = self.controls.items[self.focus_ix].radio.group_id;
                while (self.controls.items[self.focus_ix] == .radio and
                    self.controls.items[self.focus_ix].radio.group_id == rg)
                    self.focus_ix = (self.focus_ix + inc) % self.controls.items.len;
            } else {
                self.focus_ix = (self.focus_ix + inc) % self.controls.items.len;
                if (reverse and self.controls.items[self.focus_ix] == .radio)
                    while (!self.controls.items[self.focus_ix].radio._selected) {
                        self.focus_ix -= 1;
                    };
            }
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
                .button => |b| b._chosen = true,
                else => if (self._default_button) |db| {
                    db._chosen = true;
                },
            }
            return;
        },
        .escape => {
            if (self._cancel_button) |cb|
                cb._chosen = true;
            return;
        },
        else => if (self.alt_held) {
            self.handleAccelerator(keycode);
            return;
        } else switch (self.controls.items[self.focus_ix]) {
            // select box, input box need text input delivered to them
            // otherwise it might be an accelerator
            .select, .input => {
                // fall through
            },
            else => {
                self.handleAccelerator(keycode);
                return;
            },
        },
    }

    // The above nonsense is entirely so non-"overridden" up()/down()/space()
    // correctly make their way to select/input.  Do better.
    switch (self.controls.items[self.focus_ix]) {
        inline .select, .input => |s| try s.handleKeyPress(keycode, modifiers),
        else => {},
    }
}

fn handleAccelerator(self: *Dialog, keycode: SDL.Keycode) void {
    for (self.controls.items) |c|
        if (c._accel()) |a| {
            if (std.ascii.toLower(a) == @intFromEnum(keycode))
                c.accelerate();
        };
}

pub fn handleKeyUp(self: *Dialog, keycode: SDL.Keycode) !void {
    if ((keycode == .left_alt or keycode == .right_alt) and self.alt_held)
        self.alt_held = false;

    try self.controls.items[self.focus_ix].handleKeyUp(keycode);
}

pub fn handleMouseDown(self: *Dialog, b: SDL.MouseButton, clicks: u8, cm: bool) !void {
    if (cm) {
        if (self.mouse_event_target) |target|
            try target.handleMouseDown(b, clicks, true);
        return;
    }

    for (self.controls.items) |c|
        switch (c) {
            inline else => |i| if (i.mouseIsOver()) {
                try i.handleMouseDown(b, clicks, false);
                self.mouse_event_target = c;
                return;
            },
        };
}

pub fn handleMouseDrag(self: *Dialog, b: SDL.MouseButton) !void {
    if (self.mouse_event_target) |target|
        try target.handleMouseDrag(b);
}

pub fn handleMouseUp(self: *Dialog, b: SDL.MouseButton, clicks: u8) !void {
    if (self.mouse_event_target) |target|
        try target.handleMouseUp(b, clicks);

    self.mouse_event_target = null;
}

pub const Groupbox = struct {
    imtui: *Imtui,

    offset_row: usize,
    offset_col: usize,

    pub fn end(self: Groupbox) void {
        self.imtui.text_mode.offset_row -= self.offset_row;
        self.imtui.text_mode.offset_col -= self.offset_col;
    }
};

pub fn groupbox(self: *Dialog, title: []const u8, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8) Groupbox {
    self.imtui.text_mode.box(r1, c1, r2, c2, colour);

    const start = c1 + (c2 - c1 - title.len) / 2;
    self.imtui.text_mode.paint(r1, start - 1, r1 + 1, start + title.len + 1, colour, 0);
    self.imtui.text_mode.write(r1, start, title);

    self.imtui.text_mode.offset_row += r1;
    self.imtui.text_mode.offset_col += c1;
    return .{
        .imtui = self.imtui,
        .offset_row = r1,
        .offset_col = c1,
    };
}

const DialogControl = union(enum) {
    radio: *Imtui.Controls.DialogRadio,
    select: *Imtui.Controls.DialogSelect,
    checkbox: *Imtui.Controls.DialogCheckbox,
    input: *Imtui.Controls.DialogInput,
    button: *Imtui.Controls.DialogButton,

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

    fn _accel(self: DialogControl) ?u8 {
        return switch (self) {
            inline else => |c| c._accel,
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

pub fn radio(self: *Dialog, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) !*Imtui.Controls.DialogRadio {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try Imtui.Controls.DialogRadio.create(self, self.controls_at, group_id, item_id, r, c, label);
        try self.controls.append(self.imtui.allocator, .{ .radio = b });
        break :b b;
    } else b: {
        const b = self.controls.items[self.controls_at].radio;
        b.describe(self.controls_at, group_id, item_id, r, c, label);
        break :b b;
    };
    self.controls_at += 1;
    return b;
}

pub fn select(self: *Dialog, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !*Imtui.Controls.DialogSelect {
    const s = if (self.controls_at == self.controls.items.len) s: {
        const s = try Imtui.Controls.DialogSelect.create(self, self.controls_at, r1, c1, r2, c2, colour, selected);
        try self.controls.append(self.imtui.allocator, .{ .select = s });
        break :s s;
    } else s: {
        const s = self.controls.items[self.controls_at].select;
        s.describe(self.controls_at, r1, c1, r2, c2, colour);
        break :s s;
    };
    self.controls_at += 1;
    return s;
}

pub fn checkbox(self: *Dialog, r: usize, c: usize, label: []const u8, selected: bool) !*Imtui.Controls.DialogCheckbox {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try Imtui.Controls.DialogCheckbox.create(self, self.controls_at, r, c, label, selected);
        try self.controls.append(self.imtui.allocator, .{ .checkbox = b });
        break :b b;
    } else b: {
        const b = self.controls.items[self.controls_at].checkbox;
        b.describe(self.controls_at, r, c, label);
        break :b b;
    };
    self.controls_at += 1;
    return b;
}

pub fn input(self: *Dialog, r: usize, c1: usize, c2: usize) !*Imtui.Controls.DialogInput {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try Imtui.Controls.DialogInput.create(self, self.controls_at, r, c1, c2);
        try self.controls.append(self.imtui.allocator, .{ .input = b });
        break :b b;
    } else b: {
        const b = self.controls.items[self.controls_at].input;
        b.describe(self.controls_at, r, c1, c2);
        break :b b;
    };
    self.controls_at += 1;
    return b;
}

pub fn button(self: *Dialog, r: usize, c: usize, label: []const u8) !*Imtui.Controls.DialogButton {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try Imtui.Controls.DialogButton.create(self, self.controls_at, r, c, label);
        try self.controls.append(self.imtui.allocator, .{ .button = b });
        break :b b;
    } else b: {
        const b = self.controls.items[self.controls_at].button;
        b.describe(self.controls_at, r, c, label);
        break :b b;
    };
    self.controls_at += 1;
    return b;
}
