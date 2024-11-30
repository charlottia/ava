const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

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
_default_button: ?*DialogButton = undefined,
_cancel_button: ?*DialogButton = undefined,

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
    switch (keycode) {
        .left_alt, .right_alt => {
            self.alt_held = true;
            self.show_acc = true;
        },
        .tab => {
            const reverse = modifiers.get(.left_shift) or modifiers.get(.right_shift);
            const inc = if (reverse) self.controls.items.len - 1 else 1;
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
        },
        .up, .left => {
            self.controls.items[self.focus_ix].up();
        },
        .down, .right => {
            self.controls.items[self.focus_ix].down();
        },
        .space => {
            self.controls.items[self.focus_ix].space();
        },
        .@"return" => switch (self.controls.items[self.focus_ix]) {
            .button => |b| b._chosen = true,
            else => if (self._default_button) |db| {
                db._chosen = true;
            },
        },
        .escape => if (self._cancel_button) |cb| {
            cb._chosen = true;
        },
        else => if (self.alt_held)
            self.handleAccelerator(keycode)
        else switch (self.controls.items[self.focus_ix]) {
            // select box, input box need text input delivered to them
            // otherwise it might be an accelerator
            inline .select, .input => |s| try s.handleKeyPress(keycode, modifiers),
            else => self.handleAccelerator(keycode),
        },
    }
}

fn handleAccelerator(self: *Dialog, keycode: SDL.Keycode) void {
    for (self.controls.items) |c|
        if (c._accel()) |a| {
            if (std.ascii.toLower(a) == @intFromEnum(keycode))
                c.focus();
        };
}

pub fn handleKeyUp(self: *Dialog, keycode: SDL.Keycode) !void {
    if ((keycode == .left_alt or keycode == .right_alt) and self.alt_held)
        self.alt_held = false;
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
    radio: *DialogRadio,
    select: *DialogSelect,
    checkbox: *DialogCheckbox,
    input: *DialogInput,
    button: *DialogButton,

    fn deinit(self: DialogControl) void {
        switch (self) {
            inline else => |c| c.deinit(),
        }
    }

    fn up(self: DialogControl) void {
        switch (self) {
            inline else => |c| if (@hasDecl(@TypeOf(c.*), "up")) {
                c.up();
            },
        }
    }

    fn down(self: DialogControl) void {
        switch (self) {
            inline else => |c| if (@hasDecl(@TypeOf(c.*), "down")) {
                c.down();
            },
        }
    }

    fn space(self: DialogControl) void {
        switch (self) {
            inline else => |c| if (@hasDecl(@TypeOf(c.*), "space")) {
                c.space();
            },
        }
    }

    fn _accel(self: DialogControl) ?u8 {
        return switch (self) {
            inline else => |c| c._accel,
        };
    }

    fn focus(self: DialogControl) void {
        switch (self) {
            inline else => |c| c.focus(),
        }
    }
};

