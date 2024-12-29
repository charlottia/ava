const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const ini = @import("ini");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignRoot = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    // state
    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .orphan = true,
                .deinit = deinit,
                .handleKeyPress = handleKeyPress,
                .handleKeyUp = handleKeyUp,
                .isMouseOver = isMouseOver,
                .handleMouseDown = handleMouseDown,
            },
        };
    }

    pub fn describe(_: *Impl) void {}

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.imtui.allocator.destroy(self);
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));

        if (keycode == .left_alt or keycode == .right_alt) {
            var mb = try self.imtui.getMenubar();
            mb.focus = .pre;
            try self.imtui.focus(mb.control());
            return;
        }

        for ((try self.imtui.getMenubar()).menus.items) |m|
            for (m.menu_items.items) |mi| {
                if (mi != null) if (mi.?.shortcut) |s| if (s.matches(keycode, modifiers)) {
                    mi.?.chosen = true;
                    return;
                };
            };

        var cit = self.imtui.controls.valueIterator();
        while (cit.next()) |c|
            if (c.is(Imtui.Controls.Shortcut.Impl)) |s|
                if (s.shortcut.matches(keycode, modifiers)) {
                    s.*.chosen = true;
                    return;
                };
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(_: *const anyopaque) bool {
        return false;
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        return self.imtui.fallbackMouseDown(b, clicks, cm);
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}", .{"designer.DesignRoot"});
}

pub fn create(imtui: *Imtui) !DesignRoot {
    const d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
    };
    return .{ .impl = d };
}
