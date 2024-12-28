const std = @import("std");

// Not a Control in the separately-dispatchable sense.

const Imtui = @import("../Imtui.zig");

const Menu = @This();

pub const Impl = struct {
    imtui: *Imtui,
    menubar: *Imtui.Controls.Menubar.Impl,
    r: usize = undefined,
    c1: usize = undefined,
    c2: usize = undefined,
    label: []const u8 = undefined,
    index: usize = undefined,
    width: usize = undefined,
    menu_c1: usize = undefined,
    menu_c2: usize = undefined,

    menu_items: std.ArrayListUnmanaged(?*Imtui.Controls.MenuItem.Impl) = .{},
    menu_items_at: usize = 0,

    pub fn deinit(self: *Impl) void {
        for (self.menu_items.items) |mit|
            if (mit) |it|
                it.deinit();
        self.menu_items.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn describe(self: *Impl, r: usize, c: usize, label: []const u8, index: usize, width: usize) void {
        std.debug.assert(self.menu_items.items.len == self.menu_items_at);

        self.r = r;
        self.c1 = c;
        self.c2 = c + Imtui.Controls.lenWithoutAccelerators(label) + 2;
        self.label = label;
        self.index = index;
        self.width = width;

        self.menu_items_at = 0;

        const focused = self.imtui.focused(self.menubar.control());

        if (focused and
            ((self.menubar.focus.? == .menubar and self.menubar.focus.?.menubar.index == index) or
            (self.menubar.focus.? == .menu and self.menubar.focus.?.menu.index == index)))
            self.imtui.text_mode.paint(r, c, r + 1, self.c2, 0x07, .Blank);

        const show_acc = focused and (self.menubar.focus.? == .pre or
            (self.menubar.focus.? == .menubar and !self.menubar.focus.?.menubar.open));

        self.imtui.text_mode.writeAccelerated(r, c + 1, label, show_acc);
    }

    pub fn isMouseOver(self: *const Impl) bool {
        return self.imtui.mouse_row == self.r and
            self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
    }

    pub fn isMouseOverItem(self: *Impl) bool {
        return self.imtui.mouse_row >= self.r + 2 and
            self.imtui.mouse_row <= self.r + 2 + self.menu_items.items.len - 1 and
            self.imtui.mouse_col >= self.menu_c1 and
            self.imtui.mouse_col <= self.menu_c2; // TODO: this should be < self.menu_c2 for consistency
    }

    pub fn mousedOverItem(self: *Impl) ?*Imtui.Controls.MenuItem.Impl {
        if (!self.isMouseOverItem()) return null;
        return self.menu_items.items[self.imtui.mouse_row - self.r - 2];
    }
};

impl: *Impl,

pub fn create(
    menubar: *Imtui.Controls.Menubar.Impl,
    r: usize,
    c: usize,
    label: []const u8,
    index: usize,
    width: usize,
) !Menu {
    var m = try menubar.imtui.allocator.create(Impl);
    m.* = .{
        .imtui = menubar.imtui,
        .menubar = menubar,
    };
    m.describe(r, c, label, index, width);
    return .{ .impl = m };
}

pub fn item(self: Menu, label: []const u8) !Imtui.Controls.MenuItem {
    const impl = self.impl;

    const i = if (impl.menu_items_at == impl.menu_items.items.len) i: {
        const i = try Imtui.Controls.MenuItem.create(impl.imtui, label, impl.menu_items_at);
        try impl.menu_items.append(impl.imtui.allocator, i.impl);
        break :i i.impl;
    } else if (impl.menu_items.items[impl.menu_items_at]) |i| i: {
        try i.describe(label, impl.menu_items_at);
        break :i i;
    } else i: {
        const i = try Imtui.Controls.MenuItem.create(impl.imtui, label, impl.menu_items_at);
        impl.menu_items.items[impl.menu_items_at] = i.impl;
        break :i i.impl;
    };
    impl.menu_items_at += 1;

    return .{ .impl = i };
}

pub fn separator(self: Menu) !void {
    const impl = self.impl;
    if (impl.menu_items_at == impl.menu_items.items.len)
        try impl.menu_items.append(impl.imtui.allocator, null)
    else if (impl.menu_items.items[impl.menu_items_at]) |i| {
        i.deinit();
        impl.menu_items.items[impl.menu_items_at] = null;
    }
    impl.menu_items_at += 1;
}

pub fn end(self: Menu) !void {
    const impl = self.impl;
    if (impl.menu_items.items.len > impl.menu_items_at) {
        for (impl.menu_items.items[impl.menu_items_at..]) |mit|
            if (mit) |it|
                it.deinit();
        impl.menu_items.replaceRangeAssumeCapacity(
            impl.menu_items_at,
            impl.menu_items.items.len - impl.menu_items_at,
            &.{},
        );
    }

    if (impl.menubar.openMenu() != impl)
        return;

    // Ensure minimum width requirement met.
    for (impl.menu_items.items) |mit|
        if (mit) |it| {
            const label_width = Imtui.Controls.lenWithoutAccelerators(it.label);
            const shortcut_width = if (try it.renderedShortcut()) |rs|
                1 + rs.len
            else
                0;
            impl.width = @max(label_width + shortcut_width, impl.width);
        };

    impl.menu_c1 = impl.c1 - 1;
    const sw = impl.imtui.text_mode.W;
    if (impl.menu_c1 + impl.width + 3 > sw - 3)
        impl.menu_c1 -= impl.menu_c1 + impl.width + 3 - (sw - 3);
    impl.menu_c2 = impl.menu_c1 + impl.width + 3;

    impl.imtui.text_mode.box(impl.r + 1, impl.menu_c1, impl.r + 3 + impl.menu_items.items.len, impl.menu_c2 + 1, 0x70);

    var row = impl.r + 2;
    for (impl.menu_items.items, 0..) |mit, ix| {
        if (mit) |it| {
            const selected = impl.imtui.focused(self.impl.menubar.control()) and
                self.impl.menubar.focus.? == .menu and self.impl.menubar.focus.?.menu.item == ix;
            const colour: u8 = if (selected)
                0x07
            else if (!it.enabled)
                0x78
            else
                0x70;
            impl.imtui.text_mode.paint(row, impl.menu_c1 + 1, row + 1, impl.menu_c2, colour, .Blank);

            if (it.bullet)
                impl.imtui.text_mode.draw(row, impl.menu_c1 + 1, colour, .Bullet);

            impl.imtui.text_mode.writeAccelerated(row, impl.menu_c1 + 2, it.label, it.enabled);

            if (try it.renderedShortcut()) |rs|
                impl.imtui.text_mode.write(row, impl.menu_c2 - 1 - rs.len, rs);
        } else {
            impl.imtui.text_mode.draw(row, impl.menu_c1, 0x70, .VerticalRight);
            impl.imtui.text_mode.paint(row, impl.menu_c1 + 1, row + 1, impl.menu_c2, 0x70, .Horizontal);
            impl.imtui.text_mode.draw(row, impl.menu_c2, 0x70, .VerticalLeft);
        }
        impl.imtui.text_mode.shadow(row, impl.menu_c2 + 1);
        impl.imtui.text_mode.shadow(row, impl.menu_c2 + 2);
        row += 1;
    }
    impl.imtui.text_mode.shadow(row, impl.menu_c2 + 1);
    impl.imtui.text_mode.shadow(row, impl.menu_c2 + 2);
    row += 1;
    for (impl.menu_c1 + 2..impl.menu_c2 + 3) |j|
        impl.imtui.text_mode.shadow(row, j);
}
