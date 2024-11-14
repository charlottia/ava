const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Shortcut = @This();

imtui: *Imtui,
generation: usize,
shortcut: Imtui.Shortcut,

_chosen: bool = false,

pub fn create(imtui: *Imtui, keycode: SDL.Keycode, modifier: ?Imtui.ShortcutModifier) !*Shortcut {
    const s = try imtui.allocator.create(Shortcut);
    s.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .shortcut = .{ .keycode = keycode, .modifier = modifier },
    };
    return s;
}

pub fn deinit(self: *Shortcut) void {
    self.imtui.allocator.destroy(self);
}

pub fn chosen(self: *Shortcut) bool {
    defer self._chosen = false;
    return self._chosen;
}
