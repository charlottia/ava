const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const MenuItem = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,
    label: []const u8 = undefined,
    index: usize = undefined,
    enabled: bool = undefined,
    shortcut: ?Imtui.Shortcut = undefined,
    bullet: bool = undefined,
    help: ?[]const u8 = undefined,

    chosen: bool = false,

    pub fn describe(self: *Impl, label: []const u8, index: usize) void {
        self.label = label;
        self.index = index;
        self.enabled = true;
        self.shortcut = null;
        self.bullet = false;
        self.help = null;
    }

    pub fn deinit(self: *Impl) void {
        self.imtui.allocator.destroy(self);
    }
};

impl: *Impl,

pub fn create(imtui: *Imtui, label: []const u8, index: usize) !MenuItem {
    var i = try imtui.allocator.create(Impl);
    i.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
    };
    i.describe(label, index);
    return .{ .impl = i };
}

pub fn disabled(self: MenuItem) MenuItem {
    self.impl.enabled = false;
    return self;
}

pub fn shortcut(self: MenuItem, keycode: SDL.Keycode, modifier: ?Imtui.ShortcutModifier) MenuItem {
    self.impl.shortcut = .{ .keycode = keycode, .modifier = modifier };
    return self;
}

pub fn help(self: MenuItem, text: []const u8) MenuItem {
    self.impl.help = text;
    return self;
}

pub fn bullet(self: MenuItem) void {
    self.impl.bullet = true;
}

pub fn chosen(self: MenuItem) bool {
    defer self.impl.chosen = false;
    return self.impl.chosen;
}
