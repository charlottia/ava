const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Dialog = @This();

imtui: *Imtui,
generation: usize,
title: []const u8,
r1: usize,
c1: usize,

controls: std.ArrayListUnmanaged(DialogControl) = .{},
controls_at: usize = undefined,

pub fn create(imtui: *Imtui, title: []const u8, height: usize, width: usize) !*Dialog {
    var d = try imtui.allocator.create(Dialog);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .title = title,
        .r1 = undefined,
        .c1 = undefined,
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

    _ = self.groupbox(self.title, self.r1, self.c1, self.r1 + height, self.c1 + width, 0x70);
    for (1..height + 1) |r| {
        self.imtui.text_mode.shadow(r, width);
        self.imtui.text_mode.shadow(r, width + 1);
    }
    for (2..width) |c|
        self.imtui.text_mode.shadow(height, c);
}

pub fn end(self: *Dialog) void {
    self.imtui.text_mode.offset_row -= self.r1;
    self.imtui.text_mode.offset_col -= self.c1;

    self.imtui.text_mode.cursor_inhibit = false;
    self.imtui.text_mode.cursor_row = self.r1 + 1;
    self.imtui.text_mode.cursor_col = self.c1 + 1;
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
};

const DialogRadio = struct {
    dialog: *Dialog,
    generation: usize,
    group_id: usize = undefined,
    item_id: usize = undefined,
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,
    selected: bool,

    fn create(dialog: *Dialog, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) !*DialogRadio {
        var b = try dialog.imtui.allocator.create(DialogRadio);
        b.* = .{
            .dialog = dialog,
            .generation = dialog.imtui.generation,
            .selected = item_id == 0,
        };
        b.describe(group_id, item_id, r, c, label);
        return b;
    }

    fn deinit(self: *DialogRadio) void {
        self.dialog.imtui.allocator.destroy(self);
    }

    fn describe(self: *DialogRadio, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) void {
        self.group_id = group_id;
        self.item_id = item_id;
        self.r = r;
        self.c = c;
        self.label = label;

        self.dialog.imtui.text_mode.write(r, c, "( ) ");
        if (self.selected)
            self.dialog.imtui.text_mode.draw(r, c + 1, 0x70, .Bullet);
        self.dialog.imtui.text_mode.writeAccelerated(r, c + 4, label, false);
    }
};

pub fn radio(self: *Dialog, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) !*DialogRadio {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try DialogRadio.create(self, group_id, item_id, r, c, label);
        try self.controls.append(self.imtui.allocator, .{ .radio = b });
        break :b b;
    } else b: {
        const b = self.controls.items[self.controls_at].radio;
        b.describe(group_id, item_id, r, c, label);
        break :b b;
    };
    self.controls_at += 1;
    return b;
}

