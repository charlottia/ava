const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const TextMode = @import("./TextMode.zig").TextMode;
const Font = @import("./Font.zig");

const Imtui = @This();

allocator: Allocator,
text_mode: TextMode(25, 80),

running: bool = true,

last_tick: u64,
hwcursor_flip_timer: i16 = HWCURSOR_FLIP_MS, // XXX? imelik tunne

keydown_tick: u64 = 0,
keydown_sym: SDL.Keycode = .unknown,
keydown_mod: SDL.KeyModifierSet = undefined,
typematic_on: bool = false,

mouse_down: ?SDL.MouseButton = null,

// https://retrocomputing.stackexchange.com/a/27805/20624
const HWCURSOR_FLIP_MS = 266;

// https://ejmastnak.com/tutorials/arch/typematic-rate/
const TYPEMATIC_DELAY_MS = 500;
const TYPEMATIC_REPEAT_MS = 1000 / 25;

pub fn init(allocator: Allocator, renderer: SDL.Renderer, font: *Font) !Imtui {
    return .{
        .allocator = allocator,
        .text_mode = try TextMode(25, 80).init(renderer, font),
        .last_tick = SDL.getTicks64(),
    };
}

pub fn deinit(self: *Imtui) void {
    _ = self;
}

pub fn processEvent(self: *Imtui, ev: SDL.Event) void {
    switch (ev) {
        // .key_down => |key| {
        //     if (key.is_repeat) break;
        //     try qb.keyDown(key.keycode, key.modifiers);
        //     try qb.keyPress(key.keycode, key.modifiers);
        //     keydown_tick = SDL.getTicks64();
        //     keydown_sym = key.keycode;
        //     keydown_mod = key.modifiers;
        //     typematic_on = false;
        // },
        // .key_up => |key| {
        //     try qb.keyUp(key.keycode);
        //     keydown_tick = 0;
        // },
        // .mouse_motion => |motion| {
        //     const old_x = qb.mouse_x;
        //     const old_y = qb.mouse_y;
        //     if (qb.mouseAt(motion.x, motion.y, scale)) {
        //         if (mouse_down) |button|
        //             try qb.mouseDrag(button, old_x, old_y);
        //         try qb.text_mode.present();
        //     }
        // },
        // .mouse_button_down => |button| {
        //     if (qb.mouseAt(button.x, button.y, scale))
        //         try qb.text_mode.present();
        //     try qb.mouseDown(button.button, button.clicks);
        //     mouse_down = button.button;
        // },
        // .mouse_button_up => |button| {
        //     if (qb.mouseAt(button.x, button.y, scale))
        //         try qb.text_mode.present();
        //     try qb.mouseUp(button.button, button.clicks);
        //     mouse_down = null;
        // },
        .quit => self.running = false,
        else => {},
    }
}

pub fn newFrame(self: *Imtui) !void {
    const this_tick = SDL.getTicks64();
    const delta_tick = this_tick - self.last_tick;
    defer self.last_tick = this_tick;

    self.hwcursor_flip_timer -= @intCast(delta_tick);
    if (self.hwcursor_flip_timer <= 0) {
        self.hwcursor_flip_timer += HWCURSOR_FLIP_MS;
        self.text_mode.cursor_on = !self.text_mode.cursor_on;
    }

    if (self.keydown_tick > 0 and !self.typematic_on and this_tick >= self.keydown_tick + TYPEMATIC_DELAY_MS) {
        self.typematic_on = true;
        self.keydown_tick = self.keydown_tick + TYPEMATIC_DELAY_MS;
        // XXX keyPress(self.keydown_sym, self.keydown_mod);
    } else if (self.keydown_tick > 0 and self.typematic_on and this_tick >= self.keydown_tick + TYPEMATIC_REPEAT_MS) {
        self.keydown_tick = self.keydown_tick + TYPEMATIC_REPEAT_MS;
        // XXX keyPress(self.keydown_sym, self.keydown_mod);
    }
}

pub fn render(self: *Imtui) !void {
    try self.text_mode.present();
}
