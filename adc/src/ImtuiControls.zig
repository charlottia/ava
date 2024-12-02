const std = @import("std");

const Imtui = @import("./Imtui.zig");

pub const Button = @import("./controls/Button.zig");
pub const Shortcut = @import("./controls/Shortcut.zig");
pub const Menubar = @import("./controls/Menubar.zig");
pub const Menu = @import("./controls/Menu.zig");
pub const MenuItem = @import("./controls/MenuItem.zig");
pub const Editor = @import("./controls/Editor.zig");
pub const Dialog = @import("./controls/Dialog.zig");
pub const DialogRadio = @import("./controls/DialogRadio.zig");
pub const DialogSelect = @import("./controls/DialogSelect.zig");
pub const DialogCheckbox = @import("./controls/DialogCheckbox.zig");
pub const DialogInput = @import("./controls/DialogInput.zig");
pub const DialogButton = @import("./controls/DialogButton.zig");

pub const MenuItemReference = struct { index: usize, item: usize };

pub fn formatShortcut(buf: []u8, shortcut: Imtui.Shortcut) []const u8 {
    var i: usize = 0;
    if (shortcut.modifier) |modifier| {
        const tn = @tagName(modifier);
        buf[i] = std.ascii.toUpper(tn[0]);
        @memcpy(buf[i + 1 ..][0 .. tn.len - 1], tn[1..]);
        buf[i + tn.len] = '+';
        i += tn.len + 1;
    }
    switch (shortcut.keycode) {
        .delete => {
            @memcpy(buf[i..][0..3], "Del");
            i += 3;
        },
        .insert => {
            @memcpy(buf[i..][0..3], "Ins");
            i += 3;
        },
        .backslash => {
            buf[i] = '\\';
            i += 1;
        },
        else => {
            const tn = @tagName(shortcut.keycode);
            buf[i] = std.ascii.toUpper(tn[0]);
            @memcpy(buf[i + 1 ..][0 .. tn.len - 1], tn[1..]);
            i += tn.len;
        },
    }
    return buf[0..i];
}

pub fn lenWithoutAccelerators(s: []const u8) usize {
    var len: usize = 0;
    for (s) |c|
        len += if (c == '&') 0 else 1;
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
