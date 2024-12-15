const std = @import("std");

const Imtui = @import("../Imtui.zig");

const Menu = @This();

pub const Impl = struct {
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

    menu_items: std.ArrayListUnmanaged(?*Imtui.Controls.MenuItem.Impl) = .{},
    menu_items_at: usize = undefined,

    pub fn deinit(self: *Impl) void {
        std.log.debug("Menu.Impl deinit self is {*}", .{self});
        for (self.menu_items.items) |mit|
            if (mit) |it|
                it.deinit();
        self.menu_items.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn describe(self: *Impl, r: usize, c: usize, label: []const u8, index: usize, width: usize) void {
        self.r = r;
        self.c1 = c;
        self.c2 = c + Imtui.Controls.lenWithoutAccelerators(label) + 2;
        self.label = label;
        self.index = index;
        self.width = width;

        self.menu_c1 = c - 1;
        const sw = @TypeOf(self.imtui.text_mode).W;
        if (self.menu_c1 + self.width + 3 > sw - 3)
            self.menu_c1 -= self.menu_c1 + self.width + 3 - (sw - 3);
        self.menu_c2 = self.menu_c1 + self.width + 3;

        self.menu_items_at = 0;

        // if ((self.imtui.focus == .menubar and self.imtui.focus.menubar.index == index) or
        //     (self.imtui.focus == .menu and self.imtui.focus.menu.index == index))
        //     self.imtui.text_mode.paint(r, c, r + 1, self.c2, 0x07, .Blank);

        // const show_acc = self.imtui.focus != .menu and
        //     self.imtui.focus != .dialog and
        //     (self.imtui.alt_held or (self.imtui.focus == .menubar and !self.imtui.focus.menubar.open));
        const show_acc = true;
        self.imtui.text_mode.writeAccelerated(r, c + 1, label, show_acc);
    }

    pub fn mouseIsOver(self: *const Impl) bool {
        return self.imtui.mouse_row == self.r and self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
    }

    pub fn mouseIsOverItem(self: *Impl) bool {
        return self.imtui.mouse_row >= self.r + 2 and
            self.imtui.mouse_row <= self.r + 2 + self.menu_items.items.len - 1 and
            self.imtui.mouse_col >= self.menu_c1 and
            self.imtui.mouse_col <= self.menu_c2;
    }

    pub fn mouseOverItem(self: *Impl) ?*Imtui.Controls.MenuItem.Impl {
        if (!self.mouseIsOverItem()) return null;
        return self.menu_items.items[self.imtui.mouse_row - self.r - 2];
    }
};

impl: *Impl,

pub fn create(imtui: *Imtui, r: usize, c: usize, label: []const u8, index: usize, width: usize) !Menu {
    var m = try imtui.allocator.create(Impl);
    m.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
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
        i.describe(label, impl.menu_items_at);
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
        try impl.menu_items.replaceRange(
            impl.imtui.allocator,
            impl.menu_items_at,
            impl.menu_items.items.len - impl.menu_items_at,
            &.{},
        );
    }
    std.debug.assert(impl.menu_items.items.len == impl.menu_items_at);

    // if ((try impl.imtui.openMenu()) != impl)
    //     return;

    // impl.imtui.text_mode.box(impl.r + 1, impl.menu_c1, impl.r + 3 + impl.menu_items.items.len, impl.menu_c2 + 1, 0x70);

    // var row = impl.r + 2;
    // for (impl.menu_items.items, 0..) |mit, ix| {
    //     if (mit) |it| {
    //         // const selected = impl.imtui.focus == .menu and impl.imtui.focus.menu.item == ix;
    //         const selected = false;
    //         _ = ix;
    //         const colour: u8 = if (selected)
    //             0x07
    //         else if (!it.enabled)
    //             0x78
    //         else
    //             0x70;
    //         impl.imtui.text_mode.paint(row, impl.menu_c1 + 1, row + 1, impl.menu_c2, colour, .Blank);

    //         if (it.bullet)
    //             impl.imtui.text_mode.draw(row, impl.menu_c1 + 1, colour, .Bullet);

    //         impl.imtui.text_mode.writeAccelerated(row, impl.menu_c1 + 2, it.label, it.enabled);

    //         if (it.shortcut) |shortcut| {
    //             var buf: [20]u8 = undefined;
    //             const text = Imtui.Controls.formatShortcut(&buf, shortcut);
    //             impl.imtui.text_mode.write(row, impl.menu_c2 - 1 - text.len, text);
    //         }
    //     } else {
    //         impl.imtui.text_mode.draw(row, impl.menu_c1, 0x70, .VerticalRight);
    //         impl.imtui.text_mode.paint(row, impl.menu_c1 + 1, row + 1, impl.menu_c2, 0x70, .Horizontal);
    //         impl.imtui.text_mode.draw(row, impl.menu_c2, 0x70, .VerticalLeft);
    //     }
    //     impl.imtui.text_mode.shadow(row, impl.menu_c2 + 1);
    //     impl.imtui.text_mode.shadow(row, impl.menu_c2 + 2);
    //     row += 1;
    // }
    // impl.imtui.text_mode.shadow(row, impl.menu_c2 + 1);
    // impl.imtui.text_mode.shadow(row, impl.menu_c2 + 2);
    // row += 1;
    // for (impl.menu_c1 + 2..impl.menu_c2 + 3) |j|
    //     impl.imtui.text_mode.shadow(row, j);
}
