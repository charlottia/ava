const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const TextMode = @import("./TextMode.zig").TextMode;
const Font = @import("./Font.zig");
const ImtuiControls = @import("./ImtuiControls.zig");

const Imtui = @This();

allocator: Allocator,
text_mode: TextMode(25, 80),
scale: f32,

running: bool = true,

last_tick: u64,
delta_tick: u64 = 0,

keydown_tick: ?u64 = null,
keydown_sym: SDL.Keycode = .unknown,
keydown_mod: SDL.KeyModifierSet = undefined,
typematic_on: bool = false,

mouse_row: usize = 0,
mouse_col: usize = 0,
mouse_down: ?SDL.MouseButton = null,

mouse_menu_op: bool = false,
mouse_menu_op_closable: bool = false, // XXX

_alt_held: bool = false,
_focus: union(enum) {
    unknown,
    menubar: struct { index: usize, open: bool },
    menu: ImtuiControls.MenuItemReference,
} = .unknown,

_menubar: ?*ImtuiControls.Menubar = null,
_editors: std.AutoHashMapUnmanaged(usize, *ImtuiControls.Editor) = .{},

// https://ejmastnak.com/tutorials/arch/typematic-rate/
const TYPEMATIC_DELAY_MS = 500;
const TYPEMATIC_REPEAT_MS = 1000 / 25;

pub fn init(allocator: Allocator, renderer: SDL.Renderer, font: *Font, scale: f32) !*Imtui {
    const imtui = try allocator.create(Imtui);
    imtui.* = .{
        .allocator = allocator,
        .text_mode = try TextMode(25, 80).init(renderer, font),
        .scale = scale,
        .last_tick = SDL.getTicks64(),
    };
    return imtui;
}

pub fn deinit(self: *Imtui) void {
    if (self._menubar) |mb|
        mb.deinit();
    var eit = self._editors.valueIterator();
    while (eit.next()) |e|
        e.*.deinit();
    self._editors.deinit(self.allocator);
    self.allocator.destroy(self);
}

pub fn processEvent(self: *Imtui, ev: SDL.Event) void {
    switch (ev) {
        .key_down => |key| {
            if (key.is_repeat) return;
            try self.handleKeyPress(key.keycode, key.modifiers);
            self.keydown_tick = SDL.getTicks64();
            self.keydown_sym = key.keycode;
            self.keydown_mod = key.modifiers;
            self.typematic_on = false;
        },
        .key_up => |key| {
            // We don't try to match key down to up.
            try self.handleKeyUp(key.keycode);
            self.keydown_tick = null;
        },
        .mouse_motion => |motion| {
            const pos = self.interpolateMouse(motion);
            self.text_mode.positionMouseAt(pos.x, pos.y);
            if (self.handleMouseAt(self.text_mode.mouse_row, self.text_mode.mouse_col)) |old_loc| {
                if (self.mouse_down) |button|
                    try self.handleMouseDrag(button, old_loc.r, old_loc.c);
            }
        },
        .mouse_button_down => |button| {
            const pos = self.interpolateMouse(button);
            self.text_mode.positionMouseAt(pos.x, pos.y);
            _ = self.handleMouseAt(self.text_mode.mouse_row, self.text_mode.mouse_col);
            try self.handleMouseDown(button.button, button.clicks);
            self.mouse_down = button.button;
        },
        .mouse_button_up => |button| {
            const pos = self.interpolateMouse(button);
            self.text_mode.positionMouseAt(pos.x, pos.y);
            _ = self.handleMouseAt(self.text_mode.mouse_row, self.text_mode.mouse_col);
            try self.handleMouseUp(button.button, button.clicks);
            self.mouse_down = null;
        },
        .quit => self.running = false,
        else => {},
    }
}

pub fn render(self: *Imtui) !void {
    self.text_mode.cursor_inhibit = self._focus == .menu or self._focus == .menubar;
    try self.text_mode.present(self.delta_tick);
}

pub fn newFrame(self: *Imtui) !void {
    const this_tick = SDL.getTicks64();
    self.delta_tick = this_tick - self.last_tick;
    defer self.last_tick = this_tick;

    if (self.keydown_tick) |keydown_tick| {
        if (!self.typematic_on and this_tick >= keydown_tick + TYPEMATIC_DELAY_MS) {
            self.typematic_on = true;
            self.keydown_tick = keydown_tick + TYPEMATIC_DELAY_MS;
            try self.handleKeyPress(self.keydown_sym, self.keydown_mod);
        } else if (self.typematic_on and this_tick >= keydown_tick + TYPEMATIC_REPEAT_MS) {
            self.keydown_tick = keydown_tick + TYPEMATIC_REPEAT_MS;
            try self.handleKeyPress(self.keydown_sym, self.keydown_mod);
        }
    }

    self.text_mode.clear(0x07);
}

