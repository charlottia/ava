const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const TextMode = @import("./TextMode.zig").TextMode;
const Font = @import("./Font.zig");

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

// https://ejmastnak.com/tutorials/arch/typematic-rate/
const TYPEMATIC_DELAY_MS = 500;
const TYPEMATIC_REPEAT_MS = 1000 / 25;

pub fn init(allocator: Allocator, renderer: SDL.Renderer, font: *Font, scale: f32) !Imtui {
    return .{
        .allocator = allocator,
        .text_mode = try TextMode(25, 80).init(renderer, font),
        .scale = scale,
        .last_tick = SDL.getTicks64(),
    };
}

pub fn deinit(self: *Imtui) void {
    _ = self;
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

fn interpolateMouse(self: *const Imtui, payload: anytype) struct { x: usize, y: usize } {
    return .{
        .x = @intFromFloat(@as(f32, @floatFromInt(payload.x)) / self.scale),
        .y = @intFromFloat(@as(f32, @floatFromInt(payload.y)) / self.scale),
    };
}

pub fn newFrame(self: *Imtui) !void {
    const this_tick = SDL.getTicks64();
    self.delta_tick = this_tick - self.last_tick;
    defer self.last_tick = this_tick;

    if (self.keydown_tick) |keydown_tick| {
        if (!self.typematic_on and this_tick >= keydown_tick + TYPEMATIC_DELAY_MS) {
            self.typematic_on = true;
            self.keydown_tick = keydown_tick + TYPEMATIC_DELAY_MS;
            // XXX keyPress(self.keydown_sym, self.keydown_mod);
        } else if (self.typematic_on and this_tick >= keydown_tick + TYPEMATIC_REPEAT_MS) {
            self.keydown_tick = keydown_tick + TYPEMATIC_REPEAT_MS;
            // XXX keyPress(self.keydown_sym, self.keydown_mod);
        }
    }
}

pub fn render(self: *Imtui) !void {
    try self.text_mode.present(self.delta_tick);
}

fn handleKeyDown(self: *Imtui, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    _ = self;
    _ = keycode;
    _ = modifiers;
}

fn handleKeyPress(self: *Imtui, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    _ = self;
    _ = keycode;
    _ = modifiers;
}

fn handleKeyUp(self: *Imtui, keycode: SDL.Keycode) !void {
    _ = self;
    _ = keycode;
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
