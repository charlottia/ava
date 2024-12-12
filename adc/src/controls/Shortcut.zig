const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Shortcut = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,
    shortcut: Imtui.Shortcut,

    chosen: bool = false,

    pub fn deinit(self: *Impl) void {
        self.imtui.allocator.destroy(self);
    }
};

impl: *Impl,

pub fn create(imtui: *Imtui, keycode: SDL.Keycode, modifier: ?Imtui.ShortcutModifier) !Shortcut {
    const s = try imtui.allocator.create(Impl);
    s.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .shortcut = .{ .keycode = keycode, .modifier = modifier },
    };
    return .{ .impl = s };
}

pub fn chosen(self: Shortcut) bool {
    defer self.impl.chosen = false;
    return self.impl.chosen;
}
