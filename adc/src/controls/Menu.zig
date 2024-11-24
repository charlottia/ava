const std = @import("std");

const Imtui = @import("../Imtui.zig");

const Menu = @This();

imtui: *Imtui,
generation: usize,
r: usize = undefined,
c1: usize = undefined,
c2: usize = undefined,
label: []const u8 = undefined,
index: usize = undefined,
width: usize = undefined,
menu_c1: usize = undefined,
menu_c2: usize = undefined,

menu_items: std.ArrayListUnmanaged(?*Imtui.Controls.MenuItem) = .{},
menu_items_at: usize = undefined,

pub fn create(imtui: *Imtui, r: usize, c: usize, label: []const u8, index: usize, width: usize) !*Menu {
    var m = try imtui.allocator.create(Menu);
    m.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
    };
    m.describe(r, c, label, index, width);
    return m;
}

pub fn describe(self: *Menu, r: usize, c: usize, label: []const u8, index: usize, width: usize) void {
    self.r = r;
    self.c1 = c;
    self.c2 = c + Imtui.Controls.lenWithoutAccelerators(label) + 2;
    self.label = label;
    self.index = index;
    self.width = width;

    self.menu_c1 = c - 1;
    if (self.menu_c1 + self.width + 3 > 77) // XXX screen 80
        self.menu_c1 -= self.menu_c1 + self.width + 3 - 77;
    self.menu_c2 = self.menu_c1 + self.width + 3;

    self.menu_items_at = 0;

    if ((self.imtui.focus == .menubar and self.imtui.focus.menubar.index == index) or
        (self.imtui.focus == .menu and self.imtui.focus.menu.index == index))
        self.imtui.text_mode.paint(r, c, r + 1, self.c2, 0x07, .Blank);

    const show_acc = self.imtui.focus != .menu and (self.imtui.alt_held or
        (self.imtui.focus == .menubar and !self.imtui.focus.menubar.open));
    self.imtui.text_mode.writeAccelerated(r, c + 1, label, show_acc);
}

pub fn deinit(self: *Menu) void {
    for (self.menu_items.items) |mit|
        if (mit) |it|
            it.deinit();
    self.menu_items.deinit(self.imtui.allocator);
    self.imtui.allocator.destroy(self);
}

pub fn item(self: *Menu, label: []const u8) !*Imtui.Controls.MenuItem {
    const i = if (self.menu_items_at == self.menu_items.items.len) i: {
        const i = try Imtui.Controls.MenuItem.create(self.imtui, label, self.menu_items_at);
        try self.menu_items.append(self.imtui.allocator, i);
        break :i i;
    } else i: {
        // XXX: can't handle item/separator swap
        var i = self.menu_items.items[self.menu_items_at].?;
        i.describe(label, self.menu_items_at);
        break :i i;
    };
    self.menu_items_at += 1;
    return i;
}

pub fn separator(self: *Menu) !void {
    // XXX: can't handle item/separator swap
    if (self.menu_items_at == self.menu_items.items.len)
        try self.menu_items.append(self.imtui.allocator, null)
    else
        std.debug.assert(self.menu_items.items[self.menu_items_at] == null);
    self.menu_items_at += 1;
}

pub fn end(self: *Menu) !void {
    if (self.menu_items.items.len > self.menu_items_at) {
        for (self.menu_items.items[self.menu_items_at..]) |mit|
            if (mit) |it|
                it.deinit();
        try self.menu_items.replaceRange(
            self.imtui.allocator,
            self.menu_items_at,
            self.menu_items.items.len - self.menu_items_at,
            &.{},
        );
    }
    std.debug.assert(self.menu_items.items.len == self.menu_items_at);

    if (self.imtui.openMenu() != self)
        return;

    self.imtui.text_mode.draw(self.r + 1, self.menu_c1, 0x70, .TopLeft);
    self.imtui.text_mode.paint(self.r + 1, self.menu_c1 + 1, self.r + 2, self.menu_c2, 0x70, .Horizontal);
    self.imtui.text_mode.draw(self.r + 1, self.menu_c2, 0x70, .TopRight);

    var row = self.r + 2;
    for (self.menu_items.items, 0..) |mit, ix| {
        if (mit) |it| {
            self.imtui.text_mode.draw(row, self.menu_c1, 0x70, .Vertical);
            const selected = self.imtui.focus == .menu and self.imtui.focus.menu.item == ix;
            const colour: u8 = if (selected)
                0x07
            else if (!it.enabled)
                0x78
            else
                0x70;
            self.imtui.text_mode.paint(row, self.menu_c1 + 1, row + 1, self.menu_c2, colour, .Blank);

            if (it._bullet)
                self.imtui.text_mode.draw(row, self.menu_c1 + 1, colour, .Bullet);

            self.imtui.text_mode.writeAccelerated(row, self.menu_c1 + 2, it.label, it.enabled);

            if (it._shortcut) |shortcut| {
                var buf: [20]u8 = undefined;
                const text = Imtui.Controls.formatShortcut(&buf, shortcut);
                self.imtui.text_mode.write(row, self.menu_c2 - 1 - text.len, text);
            }

            self.imtui.text_mode.draw(row, self.menu_c1 + self.width + 3, 0x70, .Vertical);
        } else {
            self.imtui.text_mode.draw(row, self.menu_c1, 0x70, .VerticalRight);
            self.imtui.text_mode.paint(row, self.menu_c1 + 1, row + 1, self.menu_c2, 0x70, .Horizontal);
            self.imtui.text_mode.draw(row, self.menu_c2, 0x70, .VerticalLeft);
        }
        self.imtui.text_mode.shadow(row, self.menu_c2 + 1);
        self.imtui.text_mode.shadow(row, self.menu_c2 + 2);
        row += 1;
    }
    self.imtui.text_mode.draw(row, self.menu_c1, 0x70, .BottomLeft);
    self.imtui.text_mode.paint(row, self.menu_c1 + 1, row + 1, self.menu_c2, 0x70, .Horizontal);
    self.imtui.text_mode.draw(row, self.menu_c2, 0x70, .BottomRight);
    self.imtui.text_mode.shadow(row, self.menu_c2 + 1);
    self.imtui.text_mode.shadow(row, self.menu_c2 + 2);
    row += 1;
    for (self.menu_c1 + 2..self.menu_c2 + 3) |j|
        self.imtui.text_mode.shadow(row, j);
}

pub fn mouseIsOver(self: *const Menu) bool {
    return self.imtui.mouse_row == self.r and self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
}

pub fn mouseIsOverItem(self: *Menu) bool {
    return self.imtui.mouse_row >= self.r + 2 and
        self.imtui.mouse_row <= self.r + 2 + self.menu_items.items.len - 1 and
        self.imtui.mouse_col >= self.menu_c1 and
        self.imtui.mouse_col <= self.menu_c2;
}

pub fn mouseOverItem(self: *Menu) ?*Imtui.Controls.MenuItem {
    if (!self.mouseIsOverItem()) return null;
    return self.menu_items.items[self.imtui.mouse_row - self.r - 2];
}
