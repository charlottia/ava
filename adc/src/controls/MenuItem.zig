const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const MenuItem = @This();

imtui: *Imtui,
generation: usize,
label: []const u8,
index: usize,
enabled: bool,
_shortcut: ?Imtui.Shortcut,
help_text: ?[]const u8,

_chosen: bool,

pub fn create(imtui: *Imtui, label: []const u8, index: usize) !*MenuItem {
    var i = try imtui.allocator.create(MenuItem);
    i.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .label = undefined,
        .index = undefined,
        .enabled = undefined,
        ._shortcut = undefined,
        .help_text = undefined,
        ._chosen = false,
    };
    i.describe(label, index);
    return i;
}

pub fn describe(self: *MenuItem, label: []const u8, index: usize) void {
    self.label = label;
    self.index = index;
    self.enabled = true;
    self._shortcut = null;
    self.help_text = null;
}

pub fn deinit(self: *MenuItem) void {
    self.imtui.allocator.destroy(self);
}

pub fn disabled(self: *MenuItem) *MenuItem {
    self.enabled = false;
    return self;
}

pub fn shortcut(self: *MenuItem, keycode: SDL.Keycode, modifier: ?Imtui.ShortcutModifier) *MenuItem {
    self._shortcut = .{ .keycode = keycode, .modifier = modifier };
    return self;
}

pub fn help(self: *MenuItem, text: []const u8) *MenuItem {
    self.help_text = text;
    return self;
}

pub fn chosen(self: *MenuItem) bool {
    defer self._chosen = false;
    return self._chosen;
}