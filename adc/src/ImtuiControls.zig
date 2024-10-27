const std = @import("std");

const Imtui = @import("./Imtui.zig");

pub const Menubar = struct {
    imtui: *Imtui,
    r: usize,
    c1: usize,
    c2: usize,

    offset: usize,
    menus: std.ArrayListUnmanaged(*Menu),
    menus_at: usize,

    pub fn create(imtui: *Imtui, r: usize, c1: usize, c2: usize) !*Menubar {
        var mb = try imtui.allocator.create(Menubar);
        mb.* = .{
            .imtui = imtui,
            .r = undefined,
            .c1 = undefined,
            .c2 = undefined,
            .offset = undefined,
            .menus = .{},
            .menus_at = undefined,
        };
        mb.describe(r, c1, c2);
        return mb;
    }

    pub fn describe(self: *Menubar, r: usize, c1: usize, c2: usize) void {
        self.r = r;
        self.c1 = c1;
        self.c2 = c2;
        self.offset = 2;
        self.menus_at = 0;
        self.imtui.text_mode.paint(r, c1, r + 1, c2, 0x70, .Blank);
    }

    pub fn deinit(self: *Menubar) void {
        for (self.menus.items) |m|
            m.deinit();
        self.menus.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn menu(self: *Menubar, label: []const u8, width: usize) !*Menu {
        if (std.mem.eql(u8, label, "&Help")) // XXX
            self.offset = 73;

        const m = if (self.menus_at == self.menus.items.len) m: {
            const m = try Menu.create(self.imtui, self.r, self.c1 + self.offset, label, self.menus.items.len, width);
            try self.menus.append(self.imtui.allocator, m);
            break :m m;
        } else m: {
            var m = self.menus.items[self.menus_at];
            m.describe(self.r, self.c1 + self.offset, label, self.menus_at, width);
            break :m m;
        };
        self.menus_at += 1;
        self.offset += lenWithoutAccelerators(label) + 2;
        std.debug.assert(self.offset < self.c2 - self.c1);
        return m;
    }
};

pub const Menu = struct {
    imtui: *Imtui,
    r: usize,
    c: usize,
    label: []const u8,
    index: usize,
    width: usize,

    menu_items: std.ArrayListUnmanaged(?*MenuItem) = .{},
    menu_items_at: usize,

    fn create(imtui: *Imtui, r: usize, c: usize, label: []const u8, index: usize, width: usize) !*Menu {
        var m = try imtui.allocator.create(Menu);
        m.* = .{
            .imtui = imtui,
            .r = undefined,
            .c = undefined,
            .label = undefined,
            .index = undefined,
            .width = undefined,
            .menu_items_at = undefined,
        };
        m.describe(r, c, label, index, width);
        return m;
    }

    fn describe(self: *Menu, r: usize, c: usize, label: []const u8, index: usize, width: usize) void {
        self.r = r;
        self.c = c;
        self.label = label;
        self.index = index;
        self.width = width;
        self.menu_items_at = 0;

        if ((self.imtui._focus == .menubar and self.imtui._focus.menubar == index) or
            (self.imtui._focus == .menu and self.imtui._focus.menu.index == index))
            self.imtui.text_mode.paint(r, c, r + 1, c + lenWithoutAccelerators(label) + 2, 0x07, .Blank);

        const show_acc = self.imtui._focus != .menu and (self.imtui._alt_held or self.imtui._focus == .menubar);
        self.imtui.text_mode.writeAccelerated(r, c + 1, label, show_acc);
    }

    fn deinit(self: *Menu) void {
        for (self.menu_items.items) |mit|
            if (mit) |it|
                it.deinit();
        self.menu_items.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn item(self: *Menu, label: []const u8) !*MenuItem {
        const i = if (self.menu_items_at == self.menu_items.items.len) i: {
            const i = try MenuItem.create(self.imtui, label);
            try self.menu_items.append(self.imtui.allocator, i);
            break :i i;
        } else i: {
            // XXX: can't handle item/separator swap
            var i = self.menu_items.items[self.menu_items_at].?;
            i.describe(label);
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

        if (!(self.imtui._focus == .menu and self.imtui._focus.menu.index == self.index))
            return;

        const selected_it_ix = self.imtui._focus.menu.item;

        var c = self.c - 1;
        if (c + self.width + 3 > 77) // XXX
            c -= c + self.width + 3 - 77;

        self.imtui.text_mode.draw(self.r + 1, c, 0x70, .TopLeft);
        self.imtui.text_mode.paint(self.r + 1, c + 1, self.r + 2, c + self.width + 3, 0x70, .Horizontal);
        self.imtui.text_mode.draw(self.r + 1, c + self.width + 3, 0x70, .TopRight);

        var row = self.r + 2;
        for (self.menu_items.items, 0..) |mit, ix| {
            if (mit) |it| {
                self.imtui.text_mode.draw(row, c, 0x70, .Vertical);
                const colour: u8 = if (selected_it_ix == ix)
                    0x07
                else if (!it.enabled)
                    0x78
                else
                    0x70;
                self.imtui.text_mode.paint(row, c + 1, row + 1, c + self.width + 3, colour, .Blank);

                self.imtui.text_mode.writeAccelerated(row, c + 2, it.label, it.enabled);
                // if (self.selected_menu_item == ix)
                //     menu_help_text = o.@"1";

                if (it.shortcut_key) |key|
                    self.imtui.text_mode.write(row, c + self.width + 2 - key.len, key);

                self.imtui.text_mode.draw(row, c + self.width + 3, 0x70, .Vertical);
            } else {
                self.imtui.text_mode.draw(row, c, 0x70, .VerticalRight);
                self.imtui.text_mode.paint(row, c + 1, row + 1, c + self.width + 3, 0x70, .Horizontal);
                self.imtui.text_mode.draw(row, c + self.width + 3, 0x70, .VerticalLeft);
            }
            self.imtui.text_mode.shadow(row, c + self.width + 4);
            self.imtui.text_mode.shadow(row, c + self.width + 5);
            row += 1;
        }
        self.imtui.text_mode.draw(row, c, 0x70, .BottomLeft);
        self.imtui.text_mode.paint(row, c + 1, row + 1, c + 1 + self.width + 2, 0x70, .Horizontal);
        self.imtui.text_mode.draw(row, c + self.width + 3, 0x70, .BottomRight);
        self.imtui.text_mode.shadow(row, c + self.width + 4);
        self.imtui.text_mode.shadow(row, c + self.width + 5);
        row += 1;
        for (2..self.width + 6) |j|
            self.imtui.text_mode.shadow(row, c + j);
    }
};

pub const MenuItem = struct {
    imtui: *Imtui,
    label: []const u8,
    enabled: bool,
    shortcut_key: ?[]const u8,
    help_text: ?[]const u8,

    _chosen: bool,

    fn create(imtui: *Imtui, label: []const u8) !*MenuItem {
        var i = try imtui.allocator.create(MenuItem);
        i.* = .{
            .imtui = imtui,
            .label = undefined,
            .enabled = undefined,
            .shortcut_key = undefined,
            .help_text = undefined,
            ._chosen = false,
        };
        i.describe(label);
        return i;
    }

    fn describe(self: *MenuItem, label: []const u8) void {
        self.label = label;
        self.enabled = true;
        self.shortcut_key = null;
        self.help_text = null;
    }

    fn deinit(self: *MenuItem) void {
        self.imtui.allocator.destroy(self);
    }

    pub fn disabled(self: *MenuItem) *MenuItem {
        self.enabled = false;
        return self;
    }

    pub fn shortcut(self: *MenuItem, key: []const u8) *MenuItem {
        // TODO: we actually need to make this trigger!
        self.shortcut_key = key;
        return self;
    }

    pub fn help(self: *MenuItem, text: []const u8) *MenuItem {
        self.help_text = text;
        return self;
    }

    pub fn chosen(self: *MenuItem) bool {
        defer self._chosen = false;
        return self._chosen;
    }
};

fn lenWithoutAccelerators(s: []const u8) usize {
    var len: usize = 0;
    for (s) |c|
        len += if (c == '&') 0 else 1;
    return len;
}
