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
    menus_at: usize = 0,
    focus: ?Focus = null,
    op_closable: bool = false,

    const Focus = union(enum) {
        pre,
        menubar: struct { index: usize, open: bool },
        menu: struct { index: usize, item: usize },
    };

    pub fn deinit(self: *Impl) void {
        for (self.menus.items) |m|
            m.deinit();
        self.menus.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn describe(self: *Impl, r: usize, c1: usize, c2: usize) void {
        std.debug.assert(self.menus.items.len == self.menus_at);

        self.r = r;
        self.c1 = c1;
        self.c2 = c2;
        self.offset = 2;
        self.menus_at = 0;
        self.imtui.text_mode.paint(r, c1, r + 1, c2, 0x70, .Blank);
    }

    pub fn openMenu(self: *const Impl) ?*Imtui.Controls.Menu.Impl {
        switch (self.focus orelse return null) {
            .pre => {},
            .menubar => |d| if (d.open) return self.menus.items[d.index],
            .menu => |d| return self.menus.items[d.index],
        }
        return null;
    }

    pub fn isMouseOver(self: *const Impl) bool {
        return self.imtui.mouse_row == self.r and self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
    }

    pub fn handleKeyPress(self: *Impl, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        _ = modifiers;

        if (self.imtui.mouse_down != null) return;

        switch (self.focus.?) {
            // Bit sussydog about the .pre bit here; check against QB.
            .pre => if (self.imtui.alt_held and Imtui.keycodeAlphanum(keycode)) {
                for (self.menus.items, 0..) |m, mix|
                    if (Imtui.acceleratorMatch(m.label, keycode)) {
                        self.imtui.alt_held = false;
                        self.focus = .{ .menu = .{ .index = mix, .item = 0 } };
                        return;
                    };
            },
            .menubar => |*d| switch (keycode) {
                .left => d.index = if (d.index == 0) self.menus.items.len - 1 else d.index - 1,
                .right => d.index = (d.index + 1) % self.menus.items.len,
                .up, .down => self.focus = .{ .menu = .{ .index = d.index, .item = 0 } },
                .escape => self.unfocus(),
                .@"return" => self.focus = .{ .menu = .{ .index = d.index, .item = 0 } },
                else => if (Imtui.keycodeAlphanum(keycode)) {
                    for (self.menus.items, 0..) |m, mix|
                        if (Imtui.acceleratorMatch(m.label, keycode)) {
                            self.focus = .{ .menu = .{ .index = mix, .item = 0 } };
                            return;
                        };
                },
            },
            .menu => |*d| switch (keycode) {
                .left => {
                    d.item = 0;
                    if (d.index == 0)
                        d.index = self.menus.items.len - 1
                    else
                        d.index -= 1;
                },
                .right => {
                    d.item = 0;
                    d.index = (d.index + 1) % self.menus.items.len;
                },
                .up => while (true) {
                    if (d.item == 0)
                        d.item = self.menus.items[d.index].menu_items.items.len - 1
                    else
                        d.item -= 1;
                    if (self.menus.items[d.index].menu_items.items[d.item] == null)
                        continue;
                    break;
                },
                .down => while (true) {
                    d.item = (d.item + 1) % self.menus.items[d.index].menu_items.items.len;
                    if (self.menus.items[d.index].menu_items.items[d.item] == null)
                        continue;
                    break;
                },
                .escape => self.unfocus(),
                .@"return" => {
                    self.menus.items[d.index].menu_items.items[d.item].?.chosen = true;
                    self.unfocus();
                },
                else => if (Imtui.keycodeAlphanum(keycode)) {
                    for (self.menus.items[d.index].menu_items.items) |mi|
                        if (mi != null and Imtui.acceleratorMatch(mi.?.label, keycode)) {
                            mi.?.chosen = true;
                            self.unfocus();
                            return;
                        };
                },
            },
        }
    }

    pub fn handleKeyUp(self: *Impl, keycode: SDL.Keycode) !void {
        switch (self.focus.?) {
            .pre => if (keycode == .left_alt or keycode == .right_alt) {
                self.focus = .{ .menubar = .{ .index = 0, .open = false } };
            },
            .menubar => |*d| if (keycode == .left_alt or keycode == .right_alt) {
                if (d.open)
                    d.open = false
                else
                    self.unfocus();
            },
            .menu => |d| if (keycode == .left_alt or keycode == .right_alt) {
                self.focus = .{ .menubar = .{ .index = d.index, .open = false } };
            },
        }
    }

    pub fn handleMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8, cm: bool) !bool {
        _ = b;
        _ = clicks;

        if (cm) return false;

        self.op_closable = false;

        for (self.menus.items, 0..) |m, mix|
            if (m.isMouseOver()) {
                if (self.openMenu()) |om|
                    self.op_closable = om.index == mix;
                try self.imtui.focus(.{ .menubar = self });
                self.focus = .{ .menubar = .{ .index = mix, .open = true } };
                return true;
            };

        if (self.openMenu()) |m|
            if (m.mousedOverItem()) |i| {
                self.focus = .{ .menu = .{ .index = m.index, .item = i.index } };
                return true;
            };

        if (self.imtui.focused(.{ .menubar = self })) {
            // XXX: this should fallthrough to the editor; it doesn't.
            self.unfocus();
            return true;
        }

        return true;
    }

    pub fn handleMouseDrag(self: *Impl, b: SDL.MouseButton) !void {
        _ = b;

        if (self.imtui.mouse_row == self.r) {
            for (self.menus.items, 0..) |m, mix|
                if (m.isMouseOver()) {
                    if (self.openMenu()) |om|
                        self.op_closable = self.op_closable and om.index == mix;
                    try self.imtui.focus(.{ .menubar = self });
                    self.focus = .{ .menubar = .{ .index = mix, .open = true } };
                    return;
                };

            if (self.imtui.focused(.{ .menubar = self }))
                self.unfocus();

            return;
        }

        if (self.openMenu()) |m| {
            if (m.mousedOverItem()) |i| {
                self.op_closable = false;
                self.focus = .{ .menu = .{ .index = m.index, .item = i.index } };
            } else {
                self.focus = .{ .menubar = .{ .index = m.index, .open = true } };
            }
            return;
        }
    }

    pub fn handleMouseUp(self: *Impl, b: SDL.MouseButton, clicks: u8) !void {
        _ = b;
        _ = clicks;

        if (self.openMenu()) |m| {
            if (m.mousedOverItem()) |i| {
                i.chosen = true;
                self.unfocus();
                return;
            }

            if (m.isMouseOver() and !self.op_closable) {
                self.focus = .{ .menu = .{ .index = m.index, .item = 0 } };
                return;
            }

            self.unfocus();
        }
    }

    fn unfocus(self: *Impl) void {
        self.focus = null;
        self.imtui.unfocus(.{ .menubar = self });
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
        impl.offset = impl.imtui.text_mode.W - 7;

    const m = if (impl.menus_at == impl.menus.items.len) m: {
        const m = try Imtui.Controls.Menu.create(impl, impl.r, impl.c1 + impl.offset, label, impl.menus.items.len, width);
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

pub fn end(self: Menubar) void {
    const impl = self.impl;
    if (impl.menus.items.len > impl.menus_at) {
        for (impl.menus.items[impl.menus_at..]) |m|
            m.deinit();
        impl.menus.replaceRangeAssumeCapacity(impl.menus_at, impl.menus.items.len - impl.menus_at, &.{});
    }

    if (impl.focus != null and impl.focus.? != .pre)
        self.impl.imtui.text_mode.cursor_inhibit = true;
}
