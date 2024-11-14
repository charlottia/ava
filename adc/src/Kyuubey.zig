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
