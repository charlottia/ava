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
            // try qb.keyDown(key.keycode, key.modifiers);
            // try qb.keyPress(key.keycode, key.modifiers);
            self.keydown_tick = SDL.getTicks64();
            self.keydown_sym = key.keycode;
            self.keydown_mod = key.modifiers;
            self.typematic_on = false;
        },
        .key_up => |key| {
            _ = key;
            // try qb.keyUp(key.keycode);
            self.keydown_tick = null;
        },
        .mouse_motion => |motion| {
            const mouse_x: usize = @intFromFloat(@as(f32, @floatFromInt(motion.x)) / self.scale);
            const mouse_y: usize = @intFromFloat(@as(f32, @floatFromInt(motion.y)) / self.scale);
            self.text_mode.positionMouseAt(mouse_x, mouse_y);
            //     const old_x = qb.mouse_x;
            //     const old_y = qb.mouse_y;
            //     if (qb.mouseAt(motion.x, motion.y, scale)) {
            //         if (mouse_down) |button|
            //             try qb.mouseDrag(button, old_x, old_y);
            //         try qb.text_mode.present();
            //     }
        },
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
