const std = @import("std");
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Menubar = @This();

imtui: *Imtui,
generation: usize,
r: usize = undefined,
c1: usize = undefined,
c2: usize = undefined,

offset: usize = undefined,
menus: std.ArrayListUnmanaged(*Imtui.Controls.Menu) = .{},
menus_at: usize = undefined,

op_closable: bool = false,

pub fn create(imtui: *Imtui, r: usize, c1: usize, c2: usize) !*Menubar {
    var mb = try imtui.allocator.create(Menubar);
    mb.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
    };
    mb.describe(r, c1, c2);
    return mb;
}

pub fn deinit(self: *Menubar) void {
    for (self.menus.items) |m|
        m.deinit();
    self.menus.deinit(self.imtui.allocator);
    self.imtui.allocator.destroy(self);
}

pub fn describe(self: *Menubar, r: usize, c1: usize, c2: usize) void {
    self.r = r;
    self.c1 = c1;
    self.c2 = c2;
    self.offset = 2;
    self.menus_at = 0;
    self.imtui.text_mode.paint(r, c1, r + 1, c2, 0x70, .Blank);
}

pub fn menu(self: *Menubar, label: []const u8, width: usize) !*Imtui.Controls.Menu {
    if (std.mem.eql(u8, label, "&Help")) // XXX
        self.offset = @TypeOf(self.imtui.text_mode).W - 7;

    const m = if (self.menus_at == self.menus.items.len) m: {
        const m = try Imtui.Controls.Menu.create(self.imtui, self.r, self.c1 + self.offset, label, self.menus.items.len, width);
        try self.menus.append(self.imtui.allocator, m);
        break :m m;
    } else m: {
        var m = self.menus.items[self.menus_at];
        m.describe(self.r, self.c1 + self.offset, label, self.menus_at, width);
        break :m m;
    };
    self.menus_at += 1;
    self.offset += Imtui.Controls.lenWithoutAccelerators(label) + 2;
    std.debug.assert(self.offset < self.c2 - self.c1);
    return m;
}

pub fn itemAt(self: *const Menubar, ref: Imtui.Controls.MenuItemReference) *const Imtui.Controls.MenuItem {
    return self.menus.items[ref.index].menu_items.items[ref.item].?;
}

pub fn mouseIsOver(self: *const Menubar) bool {
    return self.imtui.mouse_row == self.r and self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
}

pub fn handleMouseDown(self: *Menubar, b: SDL.MouseButton, clicks: u8) !void {
    _ = b;
    _ = clicks;

    self.op_closable = false;

    for (self.menus.items, 0..) |m, mix|
        if (m.mouseIsOver()) {
            if (self.imtui.openMenu()) |om|
                self.op_closable = om.index == mix;
            self.imtui.focus = .{ .menubar = .{ .index = mix, .open = true } };
            return;
        };

    if (self.imtui.openMenu()) |m|
        if (m.mouseOverItem()) |i| {
            self.imtui.focus = .{ .menu = .{ .index = m.index, .item = i.index } };
            return;
        };
}

pub fn handleMouseDrag(self: *Menubar, b: SDL.MouseButton) !void {
    _ = b;

    if (self.imtui.mouse_row == self.r) {
        for (self.menus.items, 0..) |m, mix|
            if (m.mouseIsOver()) {
                if (self.imtui.openMenu()) |om|
                    self.op_closable = self.op_closable and om.index == mix;
                self.imtui.focus = .{ .menubar = .{ .index = mix, .open = true } };
                return;
            };
        self.imtui.focus = .editor;
        return;
    }

    if (self.imtui.openMenu()) |m| {
        if (m.mouseOverItem()) |i| {
            self.op_closable = false;
            self.imtui.focus = .{ .menu = .{ .index = m.index, .item = i.index } };
        } else self.imtui.focus = .{ .menubar = .{ .index = m.index, .open = true } };
        return;
    }
}

pub fn handleMouseUp(self: *Menubar, b: SDL.MouseButton, clicks: u8) !void {
    _ = b;
    _ = clicks;

    if (self.imtui.openMenu()) |m| {
        if (m.mouseOverItem()) |i| {
            i._chosen = true;
            self.imtui.focus = .editor;
            return;
        }

        if (m.mouseIsOver() and !self.op_closable) {
            self.imtui.focus = .{ .menu = .{ .index = m.index, .item = 0 } };
            return;
        }

        self.imtui.focus = .editor;
    }
}
