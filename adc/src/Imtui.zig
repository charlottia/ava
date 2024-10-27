const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const TextMode = @import("./TextMode.zig").TextMode;
const Font = @import("./Font.zig");
const ImtuiControls = @import("./ImtuiControls.zig");

const Imtui = @This();

base_allocator: Allocator,
arena: std.heap.ArenaAllocator,
arena_allocator: Allocator,
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

_alt_held: bool = false,
_focus: union(enum) {
    unknown,
    menubar: usize, // menu index
    menu: struct { index: usize, item: usize },
} = .unknown,

_menubar: ?*ImtuiControls.Menubar = null,

// https://ejmastnak.com/tutorials/arch/typematic-rate/
const TYPEMATIC_DELAY_MS = 500;
const TYPEMATIC_REPEAT_MS = 1000 / 25;

pub fn init(allocator: Allocator, renderer: SDL.Renderer, font: *Font, scale: f32) !*Imtui {
    const imtui = try allocator.create(Imtui);
    imtui.* = .{
        .base_allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .arena_allocator = undefined,
        .text_mode = try TextMode(25, 80).init(renderer, font),
        .scale = scale,
        .last_tick = SDL.getTicks64(),
    };
    imtui.arena_allocator = imtui.arena.allocator();
    return imtui;
}

pub fn deinit(self: *Imtui) void {
    self.arena.deinit();
    self.base_allocator.destroy(self);
}

pub fn processEvent(self: *Imtui, ev: SDL.Event) void {
    switch (ev) {
        .key_down => |key| {
            if (key.is_repeat) return;
            try self.handleKeyDown(key.keycode, key.modifiers);
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
            if (self.handleMouseAt(self.text_mode.cursor_row, self.text_mode.cursor_col)) |old_loc| {
                if (self.mouse_down) |button|
                    try self.handleMouseDrag(button, old_loc.r, old_loc.c);
            }
        },
        .mouse_button_down => |button| {
            const pos = self.interpolateMouse(button);
            self.text_mode.positionMouseAt(pos.x, pos.y);
            _ = self.handleMouseAt(self.text_mode.cursor_row, self.text_mode.cursor_col);
            try self.handleMouseDown(button.button, button.clicks);
            self.mouse_down = button.button;
        },
        .mouse_button_up => |button| {
            const pos = self.interpolateMouse(button);
            self.text_mode.positionMouseAt(pos.x, pos.y);
            _ = self.handleMouseAt(self.text_mode.cursor_row, self.text_mode.cursor_col);
            try self.handleMouseUp(button.button, button.clicks);
            self.mouse_down = null;
        },
        .quit => self.running = false,
        else => {},
    }
}

pub fn render(self: *Imtui) !void {
    try self.text_mode.present(self.delta_tick);
}

pub fn newFrame(self: *Imtui) !void {
    _ = self.arena.reset(.retain_capacity);
    self._menubar = null;

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
    std.debug.assert(self._menubar == null);
    const mb = try self.arena_allocator.create(ImtuiControls.Menubar);
    mb.* = ImtuiControls.Menubar.init(self, r, c1, c2);
    self._menubar = mb;
    return mb;
}

fn handleKeyDown(self: *Imtui, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    _ = modifiers;

    // XXX: just roll this into handleKeyPress and remove the distinction?
    if ((keycode == .left_alt or keycode == .right_alt) and !self._alt_held) {
        self._alt_held = true;
        return;
    }
}

fn handleKeyPress(self: *Imtui, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    _ = modifiers;

    switch (self._focus) {
        .menubar => |*ix| switch (keycode) {
            .left => {
                if (ix.* == 0)
                    ix.* = self._menubar.?.menus.items.len - 1
                else
                    ix.* -= 1;
            },
            .right => ix.* = (ix.* + 1) % self._menubar.?.menus.items.len,
            .up, .down => self._focus = .{ .menu = .{ .index = ix.*, .item = 0 } },
            .escape => {
                self.text_mode.cursor_inhibit = false;
                self._focus = .unknown; // XXX
            },
            .@"return" => self._focus = .{ .menu = .{ .index = ix.*, .item = 0 } },
            else => {},
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
                    m.item = self._menubar.?.menus.items[m.index].items.items.len - 1
                else
                    m.item -= 1;
                if (self._menubar.?.menus.items[m.index].items.items[m.item] == null)
                    continue;
                break;
            },
            .down => while (true) {
                m.item = (m.item + 1) % self._menubar.?.menus.items[m.index].items.items.len;
                if (self._menubar.?.menus.items[m.index].items.items[m.item] == null)
                    continue;
                break;
            },
            .@"return" => self._menubar.?.menus.items[m.index].items.items[m.item].?._chosen = true,
            else => {},
        },
        else => {},
    }
}

fn handleKeyUp(self: *Imtui, keycode: SDL.Keycode) !void {
    if ((keycode == .left_alt or keycode == .right_alt) and self._alt_held) {
        self._alt_held = false;

        if (self._focus == .menu) {
            self._focus = .{ .menubar = self._focus.menu.index };
        } else if (self._focus != .menubar) {
            self.text_mode.cursor_inhibit = true;
            self._focus = .{ .menubar = 0 };
        } else {
            self.text_mode.cursor_inhibit = false;
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

fn handleMouseDrag(self: *Imtui, button: SDL.MouseButton, old_row: usize, old_col: usize) !void {
    _ = self;
    _ = button;
    _ = old_row;
    _ = old_col;
}

fn handleMouseDown(self: *Imtui, button: SDL.MouseButton, clicks: u8) !void {
    _ = self;
    _ = button;
    _ = clicks;
}

fn handleMouseUp(self: *Imtui, button: SDL.MouseButton, clicks: u8) !void {
    _ = self;
    _ = button;
    _ = clicks;
}

fn interpolateMouse(self: *const Imtui, payload: anytype) struct { x: usize, y: usize } {
    return .{
        .x = @intFromFloat(@as(f32, @floatFromInt(payload.x)) / self.scale),
        .y = @intFromFloat(@as(f32, @floatFromInt(payload.y)) / self.scale),
    };
}