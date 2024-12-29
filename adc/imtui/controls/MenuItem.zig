const SDL = @import("sdl2");

// Not a Control in the separately-dispatchable sense.

const Imtui = @import("../Imtui.zig");

const MenuItem = @This();

pub const Impl = struct {
    // XXX: for now we explicitly support taking ownership of item labels, but not help texts.
    imtui: *Imtui,
    menu: *Imtui.Controls.Menu.Impl,
    label: []const u8,
    index: usize = undefined,
    enabled: bool = undefined,
    shortcut: ?Imtui.Shortcut = undefined,
    bullet: bool = undefined,
    help: ?[]const u8 = undefined,

    chosen: bool = false,
    rendered_shortcut: ?[]const u8 = null,

    pub fn describe(self: *Impl, label: []const u8, index: usize) !void {
        self.label = try self.imtui.describeValue(self.label, label);
        self.index = index;
        self.enabled = true;
        self.shortcut = null;
        self.bullet = false;
        self.help = null;
    }

    pub fn deinit(self: *Impl) void {
        if (self.rendered_shortcut) |rs| self.imtui.allocator.free(rs);
        self.imtui.allocator.free(self.label);
        self.imtui.allocator.destroy(self);
    }

    pub fn renderedShortcut(self: *Impl) !?[]const u8 {
        // we assume these do not change ever
        if (self.shortcut == null)
            return null;

        if (self.rendered_shortcut == null)
            self.rendered_shortcut = try Imtui.Controls.formatShortcut(self.imtui.allocator, self.shortcut.?);

        return self.rendered_shortcut;
    }
};

impl: *Impl,

pub fn create(menu: *Imtui.Controls.Menu.Impl, label: []const u8, index: usize) !MenuItem {
    var i = try menu.imtui.allocator.create(Impl);
    i.* = .{
        .imtui = menu.imtui,
        .menu = menu,
        .label = try menu.imtui.allocator.dupe(u8, label),
    };
    try i.describe(label, index);
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
    if (self.impl.chosen)
        self.impl.menu.menubar.unfocus();
    return self.impl.chosen;
}
