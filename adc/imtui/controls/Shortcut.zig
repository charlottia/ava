const std = @import("std");
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Shortcut = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,
    shortcut: Imtui.Shortcut,

    chosen: bool = false,

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .orphan = true,
                .no_mouse = true,
                .no_key = true,
                .deinit = deinit,
                .generationGet = generationGet,
                .generationSet = generationSet,
            },
        };
    }

    pub fn describe(_: *Impl, _: SDL.Keycode, _: ?Imtui.ShortcutModifier) void {}

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.imtui.allocator.destroy(self);
    }

    fn generationGet(ptr: *const anyopaque) usize {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.generation;
    }

    fn generationSet(ptr: *anyopaque, n: usize) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.generation = n;
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, keycode: SDL.Keycode, modifier: ?Imtui.ShortcutModifier) ![]const u8 {
    return try std.fmt.bufPrint(buf, "core.Shortcut/{s}/{s}", .{
        @tagName(keycode),
        if (modifier) |m| @tagName(m) else "none",
    });
}

pub fn create(imtui: *Imtui, keycode: SDL.Keycode, modifier: ?Imtui.ShortcutModifier) !Shortcut {
    const s = try imtui.allocator.create(Impl);
    s.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .shortcut = .{ .keycode = keycode, .modifier = modifier },
    };
    s.describe(keycode, modifier);
    return .{ .impl = s };
}

pub fn chosen(self: Shortcut) bool {
    defer self.impl.chosen = false;
    return self.impl.chosen;
}