const DialogSelect = struct {
    dialog: *Dialog,
    generation: usize,
    r1: usize = undefined,
    c1: usize = undefined,
    r2: usize = undefined,
    c2: usize = undefined,
    colour: u8 = undefined,
    _items: []const []const u8 = undefined,
    _selected_ix: usize,
    _scroll_row: usize = 0, // TODO

    fn create(dialog: *Dialog, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !*DialogSelect {
        var b = try dialog.imtui.allocator.create(DialogSelect);
        b.* = .{
            .dialog = dialog,
            .generation = dialog.imtui.generation,
            ._selected_ix = selected,
        };
        b.describe(r1, c1, r2, c2, colour);
        return b;
    }

    fn deinit(self: *DialogSelect) void {
        self.dialog.imtui.allocator.destroy(self);
    }

    fn describe(self: *DialogSelect, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8) void {
        self.r1 = r1;
        self.c1 = c1;
        self.r2 = r2;
        self.c2 = c2;
        self.colour = colour;
        self._items = &.{};

        self.dialog.imtui.text_mode.box(r1, c1, r2, c2, colour);
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
};

pub fn select(self: *Dialog, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !*DialogSelect {
    const s = if (self.controls_at == self.controls.items.len) s: {
        const s = try DialogSelect.create(self, r1, c1, r2, c2, colour, selected);
        try self.controls.append(self.imtui.allocator, .{ .select = s });
        break :s s;
    } else s: {
        const s = self.controls.items[self.controls_at].select;
        s.describe(r1, c1, r2, c2, colour);
        break :s s;
    };
    self.controls_at += 1;
    return s;
}

const DialogCheckbox = struct {
    dialog: *Dialog,
    generation: usize,
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,
    selected: bool,

    fn create(dialog: *Dialog, r: usize, c: usize, label: []const u8, selected: bool) !*DialogCheckbox {
        var b = try dialog.imtui.allocator.create(DialogCheckbox);
        b.* = .{
            .dialog = dialog,
            .generation = dialog.imtui.generation,
            .selected = selected,
        };
        b.describe(r, c, label);
        return b;
    }

    fn deinit(self: *DialogCheckbox) void {
        self.dialog.imtui.allocator.destroy(self);
    }

    fn describe(self: *DialogCheckbox, r: usize, c: usize, label: []const u8) void {
        self.r = r;
        self.c = c;
        self.label = label;

        self.dialog.imtui.text_mode.write(r, c, if (self.selected) "[X] " else "[ ] ");
        self.dialog.imtui.text_mode.writeAccelerated(r, c + 4, label, false);
    }
};

pub fn checkbox(self: *Dialog, r: usize, c: usize, label: []const u8, selected: bool) !*DialogCheckbox {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try DialogCheckbox.create(self, r, c, label, selected);
        try self.controls.append(self.imtui.allocator, .{ .checkbox = b });
        break :b b;
    } else b: {
        const b = self.controls.items[self.controls_at].checkbox;
        b.describe(r, c, label);
        break :b b;
    };
    self.controls_at += 1;
    return b;
}

const DialogInput = struct {
    dialog: *Dialog,
    generation: usize,
    r: usize = undefined,
    c1: usize = undefined,
    c2: usize = undefined,
    value: std.ArrayListUnmanaged(u8),
    // TODO: scroll_col

    fn create(dialog: *Dialog, r: usize, c1: usize, c2: usize, initial: []const u8) !*DialogInput {
        var b = try dialog.imtui.allocator.create(DialogInput);
        var value = std.ArrayListUnmanaged(u8){};
        try value.appendSlice(dialog.imtui.allocator, initial);
        b.* = .{
            .dialog = dialog,
            .generation = dialog.imtui.generation,
            .value = value,
        };
        b.describe(r, c1, c2);
        return b;
    }

    fn deinit(self: *DialogInput) void {
        self.value.deinit(self.dialog.imtui.allocator);
        self.dialog.imtui.allocator.destroy(self);
    }

    fn describe(self: *DialogInput, r: usize, c1: usize, c2: usize) void {
        self.r = r;
        self.c1 = c1;
        self.c2 = c2;

        // TODO: scroll_col/clipping
        self.dialog.imtui.text_mode.write(r, c1, self.value.items);
    }
};

pub fn input(self: *Dialog, r: usize, c1: usize, c2: usize, initial: []const u8) !*DialogInput {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try DialogInput.create(self, r, c1, c2, initial);
        try self.controls.append(self.imtui.allocator, .{ .input = b });
        break :b b;
    } else b: {
        const b = self.controls.items[self.controls_at].input;
        b.describe(r, c1, c2);
        break :b b;
    };
    self.controls_at += 1;
    return b;
}

const DialogButton = struct {
    dialog: *Dialog,
    generation: usize,
    r: usize = undefined,
    c: usize = undefined,
    label: []const u8 = undefined,

    fn create(dialog: *Dialog, r: usize, c: usize, label: []const u8) !*DialogButton {
        var b = try dialog.imtui.allocator.create(DialogButton);
        b.* = .{
            .dialog = dialog,
            .generation = dialog.imtui.generation,
        };
        b.describe(r, c, label);
        return b;
    }

    fn deinit(self: *DialogButton) void {
        self.dialog.imtui.allocator.destroy(self);
    }

    fn describe(self: *DialogButton, r: usize, c: usize, label: []const u8) void {
        self.r = r;
        self.c = c;
        self.label = label;

        self.dialog.imtui.text_mode.write(r, c, "<");
        self.dialog.imtui.text_mode.writeAccelerated(r, c + 2, self.label, false);
        self.dialog.imtui.text_mode.write(r, c + 2 + Imtui.Controls.lenWithoutAccelerators(self.label) + 1, ">");
    }
};

pub fn button(self: *Dialog, r: usize, c: usize, label: []const u8) !*DialogButton {
    const b = if (self.controls_at == self.controls.items.len) b: {
        const b = try DialogButton.create(self, r, c, label);
        try self.controls.append(self.imtui.allocator, .{ .button = b });
        break :b b;
    } else b: {
        const b = self.controls.items[self.controls_at].button;
        b.describe(r, c, label);
        break :b b;
    };
    self.controls_at += 1;
    return b;
}