const DialogRadio = struct {
    dialog: *Dialog,
    ix: usize = undefined,
    generation: usize,
    group_id: usize = undefined,
    item_id: usize = undefined,
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,
    _accel: ?u8 = undefined,
    _selected: bool,
    _selected_read: bool = false,

    fn create(dialog: *Dialog, ix: usize, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) !*DialogRadio {
        var b = try dialog.imtui.allocator.create(DialogRadio);
        b.* = .{
            .dialog = dialog,
            .generation = dialog.imtui.generation,
            ._selected = item_id == 0,
        };
        b.describe(ix, group_id, item_id, r, c, label);
        return b;
    }

    fn deinit(self: *DialogRadio) void {
        self.dialog.imtui.allocator.destroy(self);
    }

    fn describe(self: *DialogRadio, ix: usize, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) void {
        self.ix = ix;
        self.group_id = group_id;
        self.item_id = item_id;
        self.r = r;
        self.c = c;
        self.label = label;
        self._accel = Imtui.Controls.acceleratorFor(label);

        self.dialog.imtui.text_mode.write(r, c, "( ) ");
        if (self._selected)
            self.dialog.imtui.text_mode.draw(r, c + 1, 0x70, .Bullet);
        self.dialog.imtui.text_mode.writeAccelerated(r, c + 4, label, self.dialog.show_acc);

        if (self.dialog.focus_ix == ix) {
            self.dialog.imtui.text_mode.cursor_row = self.dialog.imtui.text_mode.offset_row + r;
            self.dialog.imtui.text_mode.cursor_col = self.dialog.imtui.text_mode.offset_col + c + 1;
        }
    }

    fn up(self: *DialogRadio) void {
        std.debug.assert(self._selected);
        self._selected = false;
        self.findKin(self.item_id -% 1).select();
    }

    fn down(self: *DialogRadio) void {
        std.debug.assert(self._selected);
        self._selected = false;
        self.findKin(self.item_id + 1).select();
    }

    fn select(self: *DialogRadio) void {
        self._selected = true;
        self._selected_read = false;
        self.dialog.focus_ix = self.ix;
    }

    fn focus(self: *DialogRadio) void {
        if (self._selected) return;

        for (self.dialog.controls.items) |c|
            switch (c) {
                .radio => |b| if (b.group_id == self.group_id) {
                    b._selected = false;
                },
                else => {},
            };

        self.select();
    }

    pub fn selected(self: *DialogRadio) bool {
        defer self._selected_read = true;
        return self._selected and !self._selected_read;
    }

    fn findKin(self: *DialogRadio, id: usize) *DialogRadio {
        var zero: ?*DialogRadio = null;
        var high: ?*DialogRadio = null;
        for (self.dialog.controls.items) |c|
            switch (c) {
                .radio => |b| if (b.group_id == self.group_id) {
                    if (b.item_id == 0)
                        zero = b
                    else if (b.item_id == id)
                        return b
                    else if (high) |h|
                        high = if (b.item_id > h.item_id) b else h
                    else
                        high = b;
                },
                else => {},
            };
        return if (id == std.math.maxInt(usize)) high.? else zero.?;
    }
};

