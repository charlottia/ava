const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

pub const Button = @import("./Button.zig");
pub const Shortcut = @import("./Shortcut.zig");
pub const Menubar = @import("./Menubar.zig");
pub const Menu = @import("./Menu.zig");
pub const MenuItem = @import("./MenuItem.zig");
pub const Source = @import("./Source.zig");
pub const Editor = @import("./Editor.zig");
pub const EditorLike = @import("./EditorLike.zig");
pub const Dialog = @import("./Dialog.zig");
pub const DialogRadio = @import("./DialogRadio.zig");
pub const DialogSelect = @import("./DialogSelect.zig");
pub const DialogCheckbox = @import("./DialogCheckbox.zig");
pub const DialogInput = @import("./DialogInput.zig");
pub const DialogButton = @import("./DialogButton.zig");

pub const MenuItemReference = struct { index: usize, item: usize };

pub fn formatShortcut(allocator: Allocator, shortcut: Imtui.Shortcut) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    const writer = buf.writer(allocator);

    if (shortcut.modifier) |modifier| {
        const tn = @tagName(modifier);
        try std.fmt.format(writer, "{c}{s}+", .{ std.ascii.toUpper(tn[0]), tn[1..] });
    }

    switch (shortcut.keycode) {
        .delete => try writer.writeAll("Del"),
        .insert => try writer.writeAll("Ins"),
        .backslash => try writer.writeByte('\\'),
        .grave => try writer.writeByte('`'),
        else => {
            const tn = @tagName(shortcut.keycode);
            try std.fmt.format(writer, "{c}{s}", .{ std.ascii.toUpper(tn[0]), tn[1..] });
        },
    }
    return buf.toOwnedSlice(allocator);
}

pub fn lenWithoutAccelerators(s: []const u8) usize {
    var len: usize = 0;
    for (s, 0..) |c, i|
        len += if (c == '&' and i != s.len - 1) 0 else 1;
    return len;
}

pub fn acceleratorFor(s: []const u8) ?u8 {
    var next = false;
    for (s) |c| {
        if (next)
            return c;
        if (c == '&')
            next = true;
    }
    return null;
}

pub fn isPrintableKey(keycode: SDL.Keycode) bool {
    return @intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.space) and
        @intFromEnum(keycode) <= @intFromEnum(SDL.Keycode.z);
}

pub fn getCharacter(keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) u8 {
    if (@intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.a) and
        @intFromEnum(keycode) <= @intFromEnum(SDL.Keycode.z))
    {
        if (modifiers.get(.left_shift) or modifiers.get(.right_shift) or modifiers.get(.caps_lock)) {
            return @as(u8, @intCast(@intFromEnum(keycode))) - ('a' - 'A');
        }
        return @intCast(@intFromEnum(keycode));
    }

    if (modifiers.get(.left_shift) or modifiers.get(.right_shift)) {
        for (ShiftTable) |e| {
            if (e.@"0" == keycode)
                return e.@"1";
        }
    }

    return @intCast(@intFromEnum(keycode));
}

const ShiftTable = [_]struct { SDL.Keycode, u8 }{
    .{ .apostrophe, '"' },
    .{ .comma, '<' },
    .{ .minus, '_' },
    .{ .period, '>' },
    .{ .slash, '?' },
    .{ .@"0", ')' },
    .{ .@"1", '!' },
    .{ .@"2", '@' },
    .{ .@"3", '#' },
    .{ .@"4", '$' },
    .{ .@"5", '%' },
    .{ .@"6", '^' },
    .{ .@"7", '&' },
    .{ .@"8", '*' },
    .{ .@"9", '(' },
    .{ .semicolon, ':' },
    .{ .left_bracket, '{' },
    .{ .backslash, '|' },
    .{ .right_bracket, '}' },
    .{ .grave, '~' },
    .{ .equals, '+' },
};
