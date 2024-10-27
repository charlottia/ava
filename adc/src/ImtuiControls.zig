const std = @import("std");

const Imtui = @import("./Imtui.zig");

pub const Menubar = struct {
    imtui: *Imtui,
    r: usize,
    c1: usize,
    c2: usize,

    offset: usize = 2,
    menus: std.ArrayListUnmanaged(*MenubarMenu) = .{},

    pub fn init(imtui: *Imtui, r: usize, c1: usize, c2: usize) Menubar {
        imtui.text_mode.paint(r, c1, r + 1, c2, 0x70, .Blank);
        return .{ .imtui = imtui, .r = r, .c1 = c1, .c2 = c2 };
    }

    pub fn menu(self: *Menubar, label: []const u8, width: usize) !*MenubarMenu {
        const m = try self.imtui.arena_allocator.create(MenubarMenu);
        m.* = MenubarMenu.init(self.imtui, self.r, self.c1 + self.offset, label, self.menus.items.len, width);
        try self.menus.append(self.imtui.arena_allocator, m);
        self.offset += lenWithoutAccelerators(label) + 2;
        std.debug.assert(self.offset < self.c2 - self.c1);
        return m;
    }
};

pub const MenubarMenu = struct {
    imtui: *Imtui,
    r: usize,
    c: usize,
    label: []const u8,
    index: usize,
    width: usize,

    items: std.ArrayListUnmanaged(?*MenubarItem) = .{},
    selectable_count: usize = 0,

    fn init(imtui: *Imtui, r: usize, c: usize, label: []const u8, index: usize, width: usize) MenubarMenu {
        if ((imtui._focus == .menubar and imtui._focus.menubar == index) or
            (imtui._focus == .menu and imtui._focus.menu.index == index))
            imtui.text_mode.paint(r, c, r + 1, c + lenWithoutAccelerators(label) + 2, 0x07, .Blank);

        const show_acc = imtui._focus != .menu and (imtui._alt_held or imtui._focus == .menubar);
        imtui.text_mode.writeAccelerated(r, c + 1, label, show_acc);

        return .{ .imtui = imtui, .r = r, .c = c, .label = label, .index = index, .width = width };
    }

    pub fn item(self: *MenubarMenu, label: []const u8) !*MenubarItem {
        const i = try self.imtui.arena_allocator.create(MenubarItem);
        i.* = MenubarItem.init(self.imtui, label);
        try self.items.append(self.imtui.arena_allocator, i);
        self.selectable_count += 1;
        return i;
    }

    pub fn separator(self: *MenubarMenu) !void {
        try self.items.append(self.imtui.arena_allocator, null);
    }

    pub fn end(self: *MenubarMenu) !void {
        if (!(self.imtui._focus == .menu and self.imtui._focus.menu.index == self.index))
            return;

        const selected_it_ix = self.imtui._focus.menu.item;

        self.imtui.text_mode.draw(self.r + 1, self.c - 1, 0x70, .TopLeft);
        self.imtui.text_mode.paint(self.r + 1, self.c, self.r + 2, self.c + self.width + 2, 0x70, .Horizontal);
        self.imtui.text_mode.draw(self.r + 1, self.c - 1 + self.width + 3, 0x70, .TopRight);

        var row = self.r + 2;
        var it_ix: usize = 0;
        for (self.items.items) |mit| {
            if (mit) |it| {
                defer it_ix += 1;
                self.imtui.text_mode.draw(row, self.c - 1, 0x70, .Vertical);
                const disabled = std.mem.eql(u8, "&Undo", it.label) or std.mem.eql(u8, "Cu&t", it.label) or std.mem.eql(u8, "&Copy", it.label) or std.mem.eql(u8, "Cl&ear", it.label);
                const colour: u8 = if (selected_it_ix == it_ix)
                    0x07
                else if (disabled)
                    0x78
                else
                    0x70;
                self.imtui.text_mode.paint(row, self.c, row + 1, self.c + self.width + 2, colour, .Blank);

                self.imtui.text_mode.writeAccelerated(row, self.c + 1, it.label, !disabled);
                // if (self.selected_menu_item == it_ix)
                //     menu_help_text = o.@"1";

                // if (o.len == 3) {
                //     // Shortcut key.
                //     const sk = o.@"2";
                //     self.imtui.text_mode.write(row, offset + menu.width + 2 - sk.len, sk);
                // }
                self.imtui.text_mode.draw(row, self.c - 1 + self.width + 3, 0x70, .Vertical);
            } else {
                self.imtui.text_mode.draw(row, self.c - 1, 0x70, .VerticalRight);
                self.imtui.text_mode.paint(row, self.c, row + 1, self.c + self.width + 2, 0x70, .Horizontal);
                self.imtui.text_mode.draw(row, self.c - 1 + self.width + 3, 0x70, .VerticalLeft);
            }
            self.imtui.text_mode.shadow(row, self.c - 1 + self.width + 4);
            self.imtui.text_mode.shadow(row, self.c - 1 + self.width + 5);
            row += 1;
        }
        self.imtui.text_mode.draw(row, self.c - 1, 0x70, .BottomLeft);
        self.imtui.text_mode.paint(row, self.c - 1 + 1, row + 1, self.c - 1 + 1 + self.width + 2, 0x70, .Horizontal);
        self.imtui.text_mode.draw(row, self.c - 1 + self.width + 3, 0x70, .BottomRight);
        self.imtui.text_mode.shadow(row, self.c - 1 + self.width + 4);
        self.imtui.text_mode.shadow(row, self.c - 1 + self.width + 5);
        row += 1;
        for (2..self.width + 6) |j|
            self.imtui.text_mode.shadow(row, self.c - 1 + j);
    }
};

pub const MenubarItem = struct {
    imtui: *Imtui,
    label: []const u8,
    shortcut_key: ?[]const u8 = null,
    help_text: ?[]const u8 = null,

    fn init(imtui: *Imtui, label: []const u8) MenubarItem {
        return .{ .imtui = imtui, .label = label };
    }

    pub fn shortcut(self: *MenubarItem, key: []const u8) *MenubarItem {
        // TODO: we actually need to make this trigger!
        self.shortcut_key = key;
        return self;
    }

    pub fn help(self: *MenubarItem, text: []const u8) void {
        self.help_text = text;
    }
};

fn lenWithoutAccelerators(s: []const u8) usize {
    var len: usize = 0;
    for (s) |c|
        len += if (c == '&') 0 else 1;
    return len;
}
