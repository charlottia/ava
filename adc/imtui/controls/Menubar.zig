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
        menu: Imtui.Controls.MenuItemReference,
    };

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .orphan = true,
                .deinit = deinit,
                .handleKeyPress = handleKeyPress,
                .handleKeyUp = handleKeyUp,
                .isMouseOver = isMouseOver,
                .handleMouseDown = handleMouseDown,
                .handleMouseDrag = handleMouseDrag,
                .handleMouseUp = handleMouseUp,
            },
        };
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

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        for (self.menus.items) |m|
            m.deinit();
        self.menus.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn openMenu(self: *const Impl) ?*Imtui.Controls.Menu.Impl {
        switch (self.focus orelse return null) {
            .pre => {},
            .menubar => |d| if (d.open) return self.menus.items[d.index],
            .menu => |d| return self.menus.items[d.index],
        }
        return null;
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = modifiers;

        if (self.imtui.mouse_down != null) return;

        switch (self.focus.?) {
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
                            self.imtui.alt_held = false;
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
                    var item = self.menus.items[d.index].menu_items.items[d.item].?;
                    if (item.enabled)
                        item.chosen = true;
                },
                else => if (Imtui.keycodeAlphanum(keycode)) {
                    for (self.menus.items[d.index].menu_items.items) |mi|
                        if (mi != null and Imtui.acceleratorMatch(mi.?.label, keycode)) {
                            if (mi.?.enabled)
                                mi.?.chosen = true;
                            return;
                        };
                },
            },
        }
    }

    fn handleKeyUp(ptr: *anyopaque, keycode: SDL.Keycode) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        switch (self.focus.?) {
            .pre => if (self.imtui.alt_held and (keycode == .left_alt or keycode == .right_alt)) {
                self.focus = .{ .menubar = .{ .index = 0, .open = false } };
            },
            .menubar => |*d| if (self.imtui.alt_held and (keycode == .left_alt or keycode == .right_alt)) {
                if (d.open)
                    d.open = false
                else
                    self.unfocus();
            },
            .menu => |d| if (self.imtui.alt_held and (keycode == .left_alt or keycode == .right_alt)) {
                self.focus = .{ .menubar = .{ .index = d.index, .open = false } };
            },
        }
    }

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.imtui.mouse_row == self.r and self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;
        _ = clicks;

        if (cm) return null;

        self.op_closable = false;

        for (self.menus.items, 0..) |m, mix|
            if (m.isMouseOver()) {
                if (self.openMenu()) |om|
                    self.op_closable = om.index == mix;
                try self.imtui.focus(self.control());
                self.focus = .{ .menubar = .{ .index = mix, .open = true } };
                return self.control();
            };

        // XXX: in QB you can click down on a separator, and then drag to
        // an item. We can't yet.
        if (self.openMenu()) |m|
            if (m.mousedOverItem()) |i| {
                self.focus = .{ .menu = .{ .index = m.index, .item = i.index } };
                return self.control();
            };

        if (self.imtui.focused(self.control())) {
            // XXX: this should fallthrough to the editor; it doesn't.
            self.unfocus();
            return self.control();
        }

        return self.control();
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;

        if (self.imtui.mouse_row == self.r) {
            for (self.menus.items, 0..) |m, mix|
                if (m.isMouseOver()) {
                    if (self.openMenu()) |om|
                        self.op_closable = self.op_closable and om.index == mix;
                    try self.imtui.focus(self.control());
                    self.focus = .{ .menubar = .{ .index = mix, .open = true } };
                    return;
                };

            if (self.imtui.focused(self.control()))
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

    fn handleMouseUp(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;
        _ = clicks;

        if (self.openMenu()) |m| {
            if (m.mousedOverItem()) |i| {
                i.chosen = true;
                return;
            }

            if (m.isMouseOver() and !self.op_closable) {
                self.focus = .{ .menu = .{ .index = m.index, .item = 0 } };
                return;
            }

            self.unfocus();
        }
    }

    pub fn unfocus(self: *Impl) void {
        self.focus = null;
        self.imtui.unfocus(self.control());
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(_: []u8, _: usize, _: usize, _: usize) ![]const u8 {
    return "core.Menubar";
}

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
        impl.offset = impl.imtui.text_mode.W - 7
    else if (std.mem.eql(u8, label, "Debu&g")) // XXX
        impl.offset = impl.imtui.text_mode.W - 8;

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
