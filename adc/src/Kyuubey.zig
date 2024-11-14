const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Font = @import("./Font.zig");
const TextMode = @import("./TextMode.zig").TextMode;
const Editor = @import("./Editor.zig");

const Kyuubey = @This();

allocator: Allocator,
text_mode: TextMode(25, 80),
char_width: usize, // XXX: abstraction leak, should happen in IMTUI
char_height: usize, // XXX: abstraction leak, should happen in IMTUI

mouse_x: usize = 100,
mouse_y: usize = 100,

alt_held: bool = false,
menubar_focus: bool = false,
selected_menu: usize = 0,
menu_open: bool = false,
selected_menu_item: usize = 0,

editors: [3]Editor,
editor_active: usize,
split_active: bool,

pub fn keyPress(self: *Kyuubey, sym: SDL.Keycode, mod: SDL.KeyModifierSet) !void {
    _ = mod;

    if (sym == .f6) {
        const prev = self.activeEditor();
        var next_index = (self.editor_active + 1) % self.editors.len;
        if (self.editors[next_index].kind == .secondary and !self.split_active)
            next_index += 1;
        const next = &self.editors[next_index];
        self.editor_active = next_index;

        if (prev.fullscreened != null) {
            prev.toggleFullscreen();
            next.toggleFullscreen();
        }
        self.render();
        try self.text_mode.present();
        return;
    }

    if (sym == .f7) {
        // XXX: this doesn't belong on F7, I just don't have menus yet.
        try self.toggleSplit();
        self.render();
        try self.text_mode.present();
        return;
    }
}

pub fn mouseDown(self: *Kyuubey, button: SDL.MouseButton, clicks: u8) !void {
    const x = self.mouse_x / self.char_width;
    const y = self.mouse_y / self.char_height;

    const active_editor = self.activeEditor();
    if (active_editor.fullscreened != null) {
        _ = active_editor.handleMouseDown(true, button, clicks, x, y);
    } else for (&self.editors, 0..) |*e, i| {
        if (!self.split_active and e.kind == .secondary)
            continue;
        if (e.handleMouseDown(self.editor_active == i, button, clicks, x, y)) {
            self.editor_active = i;
            break;
        }
    }

    self.render();
    try self.text_mode.present();
}

pub fn mouseUp(self: *Kyuubey, button: SDL.MouseButton, clicks: u8) !void {
    const x = self.mouse_x / self.char_width;
    const y = self.mouse_y / self.char_height;

    self.activeEditor().handleMouseUp(button, clicks, x, y);

    self.render();
    try self.text_mode.present();
}

pub fn mouseDrag(self: *Kyuubey, button: SDL.MouseButton, old_x_px: usize, old_y_px: usize) !void {
    const old_x = old_x_px / self.char_width;
    const old_y = old_y_px / self.char_height;

    const x = self.mouse_x / self.char_width;
    const y = self.mouse_y / self.char_height;

    if (old_x == x and old_y == y)
        return;

    const active_editor = self.activeEditor();
    if (active_editor.top != 1 and old_y == active_editor.top and y != old_y) {
        // Resizing a window. Constraints:
        // * Immediate can be at most 10 high.
        // * Any window can be as small as 0 high.
        // * Pulling a window across another one moves that one along with it.

    }

    _ = button;
}

fn toggleSplit(self: *Kyuubey) !void {
    // TODO: does QB do anything fancy with differently-sized immediates? For now
    // we just reset to the default view.
    //
    // Immediate window max height is 10.
    // Means there's always room to split with 5+5. Uneven split favours bottom.

    // QB split always leaves the view in non-fullscreen, with primary editor selected.

    for (&self.editors) |*e|
        if (e.fullscreened != null)
            e.toggleFullscreen();

    self.editor_active = 0;

    if (!self.split_active) {
        std.debug.assert(self.editors[0].height >= 11);
        try self.editors[1].loadFrom(&self.editors[0]);
        self.editors[0].height = 9;
        self.editors[1].height = 9;
        self.editors[1].top = 11;
        self.split_active = true;
    } else {
        self.editors[0].height += self.editors[1].height + 1;
        self.split_active = false;
    }
}