pub fn menubar(self: *Imtui, r: usize, c1: usize, c2: usize) !*ImtuiControls.Menubar {
    if (self._menubar) |mb| {
        mb.describe(r, c1, c2);
        return mb;
    }

    const mb = try ImtuiControls.Menubar.create(self, r, c1, c2);
    self._menubar = mb;
    return mb;
}

pub fn editor(self: *Imtui, r1: usize, c1: usize, r2: usize, c2: usize, editor_id: usize) !*ImtuiControls.Editor {
    const gop = try self._editors.getOrPut(self.allocator, editor_id);
    if (gop.found_existing) {
        gop.value_ptr.*.describe(r1, c1, r2, c2);
        return gop.value_ptr.*;
    }

    const e = try ImtuiControls.Editor.create(self, r1, c1, r2, c2);
    gop.value_ptr.* = e;
    return e;
}

pub fn openMenu(self: *Imtui) ?*ImtuiControls.Menu {
    switch (self._focus) {
        .menubar => |mb| if (mb.open) return self._menubar.?.menus.items[mb.index],
        .menu => |m| return self._menubar.?.menus.items[m.index],
        else => {},
    }
    return null;
}

fn handleKeyPress(self: *Imtui, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    _ = modifiers;

    if ((keycode == .left_alt or keycode == .right_alt) and !self._alt_held) {
        self._alt_held = true;
        return;
    }

    if ((self._focus == .menubar or self._focus == .menu) and self.mouse_down != null)
        return;

    if (self._alt_held and keycodeAlphanum(keycode)) {
        for (self._menubar.?.menus.items, 0..) |m, mix|
            if (acceleratorMatch(m.label, keycode)) {
                self._alt_held = false;
                self._focus = .{ .menu = .{ .index = mix, .item = 0 } };
                return;
            };
    }

    switch (self._focus) {
        .menubar => |*mb| switch (keycode) {
            .left => {
                if (mb.index == 0)
                    mb.index = self._menubar.?.menus.items.len - 1
                else
                    mb.index -= 1;
            },
            .right => mb.index = (mb.index + 1) % self._menubar.?.menus.items.len,
            .up, .down => self._focus = .{ .menu = .{ .index = mb.index, .item = 0 } },
            .escape => {
                self._focus = .unknown; // XXX
            },
            .@"return" => self._focus = .{ .menu = .{ .index = mb.index, .item = 0 } },
            else => if (keycodeAlphanum(keycode)) {
                for (self._menubar.?.menus.items, 0..) |m, mix|
                    if (acceleratorMatch(m.label, keycode)) {
                        self._focus = .{ .menu = .{ .index = mix, .item = 0 } };
                        return;
                    };
            },
        },
        .menu => |*m| switch (keycode) {
            .left => {
                m.item = 0;
                if (m.index == 0)
                    m.index = self._menubar.?.menus.items.len - 1
                else
                    m.index -= 1;
            },
            .right => {
                m.item = 0;
                m.index = (m.index + 1) % self._menubar.?.menus.items.len;
            },
            .up => while (true) {
                if (m.item == 0)
                    m.item = self._menubar.?.menus.items[m.index].menu_items.items.len - 1
                else
                    m.item -= 1;
                if (self._menubar.?.menus.items[m.index].menu_items.items[m.item] == null)
                    continue;
                break;
            },
            .down => while (true) {
                m.item = (m.item + 1) % self._menubar.?.menus.items[m.index].menu_items.items.len;
                if (self._menubar.?.menus.items[m.index].menu_items.items[m.item] == null)
                    continue;
                break;
            },
            .escape => {
                self._focus = .unknown; // XXX
            },
            .@"return" => self._menubar.?.menus.items[m.index].menu_items.items[m.item].?._chosen = true,
            else => if (keycodeAlphanum(keycode)) {
                for (self._menubar.?.menus.items[m.index].menu_items.items) |*mi|
                    if (mi.* != null and acceleratorMatch(mi.*.?.label, keycode)) {
                        mi.*.?._chosen = true;
                    };
            },
        },
        else => {},
    }
}

fn handleKeyUp(self: *Imtui, keycode: SDL.Keycode) !void {
    if ((keycode == .left_alt or keycode == .right_alt) and self._alt_held) {
        self._alt_held = false;

        if (self._focus == .menu) {
            self._focus = .{ .menubar = .{ .index = self._focus.menu.index, .open = false } };
        } else if (self._focus != .menubar) {
            self._focus = .{ .menubar = .{ .index = 0, .open = false } };
        } else {
            self._focus = .unknown; // XXX
        }
    }
}

