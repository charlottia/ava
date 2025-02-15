const std = @import("std");
const Allocator = std.mem.Allocator;
const imtuilib = @import("imtui");
const ini = @import("ini");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;
const Designer = @import("./Designer.zig");

const DesignRoot = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    designer: *Designer,

    // state
    editing_text: bool = undefined,
    focus_idle: bool = undefined,

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

    pub fn describe(self: *Impl) void {
        self.editing_text = false;
        self.focus_idle = false;
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.imtui.allocator.destroy(self);
    }

    fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        return self.imtui.fallbackKeyPress(keycode, modifiers);
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(_: *const anyopaque) bool {
        return false;
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        return (try self.imtui.fallbackMouseDown(b, clicks, cm) orelse return null).@"0";
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, _: *Designer) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}", .{"designer.DesignRoot"});
}

pub fn create(imtui: *Imtui, designer: *Designer) !DesignRoot {
    const d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .designer = designer,
    };
    return .{ .impl = d };
}
