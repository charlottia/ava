const std = @import("std");

const Imtui = @import("./Imtui.zig");

pub const Button = struct {
    imtui: *Imtui,
    generation: usize,
    r: usize,
    c: usize,
    colour: u8,
    label: []const u8,

    _chosen: bool,

    pub fn create(imtui: *Imtui, r: usize, c: usize, colour: u8, label: []const u8) !*Button {
        var b = try imtui.allocator.create(Button);
        b.* = .{
            .imtui = imtui,
            .generation = imtui.generation,
            .r = undefined,
            .c = undefined,
            .colour = undefined,
            .label = label,
            ._chosen = false,
        };
        b.describe(r, c, colour);
        return b;
    }

    pub fn describe(self: *Button, r: usize, c: usize, colour: u8) void {
        self.r = r;
        self.c = c;
        self.colour = colour;
        self.imtui.text_mode.paint(r, c, r + 1, c + self.label.len, colour, .Blank);
        self.imtui.text_mode.write(r, c, self.label);
    }

    pub fn deinit(self: *Button) void {
        self.imtui.allocator.destroy(self);
    }

    pub fn mouseIsOver(self: *const Button, imtui: *const Imtui) bool {
        return imtui.mouse_row == self.r and imtui.mouse_col >= self.c and imtui.mouse_col < self.c + self.label.len;
    }

    pub fn chosen(self: *Button) bool {
        defer self._chosen = false;
        return self._chosen;
    }
};

pub const Menubar = struct {
    imtui: *Imtui,
    generation: usize,
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
            .generation = imtui.generation,
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

    pub fn itemAt(self: *const Menubar, ref: MenuItemReference) *const MenuItem {
        return self.menus.items[ref.index].menu_items.items[ref.item].?;
    }

    pub fn mouseIsOver(self: *const Menubar, imtui: *const Imtui) bool {
        return imtui.mouse_row == self.r and imtui.mouse_col >= self.c1 and imtui.mouse_col < self.c2;
    }
};

