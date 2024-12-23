const std = @import("std");
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Button = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    r: usize = undefined,
    c: usize = undefined,
    colour: u8 = undefined,
    label: []const u8,

    chosen: bool = false,
    inverted: bool = false,

    pub fn control(self: *Impl) Imtui.Control {
        return .{
            .ptr = self,
            .vtable = &.{
                .orphan = true,
                .no_key = true,
                .deinit = deinit,
                .isMouseOver = isMouseOver,
                .handleMouseDown = handleMouseDown,
                .handleMouseDrag = handleMouseDrag,
                .handleMouseUp = handleMouseUp,
            },
        };
    }

    pub fn describe(self: *Impl, r: usize, c: usize, colour: u8, _: []const u8) void {
        self.r = r;
        self.c = c;
        self.colour = if (self.inverted)
            ((colour & 0x0f) << 4) | ((colour & 0xf0) >> 4)
        else
            colour;
        self.imtui.text_mode.paint(r, c, r + 1, c + self.label.len, self.colour, .Blank);
        self.imtui.text_mode.write(r, c, self.label);
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.imtui.allocator.destroy(self);
    }

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.imtui.mouse_row == self.r and self.imtui.mouse_col >= self.c and self.imtui.mouse_col < self.c + self.label.len;
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;
        _ = clicks;

        if (cm) return null;
        if (!isMouseOver(ptr)) return null;

        self.inverted = true;

        return self.control();
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;

        self.inverted = isMouseOver(ptr);
    }

    fn handleMouseUp(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;
        _ = clicks;

        if (self.inverted) {
            self.inverted = false;
            self.chosen = true;
        }
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, _: usize, _: usize, _: u8, label: []const u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}/{s}", .{ "core.Button", label });
}

pub fn create(imtui: *Imtui, r: usize, c: usize, colour: u8, label: []const u8) !Button {
    var b = try imtui.allocator.create(Impl);
    b.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .label = label,
    };
    b.describe(r, c, colour, label);
    return .{ .impl = b };
}

pub fn chosen(self: Button) bool {
    defer self.impl.chosen = false;
    return self.impl.chosen;
}