fn handleMouseAt(self: *Imtui, row: usize, col: usize) ?struct { r: usize, c: usize } {
    const old_mouse_row = self.mouse_row;
    const old_mouse_col = self.mouse_col;

    self.mouse_row = row;
    self.mouse_col = col;

    if (old_mouse_row != self.mouse_row or old_mouse_col != self.mouse_col)
        return .{ .r = old_mouse_row, .c = old_mouse_col };

    return null;
}

fn handleMouseDown(self: *Imtui, button: SDL.MouseButton, clicks: u8) !void {
    _ = clicks;

    // "mouse_menu_op" is a bit of hack. We might be able to generalise it by
    // saying that whatever control a mouse operation starts in then receives
    // further events until it ends (i.e. from down to up).
    self.mouse_menu_op = false;

    if (button == .left and (self._menubar.?.mouseIsOver(self) or
        (self.openMenu() != null and self.openMenu().?.mouseIsOverItem(self))))
    {
        self.mouse_menu_op = true;
        return self.handleMenuMouseDown();
    }

    if (button == .left and (self._focus == .menubar or self._focus == .menu)) {
        self._focus = .unknown; // XXX
        return;
    }
}

fn handleMouseDrag(self: *Imtui, button: SDL.MouseButton, old_row: usize, old_col: usize) !void {
    _ = button;

    if (self.mouse_menu_op)
        return self.handleMenuMouseDrag(old_row, old_col);
}

fn handleMouseUp(self: *Imtui, button: SDL.MouseButton, clicks: u8) !void {
    _ = button;
    _ = clicks;

    if (self.mouse_menu_op)
        return self.handleMenuMouseUp();
}

fn handleMenuMouseDown(self: *Imtui) void {
    self.mouse_menu_op_closable = false;

    for (self._menubar.?.menus.items, 0..) |*m, mix|
        if (m.*.mouseIsOver(self)) {
            if (self.openMenu()) |om|
                self.mouse_menu_op_closable = om.index == mix;
            self._focus = .{ .menubar = .{ .index = mix, .open = true } };
            return;
        };

    if (self.openMenu()) |m|
        if (m.mouseOverItem(self)) |i| {
            self._focus = .{ .menu = .{ .index = m.index, .item = i.index } };
            return;
        };
}

fn handleMenuMouseDrag(self: *Imtui, old_row: usize, old_col: usize) !void {
    _ = old_row;
    _ = old_col;

    if (self.mouse_row == self._menubar.?.r) {
        for (self._menubar.?.menus.items, 0..) |*m, mix|
            if (m.*.mouseIsOver(self)) {
                if (self.openMenu()) |om|
                    self.mouse_menu_op_closable = self.mouse_menu_op_closable and
                        om.index == mix;
                self._focus = .{ .menubar = .{ .index = mix, .open = true } };
                return;
            };
        self._focus = .unknown; // XXX
        return;
    }

    if (self.openMenu()) |m| {
        if (m.mouseOverItem(self)) |i| {
            self.mouse_menu_op_closable = false;
            self._focus = .{ .menu = .{ .index = m.index, .item = i.index } };
        } else self._focus = .{ .menubar = .{ .index = m.index, .open = true } };
        return;
    }
}

fn handleMenuMouseUp(self: *Imtui) void {
    self.mouse_menu_op = false;

    if (self.openMenu()) |m| {
        if (m.mouseOverItem(self)) |i| {
            i._chosen = true;
            self._focus = .unknown; // XXX
            return;
        }

        if (m.mouseIsOver(self) and !self.mouse_menu_op_closable) {
            self._focus = .{ .menu = .{ .index = m.index, .item = 0 } };
            return;
        }

        self._focus = .unknown; // XXX
    }
}

fn interpolateMouse(self: *const Imtui, payload: anytype) struct { x: usize, y: usize } {
    return .{
        .x = @intFromFloat(@as(f32, @floatFromInt(@max(0, payload.x))) / self.scale),
        .y = @intFromFloat(@as(f32, @floatFromInt(@max(0, payload.y))) / self.scale),
    };
}

fn acceleratorMatch(label: []const u8, keycode: SDL.Keycode) bool {
    var next_acc = false;
    for (label) |c| {
        if (c == '&')
            next_acc = true
        else if (next_acc)
            return std.ascii.toLower(c) == @intFromEnum(keycode);
    }
    return false;
}

fn keycodeAlphanum(keycode: SDL.Keycode) bool {
    return @intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.a) and
        @intFromEnum(keycode) <= @intFromEnum(SDL.Keycode.z);
}