pub const Menu = struct {
    imtui: *Imtui,
    generation: usize,
    r: usize,
    c1: usize,
    c2: usize,
    label: []const u8,
    index: usize,
    width: usize,
    menu_c1: usize,
    menu_c2: usize,

    menu_items: std.ArrayListUnmanaged(?*MenuItem) = .{},
    menu_items_at: usize,

    fn create(imtui: *Imtui, r: usize, c: usize, label: []const u8, index: usize, width: usize) !*Menu {
        var m = try imtui.allocator.create(Menu);
        m.* = .{
            .imtui = imtui,
            .generation = imtui.generation,
            .r = undefined,
            .c1 = undefined,
            .c2 = undefined,
            .label = undefined,
            .index = undefined,
            .width = undefined,
            .menu_c1 = undefined,
            .menu_c2 = undefined,
            .menu_items_at = undefined,
        };
        m.describe(r, c, label, index, width);
        return m;
    }

    fn describe(self: *Menu, r: usize, c: usize, label: []const u8, index: usize, width: usize) void {
        self.r = r;
        self.c1 = c;
        self.c2 = c + lenWithoutAccelerators(label) + 2;
        self.label = label;
        self.index = index;
        self.width = width;

        self.menu_c1 = c - 1;
        if (self.menu_c1 + self.width + 3 > 77) // XXX
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

    pub fn item(self: *Menu, label: []const u8) !*MenuItem {
        const i = if (self.menu_items_at == self.menu_items.items.len) i: {
            const i = try MenuItem.create(self.imtui, label, self.menu_items_at);
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

                self.imtui.text_mode.writeAccelerated(row, self.menu_c1 + 2, it.label, it.enabled);

                if (it.shortcut_key) |key|
                    self.imtui.text_mode.write(row, self.menu_c2 - 1 - key.len, key);

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

    pub fn mouseIsOver(self: *const Menu, imtui: *const Imtui) bool {
        return imtui.mouse_row == self.r and imtui.mouse_col >= self.c1 and imtui.mouse_col < self.c2;
    }

    pub fn mouseIsOverItem(self: *Menu, imtui: *const Imtui) bool {
        return imtui.mouse_row >= self.r + 2 and
            imtui.mouse_row <= self.r + 2 + self.menu_items.items.len - 1 and
            imtui.mouse_col >= self.menu_c1 and
            imtui.mouse_col <= self.menu_c2;
    }

    pub fn mouseOverItem(self: *Menu, imtui: *const Imtui) ?*MenuItem {
        if (!self.mouseIsOverItem(imtui)) return null;
        return self.menu_items.items[imtui.mouse_row - self.r - 2];
    }
};

pub const MenuItem = struct {
    imtui: *Imtui,
    generation: usize,
    label: []const u8,
    index: usize,
    enabled: bool,
    shortcut_key: ?[]const u8,
    help_text: ?[]const u8,

    _chosen: bool,

    fn create(imtui: *Imtui, label: []const u8, index: usize) !*MenuItem {
        var i = try imtui.allocator.create(MenuItem);
        i.* = .{
            .imtui = imtui,
            .generation = imtui.generation,
            .label = undefined,
            .index = undefined,
            .enabled = undefined,
            .shortcut_key = undefined,
            .help_text = undefined,
            ._chosen = false,
        };
        i.describe(label, index);
        return i;
    }

    fn describe(self: *MenuItem, label: []const u8, index: usize) void {
        self.label = label;
        self.index = index;
        self.enabled = true;
        self.shortcut_key = null;
        self.help_text = null;
    }

    pub fn deinit(self: *MenuItem) void {
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

pub const MenuItemReference = struct { index: usize, item: usize };

pub const Editor = struct {
    imtui: *Imtui,
    generation: usize,
    r1: usize,
    c1: usize,
    r2: usize,
    c2: usize,
    _title: []const u8,

    pub fn create(imtui: *Imtui, r1: usize, c1: usize, r2: usize, c2: usize) !*Editor {
        var e = try imtui.allocator.create(Editor);
        e.* = .{
            .imtui = imtui,
            .generation = imtui.generation,
            .r1 = undefined,
            .c1 = undefined,
            .r2 = undefined,
            .c2 = undefined,
            ._title = undefined,
        };
        e.describe(r1, c1, r2, c2);
        return e;
    }

    pub fn describe(self: *Editor, r1: usize, c1: usize, r2: usize, c2: usize) void {
        self.r1 = r1;
        self.c1 = c1;
        self.r2 = r2;
        self.c2 = c2;
        self._title = "";
    }

    pub fn deinit(self: *Editor) void {
        self.imtui.allocator.destroy(self);
    }

    pub fn title(self: *Editor, t: []const u8) void {
        self._title = t;
    }

    pub fn end(self: *Editor) void {
        // XXX: r1==1 checks here are iffy.
        const active = true; // XXX
        const immediate = false; // XXX
        const fullscreened = false; // XXX
        const verticalScrollThumb = 0; // XXX
        const horizontalScrollThumb = 0; // XXX

        self.imtui.text_mode.draw(self.r1, self.c1, 0x17, if (self.r1 == 1) .TopLeft else .VerticalRight);
        for (self.c1 + 1..self.c2 - 1) |x|
            self.imtui.text_mode.draw(self.r1, x, 0x17, .Horizontal);

        const start = self.c1 + (self.c2 - self._title.len) / 2;
        const colour: u8 = if (active) 0x71 else 0x17;
        self.imtui.text_mode.paint(self.r1, start - 1, self.r1 + 1, start + self._title.len + 1, colour, 0);
        self.imtui.text_mode.write(self.r1, start, self._title);
        self.imtui.text_mode.draw(self.r1, self.c2 - 1, 0x17, if (self.r1 == 1) .TopRight else .VerticalLeft);

        if (!immediate) {
            self.imtui.text_mode.draw(self.r1, self.c2 - 5, 0x17, .VerticalLeft);
            self.imtui.text_mode.draw(self.r1, self.c2 - 4, 0x71, if (fullscreened) .ArrowVertical else .ArrowUp);
            self.imtui.text_mode.draw(self.r1, self.c2 - 3, 0x17, .VerticalRight);
        }

        self.imtui.text_mode.paint(self.r1 + 1, self.c1, self.r2, self.c1 + 1, 0x17, .Vertical);
        self.imtui.text_mode.paint(self.r1 + 1, self.c2 - 1, self.r2, self.c2, 0x17, .Vertical);
        self.imtui.text_mode.paint(self.r1 + 1, self.c1 + 1, self.r2, self.c2 - 1, 0x17, .Blank);

        // --8<-- editor contents go here --8<--

        if (active and !immediate) {
            if (self.r2 - self.r1 > 4) {
                self.imtui.text_mode.draw(self.r1 + 1, self.c2 - 1, 0x70, .ArrowUp);
                self.imtui.text_mode.paint(self.r1 + 2, self.c2 - 1, self.r2 - 2, self.c2, 0x70, .DotsLight);
                self.imtui.text_mode.draw(self.r1 + 2 + verticalScrollThumb, self.c2 - 1, 0x00, .Blank);
                self.imtui.text_mode.draw(self.r2 - 2, self.c2 - 1, 0x70, .ArrowDown);
            }

            if (self.r2 - self.r1 > 2) {
                self.imtui.text_mode.draw(self.r2 - 1, self.c1 + 1, 0x70, .ArrowLeft);
                self.imtui.text_mode.paint(self.r2 - 1, self.c1 + 2, self.r2, self.c2 - 2, 0x70, .DotsLight);
                self.imtui.text_mode.draw(self.r2 - 1, self.c1 + 2 + horizontalScrollThumb, 0x00, .Blank);
                self.imtui.text_mode.draw(self.r2 - 1, self.c2 - 2, 0x70, .ArrowRight);
            }
        }
    }
};

fn lenWithoutAccelerators(s: []const u8) usize {
    var len: usize = 0;
    for (s) |c|
        len += if (c == '&') 0 else 1;
    return len;
}
