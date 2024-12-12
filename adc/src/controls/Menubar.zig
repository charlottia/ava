const std = @import("std");
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Menubar = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,
    r: usize = undefined,
    c1: usize = undefined,
    c2: usize = undefined,

    offset: usize = undefined,
    menus: std.ArrayListUnmanaged(*Imtui.Controls.Menu.Impl) = .{},
    menus_at: usize = undefined,

    op_closable: bool = false,

    pub fn deinit(self: *Impl) void {
        for (self.menus.items) |m|
            m.deinit();
        self.menus.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn describe(self: *Impl, r: usize, c1: usize, c2: usize) void {
        self.r = r;
        self.c1 = c1;
        self.c2 = c2;
        self.offset = 2;
        self.menus_at = 0;
        self.imtui.text_mode.paint(r, c1, r + 1, c2, 0x70, .Blank);
    }

    pub fn mouseIsOver(self: *const Impl) bool {
        return self.imtui.mouse_row == self.r and self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
    }

    pub fn handleMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8) !void {
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

    pub fn handleMouseDrag(self: *Impl, b: SDL.MouseButton) !void {
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

    pub fn handleMouseUp(self: *Impl, b: SDL.MouseButton, clicks: u8) !void {
        _ = b;
        _ = clicks;

        if (self.imtui.openMenu()) |m| {
            if (m.mouseOverItem()) |i| {
                i.chosen = true;
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
};

impl: *Impl,

pub fn create(imtui: *Imtui, r: usize, c1: usize, c2: usize) !Menubar {
    var mb = try imtui.allocator.create(Impl);
    mb.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
    };
    mb.describe(r, c1, c2);
    return .{ .impl = mb };
}

pub fn menu(self: Menubar, label: []const u8, width: usize) !Imtui.Controls.Menu {
    const impl = self.impl;
    if (std.mem.eql(u8, label, "&Help")) // XXX
        impl.offset = @TypeOf(impl.imtui.text_mode).W - 7;

    const m = if (impl.menus_at == impl.menus.items.len) m: {
        const m = try Imtui.Controls.Menu.create(impl.imtui, impl.r, impl.c1 + impl.offset, label, impl.menus.items.len, width);
        try impl.menus.append(impl.imtui.allocator, m.impl);
        break :m m.impl;
    } else m: {
        var m = impl.menus.items[impl.menus_at];
        m.describe(impl.r, impl.c1 + impl.offset, label, impl.menus_at, width);
        break :m m;
    };
    impl.menus_at += 1;
    impl.offset += Imtui.Controls.lenWithoutAccelerators(label) + 2;
    std.debug.assert(impl.offset < impl.c2 - impl.c1);
    return .{ .impl = m };
}

pub fn itemAt(self: Menubar, ref: Imtui.Controls.MenuItemReference) *const Imtui.Controls.MenuItem.Impl {
    return self.impl.menus.items[ref.index].menu_items.items[ref.item].?;
}