pub fn radio(self: *Dialog, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) !*DialogRadio {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try DialogRadio.create(self, self.controls_at, group_id, item_id, r, c, label);
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

const DialogSelect = struct {
    dialog: *Dialog,
    ix: usize = undefined,
    generation: usize,
    r1: usize = undefined,
    c1: usize = undefined,
    r2: usize = undefined,
    c2: usize = undefined,
    colour: u8 = undefined,
    _items: []const []const u8 = undefined,
    _accel: ?u8 = undefined,
    _selected_ix: usize,
    _scroll_row: usize = 0,

    fn create(dialog: *Dialog, ix: usize, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !*DialogSelect {
        var b = try dialog.imtui.allocator.create(DialogSelect);
        b.* = .{
            .dialog = dialog,
            .generation = dialog.imtui.generation,
            ._selected_ix = selected,
        };
        b.describe(ix, r1, c1, r2, c2, colour);
        return b;
    }

    fn deinit(self: *DialogSelect) void {
        self.dialog.imtui.allocator.destroy(self);
    }

    fn describe(self: *DialogSelect, ix: usize, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8) void {
        self.ix = ix;
        self.r1 = r1;
        self.c1 = c1;
        self.r2 = r2;
        self.c2 = c2;
        self.colour = colour;
        self._items = &.{};
        self._accel = null;

        self.dialog.imtui.text_mode.box(r1, c1, r2, c2, colour);

        if (self.dialog.focus_ix == ix) {
            self.dialog.imtui.text_mode.cursor_row = self.dialog.imtui.text_mode.offset_row + r1 + 1 + self._selected_ix - self._scroll_row;
            self.dialog.imtui.text_mode.cursor_col = self.dialog.imtui.text_mode.offset_col + c1 + 2;
        }
    }

    pub fn accel(self: *DialogSelect, key: u8) void {
        self._accel = key;
    }

    pub fn items(self: *DialogSelect, it: []const []const u8) void {
        self._items = it;
    }

    pub fn end(self: *DialogSelect) void {
        for (self._items[self._scroll_row..], 0..) |it, ix| {
            const r = self.r1 + 1 + ix;
            if (r == self.r2 - 1) break;
            if (ix + self._scroll_row == self._selected_ix)
                self.dialog.imtui.text_mode.paint(r, self.c1 + 1, r + 1, self.c2 - 1, ((self.colour & 0x0f) << 4) | ((self.colour & 0xf0) >> 4), .Blank);
            self.dialog.imtui.text_mode.write(r, self.c1 + 2, it);
        }
        _ = self.dialog.imtui.text_mode.vscrollbar(self.c2 - 1, self.r1 + 1, self.r2 - 1, self._scroll_row, self._items.len -| 8);
    }

    pub fn focus(self: *DialogSelect) void {
        self.dialog.focus_ix = self.ix;
    }

    pub fn value(self: *DialogSelect, ix: usize) void {
        self._selected_ix = ix;
        if (self._scroll_row > ix)
            self._scroll_row = ix
        else if (ix >= self._scroll_row + self.r2 - self.r1 - 2)
            self._scroll_row = ix + self.r1 + 3 - self.r2;
    }

    fn up(self: *DialogSelect) void {
        self.value(self._selected_ix -| 1);
    }

    fn down(self: *DialogSelect) void {
        self.value(@min(self._items.len - 1, self._selected_ix + 1));
    }

    fn handleKeyPress(self: *DialogSelect, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        _ = modifiers;

        if (@intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.a) and
            @intFromEnum(keycode) <= @intFromEnum(SDL.Keycode.z))
        {
            // advance to next item starting with pressed key (if any)
            var next = (self._selected_ix + 1) % self._items.len;
            while (next != self._selected_ix) : (next = (next + 1) % self._items.len) {
                // SDLK_a..SDLK_z correspond to 'a'..'z' in ASCII.
                if (std.ascii.toLower(self._items[next][0]) == @intFromEnum(keycode)) {
                    self.value(next);
                    return;
                }
            }
            return;
        }
    }
};

pub fn select(self: *Dialog, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !*DialogSelect {
    const s = if (self.controls_at == self.controls.items.len) s: {
        const s = try DialogSelect.create(self, self.controls_at, r1, c1, r2, c2, colour, selected);
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

const DialogCheckbox = struct {
    dialog: *Dialog,
    generation: usize,
    ix: usize = undefined,
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,
    _accel: ?u8 = undefined,

    selected: bool,
    _changed: bool = false,

    fn create(dialog: *Dialog, ix: usize, r: usize, c: usize, label: []const u8, selected: bool) !*DialogCheckbox {
        var b = try dialog.imtui.allocator.create(DialogCheckbox);
        b.* = .{
            .dialog = dialog,
            .generation = dialog.imtui.generation,
            .selected = selected,
        };
        b.describe(ix, r, c, label);
        return b;
    }

    fn deinit(self: *DialogCheckbox) void {
        self.dialog.imtui.allocator.destroy(self);
    }

    fn describe(self: *DialogCheckbox, ix: usize, r: usize, c: usize, label: []const u8) void {
        self.ix = ix;
        self.r = r;
        self.c = c;
        self.label = label;
        self._accel = Imtui.Controls.acceleratorFor(label);

        self.dialog.imtui.text_mode.write(r, c, if (self.selected) "[X] " else "[ ] ");
        self.dialog.imtui.text_mode.writeAccelerated(r, c + 4, label, self.dialog.show_acc);

        if (self.dialog.focus_ix == self.dialog.controls_at) {
            self.dialog.imtui.text_mode.cursor_row = self.dialog.imtui.text_mode.offset_row + r;
            self.dialog.imtui.text_mode.cursor_col = self.dialog.imtui.text_mode.offset_col + c + 1;
        }
    }

    fn up(self: *DialogCheckbox) void {
        self._changed = !self.selected;
        self.selected = true;
    }

    fn down(self: *DialogCheckbox) void {
        self._changed = self.selected;
        self.selected = false;
    }

    fn space(self: *DialogCheckbox) void {
        self._changed = true;
        self.selected = !self.selected;
    }

    pub fn focus(self: *DialogCheckbox) void {
        self.space();
        self.dialog.focus_ix = self.ix;
    }

    pub fn changed(self: *DialogCheckbox) ?bool {
        defer self._changed = false;
        return if (self._changed) self.selected else null;
    }
};

pub fn checkbox(self: *Dialog, r: usize, c: usize, label: []const u8, selected: bool) !*DialogCheckbox {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try DialogCheckbox.create(self, self.controls_at, r, c, label, selected);
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

const DialogInput = struct {
    dialog: *Dialog,
    generation: usize,
    ix: usize = undefined,
    r: usize = undefined,
    c1: usize = undefined,
    c2: usize = undefined,
    _accel: ?u8 = undefined,

    value: std.ArrayList(u8),
    initted: bool = false,
    // TODO: scroll_col

    fn create(dialog: *Dialog, ix: usize, r: usize, c1: usize, c2: usize) !*DialogInput {
        var b = try dialog.imtui.allocator.create(DialogInput);
        b.* = .{
            .dialog = dialog,
            .generation = dialog.imtui.generation,
            .value = std.ArrayList(u8).init(dialog.imtui.allocator),
        };
        b.describe(ix, r, c1, c2);
        return b;
    }

    fn deinit(self: *DialogInput) void {
        self.value.deinit();
        self.dialog.imtui.allocator.destroy(self);
    }

    fn describe(self: *DialogInput, ix: usize, r: usize, c1: usize, c2: usize) void {
        self.ix = ix;
        self.r = r;
        self.c1 = c1;
        self.c2 = c2;
        self._accel = null;

        // TODO: scroll_col/clipping
        self.dialog.imtui.text_mode.write(r, c1, self.value.items);

        if (self.dialog.focus_ix == self.dialog.controls_at) {
            self.dialog.imtui.text_mode.cursor_row = self.dialog.imtui.text_mode.offset_row + r;
            self.dialog.imtui.text_mode.cursor_col = self.dialog.imtui.text_mode.offset_col + c1;
        }
    }

    pub fn accel(self: *DialogInput, key: u8) void {
        self._accel = key;
    }

    pub fn initial(self: *DialogInput) ?*std.ArrayList(u8) {
        if (self.initted) return null;
        self.initted = true;
        return &self.value;
    }

    pub fn focus(self: *DialogInput) void {
        self.dialog.focus_ix = self.ix;
    }

    pub fn handleKeyPress(self: *DialogInput, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        _ = self;
        _ = keycode;
        _ = modifiers;
    }
};

pub fn input(self: *Dialog, r: usize, c1: usize, c2: usize) !*DialogInput {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try DialogInput.create(self, self.controls_at, r, c1, c2);
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

const DialogButton = struct {
    dialog: *Dialog,
    ix: usize = undefined,
    generation: usize,
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,
    _accel: ?u8 = undefined,

    _chosen: bool = false,

    fn create(dialog: *Dialog, ix: usize, r: usize, c: usize, label: []const u8) !*DialogButton {
        var b = try dialog.imtui.allocator.create(DialogButton);
        b.* = .{
            .dialog = dialog,
            .generation = dialog.imtui.generation,
        };
        b.describe(ix, r, c, label);
        return b;
    }

    fn deinit(self: *DialogButton) void {
        self.dialog.imtui.allocator.destroy(self);
    }

    fn describe(self: *DialogButton, ix: usize, r: usize, c: usize, label: []const u8) void {
        self.ix = ix;
        self.r = r;
        self.c = c;
        self.label = label;
        self._accel = Imtui.Controls.acceleratorFor(label);
    }

    fn draw(self: *const DialogButton) void {
        const colour: u8 = if (self.dialog.focus_ix == self.ix or
            (self.dialog._default_button == self and self.dialog.controls.items[self.dialog.focus_ix] != .button))
            0x7f
        else
            0x70;

        self.dialog.imtui.text_mode.paint(self.r, self.c, self.r + 1, self.c + 1, colour, '<');
        self.dialog.imtui.text_mode.writeAccelerated(self.r, self.c + 2, self.label, self.dialog.show_acc);
        const ec = self.c + 2 + Imtui.Controls.lenWithoutAccelerators(self.label) + 1;
        self.dialog.imtui.text_mode.paint(self.r, ec, self.r + 1, ec + 1, colour, '>');

        if (self.dialog.focus_ix == self.ix) {
            self.dialog.imtui.text_mode.cursor_row = self.dialog.imtui.text_mode.offset_row + self.r;
            self.dialog.imtui.text_mode.cursor_col = self.dialog.imtui.text_mode.offset_col + self.c + 2;
        }
    }

    pub fn default(self: *DialogButton) void {
        self.dialog._default_button = self;
    }

    pub fn cancel(self: *DialogButton) void {
        self.dialog._cancel_button = self;
    }

    pub fn focus(self: *DialogButton) void {
        self.dialog.focus_ix = self.ix;
        self._chosen = true;
    }

    pub fn chosen(self: *DialogButton) bool {
        defer self._chosen = false;
        return self._chosen;
    }
};

pub fn button(self: *Dialog, r: usize, c: usize, label: []const u8) !*DialogButton {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try DialogButton.create(self, self.controls_at, r, c, label);
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
