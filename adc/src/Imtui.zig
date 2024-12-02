const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const TextMode = @import("./TextMode.zig").TextMode;
const Font = @import("./Font.zig");

pub const Controls = @import("./ImtuiControls.zig");

const Imtui = @This();

allocator: Allocator,
text_mode: TextMode(25, 80),
scale: f32,

running: bool = true,
generation: usize = 0,

last_tick: u64,
delta_tick: u64 = 0,

keydown_sym: SDL.Keycode = .unknown,
keydown_mod: SDL.KeyModifierSet = .{ .storage = 0 },
typematic_on: bool = false,
typematic_tick: ?u64 = null,

mouse_row: usize = 0,
mouse_col: usize = 0,
mouse_down: ?SDL.MouseButton = null,
mouse_event_target: ?Control = null,
// Clickmatic requires a model shift above: we want to continue dispatching
// click events to the same target, as long as our cursor position remains over
// that same target. The tricky part is defining what a target is: one example
// is one of the click-to-move-1 scrollbar ends ("<", ">", "^", "v"). Those are
// unit-sized so it makes sense that dragging your mouse away from it doesn't
// continue to trigger it, and triggers resume if you drag your mouse back.
// On the other hand, we have the scroll bar area the thumb tracks in: it's
// split in two (if not scrolled all the way to one end), with a click and
// drag in the region of one allowing repeated triggers on that space. Query:
// is the valid target the _original_ space, or does it shrink/vanish?
// Answer: it does shrink! You have to keep moving the mouse to it to keep
// scrolling.
//
// Follow-up question: what state do we need to store to match that target? What
// would identify a target? It updates over time so we definitely need to get an
// object we can query each frame.
// Answer: We can maybe just use the mouse_event_target and ask it to do any
// more specific matching required.
// Action item: check all references to mouse_event_target & verify the
// semantics will hold up.
// Notes:
// - mouse_event_target is only set for Buttons and Editors at present.
// - handleMouseDrag is only called on mouse_event_targets.
// - handleMouseUp is also only called on mouse_event_targets (and clears
//   mouse_event_target).
// This is plenty; the main things it needs to work on are scroll-related, which
// are all contained within Editor.
clickmatic_on: bool = false,
clickmatic_tick: ?u64 = null, // Only set when a mouse_event_target is moused down on.

alt_held: bool = false,
focus: union(enum) {
    editor,
    menubar: struct { index: usize, open: bool },
    menu: Controls.MenuItemReference,
    dialog,
} = .editor,
focus_editor: usize = 0,
focus_dialog: *Controls.Dialog = undefined,

controls: std.StringHashMapUnmanaged(Control) = .{},

const Control = union(enum) {
    button: *Controls.Button,
    shortcut: *Controls.Shortcut,
    menubar: *Controls.Menubar,
    menu: *Controls.Menu,
    menu_item: *Controls.MenuItem,
    editor: *Controls.Editor,
    dialog: *Controls.Dialog,

    fn generation(self: Control) usize {
        return switch (self) {
            inline else => |c| c.generation,
        };
    }

    fn setGeneration(self: Control, n: usize) void {
        switch (self) {
            inline else => |c| c.generation = n,
        }
    }

    fn deinit(self: Control) void {
        switch (self) {
            inline else => |c| c.deinit(),
        }
    }

    fn handleMouseDrag(self: Control, b: SDL.MouseButton) !void {
        switch (self) {
            inline else => |c| if (@hasDecl(@TypeOf(c.*), "handleMouseDrag")) {
                try c.handleMouseDrag(b);
            },
        }
    }

    fn handleMouseUp(self: Control, b: SDL.MouseButton, clicks: u8) !void {
        switch (self) {
            inline else => |c| if (@hasDecl(@TypeOf(c.*), "handleMouseUp")) {
                try c.handleMouseUp(b, clicks);
            },
        }
    }
};

pub const ShortcutModifier = enum { shift, alt, ctrl };

pub const Shortcut = struct {
    keycode: SDL.Keycode,
    modifier: ?ShortcutModifier,

    pub fn matches(self: Shortcut, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) bool {
        if (keycode != self.keycode) return false;
        return (modifiers.get(.left_shift) or modifiers.get(.right_shift)) == (self.modifier == .shift) and
            (modifiers.get(.left_alt) or modifiers.get(.right_alt)) == (self.modifier == .alt) and
            (modifiers.get(.left_control) or modifiers.get(.right_control)) == (self.modifier == .ctrl);
    }
};

// https://ejmastnak.com/tutorials/arch/typematic-rate/
const TYPEMATIC_DELAY_MS = 500;
const TYPEMATIC_REPEAT_MS = 1000 / 25;

const CLICKMATIC_DELAY_MS = 500;
const CLICKMATIC_REPEAT_MS = 1000 / 8;

pub fn init(allocator: Allocator, renderer: SDL.Renderer, font: Font, scale: f32) !*Imtui {
    const imtui = try allocator.create(Imtui);
    imtui.* = .{
        .allocator = allocator,
        .text_mode = try TextMode(25, 80).init(renderer, font),
        .scale = scale,
        .last_tick = SDL.getTicks64(),
    };
    return imtui;
}

pub fn deinit(self: *Imtui) void {
    var cit = self.controls.iterator();
    while (cit.next()) |c| {
        self.allocator.free(c.key_ptr.*);
        c.value_ptr.deinit();
    }
    self.controls.deinit(self.allocator);

    self.text_mode.deinit();

    self.allocator.destroy(self);
}

pub fn processEvent(self: *Imtui, event: SDL.Event) !void {
    switch (event) {
        .key_down => |key| {
            if (key.is_repeat) return;
            try self.handleKeyPress(key.keycode, key.modifiers);
            self.keydown_sym = key.keycode;
            self.keydown_mod = key.modifiers;
            self.typematic_on = false;
            self.typematic_tick = SDL.getTicks64();
        },
        .key_up => |key| {
            // We don't try to match key down to up.
            try self.handleKeyUp(key.keycode);
            self.typematic_tick = null;
        },
        .mouse_motion => |ev| {
            const pos = self.interpolateMouse(ev);
            self.text_mode.positionMouseAt(pos.x, pos.y);
            if (self.handleMouseAt(self.text_mode.mouse_row, self.text_mode.mouse_col))
                if (self.mouse_down) |b| {
                    try self.handleMouseDrag(b);
                };
        },
        .mouse_button_down => |ev| {
            const pos = self.interpolateMouse(ev);
            self.text_mode.positionMouseAt(pos.x, pos.y);
            _ = self.handleMouseAt(self.text_mode.mouse_row, self.text_mode.mouse_col);
            self.mouse_event_target = try self.handleMouseDown(ev.button, ev.clicks, false);
            self.mouse_down = ev.button;
            self.clickmatic_on = false;
            if (self.mouse_event_target != null)
                self.clickmatic_tick = SDL.getTicks64();
        },
        .mouse_button_up => |ev| {
            const pos = self.interpolateMouse(ev);
            self.text_mode.positionMouseAt(pos.x, pos.y);
            _ = self.handleMouseAt(self.text_mode.mouse_row, self.text_mode.mouse_col);
            try self.handleMouseUp(ev.button, ev.clicks);
            self.mouse_event_target = null;
            self.mouse_down = null;
            self.clickmatic_tick = null;
        },
        .mouse_wheel => |ev| {
            if (ev.delta_y < 0)
                try self.handleKeyPress(.down, .{ .storage = 0 })
            else if (ev.delta_y > 0)
                try self.handleKeyPress(.up, .{ .storage = 0 });
        },
        .window => |ev| {
            if (ev.type == .close)
                self.running = false;
        },
        .quit => self.running = false,
        else => {},
    }
}

pub fn render(self: *Imtui) !void {
    self.text_mode.cursor_inhibit = self.text_mode.cursor_inhibit or self.focus == .menu or self.focus == .menubar;
    try self.text_mode.present(self.delta_tick);
}

pub fn newFrame(self: *Imtui) !void {
    self.text_mode.cursor_inhibit = false;

    var cit = self.controls.iterator();
    while (cit.next()) |c| {
        if (c.value_ptr.generation() != self.generation) {
            self.allocator.free(c.key_ptr.*);
            c.value_ptr.deinit();
            self.controls.removeByPtr(c.key_ptr);

            cit = self.controls.iterator();
        }
    }

    self.generation += 1;

    const this_tick = SDL.getTicks64();
    self.delta_tick = this_tick - self.last_tick;
    defer self.last_tick = this_tick;

    if (self.typematic_tick) |typematic_tick| {
        if (!self.typematic_on and this_tick >= typematic_tick + TYPEMATIC_DELAY_MS) {
            self.typematic_on = true;
            self.typematic_tick = typematic_tick + TYPEMATIC_DELAY_MS;
            try self.handleKeyPress(self.keydown_sym, self.keydown_mod);
        } else if (self.typematic_on and this_tick >= typematic_tick + TYPEMATIC_REPEAT_MS) {
            self.typematic_tick = typematic_tick + TYPEMATIC_REPEAT_MS;
            try self.handleKeyPress(self.keydown_sym, self.keydown_mod);
        }
    }

    if (self.clickmatic_tick) |clickmatic_tick| {
        var trigger = false;
        if (!self.clickmatic_on and this_tick >= clickmatic_tick + CLICKMATIC_DELAY_MS) {
            self.clickmatic_on = true;
            self.clickmatic_tick = clickmatic_tick + CLICKMATIC_DELAY_MS;
            trigger = true;
        } else if (self.clickmatic_on and this_tick >= clickmatic_tick + CLICKMATIC_REPEAT_MS) {
            self.clickmatic_tick = clickmatic_tick + CLICKMATIC_REPEAT_MS;
            trigger = true;
        }

        const target = self.mouse_event_target.?; // Assumed to be present if clickmatic_tick is.
        if (trigger)
            switch (target) {
                .button => |bu| try bu.handleMouseDown(self.mouse_down.?, 0),
                .editor => |e| try e.handleMouseDown(self.mouse_down.?, 0, true),
                else => {},
            };
    }

    self.text_mode.clear(0x07);
}

fn controlById(self: *Imtui, comptime tag: std.meta.Tag(Control), id: []const u8) ?std.meta.TagPayload(Control, tag) {
    // We remove invalidated objects here (in addition to newFrame), since
    // a null return here will often be followed by a putNoClobber on
    // self.controls.
    const e = self.controls.getEntry(id) orelse return null;
    if (e.value_ptr.generation() >= self.generation - 1) {
        e.value_ptr.setGeneration(self.generation);
        switch (e.value_ptr.*) {
            tag => |p| return p,
            else => unreachable,
        }
    }

    self.allocator.free(e.key_ptr.*);
    e.value_ptr.deinit();
    self.controls.removeByPtr(e.key_ptr);
    return null;
}

pub fn getMenubar(self: *Imtui) ?*Controls.Menubar {
    return self.controlById(.menubar, "menubar");
}

pub fn openMenu(self: *Imtui) ?*Controls.Menu {
    switch (self.focus) {
        .menubar => |mb| if (mb.open) return self.getMenubar().?.menus.items[mb.index],
        .menu => |m| return self.getMenubar().?.menus.items[m.index],
        else => {},
    }
    return null;
}

pub fn focusedEditor(self: *Imtui) !*Controls.Editor {
    // XXX: this is ridiculous and i cant take it seriously
    var buf: [10]u8 = undefined; // editor.XYZ
    const key = try std.fmt.bufPrint(&buf, "editor.{d}", .{self.focus_editor});
    return self.controlById(.editor, key).?;
}

pub fn menubar(self: *Imtui, r: usize, c1: usize, c2: usize) !*Controls.Menubar {
    if (self.controlById(.menubar, "menubar")) |mb| {
        mb.describe(r, c1, c2);
        return mb;
    }

    const mb = try Controls.Menubar.create(self, r, c1, c2);
    try self.controls.putNoClobber(self.allocator, try self.allocator.dupe(u8, "menubar"), .{ .menubar = mb });
    return mb;
}

pub fn editor(self: *Imtui, editor_id: usize, r1: usize, c1: usize, r2: usize, c2: usize) !*Controls.Editor {
    var buf: [10]u8 = undefined; // editor.XYZ
    const key = try std.fmt.bufPrint(&buf, "editor.{d}", .{editor_id});
    if (self.controlById(.editor, key)) |e| {
        e.describe(r1, c1, r2, c2);
        return e;
    }

    const e = try Controls.Editor.create(self, editor_id, r1, c1, r2, c2);
    try self.controls.putNoClobber(self.allocator, try self.allocator.dupe(u8, key), .{ .editor = e });
    return e;
}

pub fn button(self: *Imtui, r: usize, c: usize, colour: u8, label: []const u8) !*Controls.Button {
    var buf: [60]u8 = undefined; // button.blahblahblahblahblah
    const key = try std.fmt.bufPrint(&buf, "button.{s}", .{label});
    if (self.controlById(.button, key)) |b| {
        b.describe(r, c, colour);
        return b;
    }

    const b = try Controls.Button.create(self, r, c, colour, label);
    try self.controls.putNoClobber(self.allocator, try self.allocator.dupe(u8, key), .{ .button = b });
    return b;
}

pub fn shortcut(self: *Imtui, keycode: SDL.Keycode, modifier: ?ShortcutModifier) !*Controls.Shortcut {
    var buf: [60]u8 = undefined; // shortcut.left_parenthesis.shift
    const key = try std.fmt.bufPrint(&buf, "shortcut.{s}.{s}", .{ @tagName(keycode), if (modifier) |m| @tagName(m) else "none" });
    if (self.controlById(.shortcut, key)) |s|
        return s;

    const s = try Controls.Shortcut.create(self, keycode, modifier);
    try self.controls.putNoClobber(self.allocator, try self.allocator.dupe(u8, key), .{ .shortcut = s });
    return s;
}

pub fn dialog(self: *Imtui, title: []const u8, height: usize, width: usize) !*Controls.Dialog {
    self.focus = .dialog;

    var buf: [100]u8 = undefined; // dialog.blahblahblahblahblah
    const key = try std.fmt.bufPrint(&buf, "dialog.{s}", .{title});
    if (self.controlById(.dialog, key)) |d| {
        self.focus_dialog = d;
        d.describe(height, width);
        return d;
    }

    const d = try Controls.Dialog.create(self, title, height, width);
    self.focus_dialog = d;
    try self.controls.putNoClobber(self.allocator, try self.allocator.dupe(u8, key), .{ .dialog = d });
    return d;
}

fn handleKeyPress(self: *Imtui, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    if (self.focus == .dialog)
        return try self.focus_dialog.handleKeyPress(keycode, modifiers);

    if ((keycode == .left_alt or keycode == .right_alt) and !self.alt_held) {
        self.alt_held = true;
        return;
    }

    if ((self.focus == .menubar or self.focus == .menu) and self.mouse_down != null)
        return;

    if (self.alt_held and keycodeAlphanum(keycode)) {
        for (self.getMenubar().?.menus.items, 0..) |m, mix|
            if (acceleratorMatch(m.label, keycode)) {
                self.alt_held = false;
                self.focus = .{ .menu = .{ .index = mix, .item = 0 } };
                return;
            };
    }

    switch (self.focus) {
        .menubar => |*mb| switch (keycode) {
            .left => {
                if (mb.index == 0)
                    mb.index = self.getMenubar().?.menus.items.len - 1
                else
                    mb.index -= 1;
                return;
            },
            .right => {
                mb.index = (mb.index + 1) % self.getMenubar().?.menus.items.len;
                return;
            },
            .up, .down => {
                self.focus = .{ .menu = .{ .index = mb.index, .item = 0 } };
                return;
            },
            .escape => {
                self.focus = .editor;
                return;
            },
            .@"return" => {
                self.focus = .{ .menu = .{ .index = mb.index, .item = 0 } };
                return;
            },
            else => if (keycodeAlphanum(keycode)) {
                for (self.getMenubar().?.menus.items, 0..) |m, mix|
                    if (acceleratorMatch(m.label, keycode)) {
                        self.focus = .{ .menu = .{ .index = mix, .item = 0 } };
                        return;
                    };
            },
        },
        .menu => |*m| switch (keycode) {
            .left => {
                m.item = 0;
                if (m.index == 0)
                    m.index = self.getMenubar().?.menus.items.len - 1
                else
                    m.index -= 1;
                return;
            },
            .right => {
                m.item = 0;
                m.index = (m.index + 1) % self.getMenubar().?.menus.items.len;
                return;
            },
            .up => while (true) {
                if (m.item == 0)
                    m.item = self.getMenubar().?.menus.items[m.index].menu_items.items.len - 1
                else
                    m.item -= 1;
                if (self.getMenubar().?.menus.items[m.index].menu_items.items[m.item] == null)
                    continue;
                return;
            },
            .down => while (true) {
                m.item = (m.item + 1) % self.getMenubar().?.menus.items[m.index].menu_items.items.len;
                if (self.getMenubar().?.menus.items[m.index].menu_items.items[m.item] == null)
                    continue;
                return;
            },
            .escape => {
                self.focus = .editor;
                return;
            },
            .@"return" => {
                self.getMenubar().?.menus.items[m.index].menu_items.items[m.item].?._chosen = true;
                self.focus = .editor;
                return;
            },
            else => if (keycodeAlphanum(keycode)) {
                for (self.getMenubar().?.menus.items[m.index].menu_items.items) |mi|
                    if (mi != null and acceleratorMatch(mi.?.label, keycode)) {
                        mi.?._chosen = true;
                        self.focus = .editor;
                        return;
                    };
            },
        },
        .editor => {
            const e = try self.focusedEditor();
            try e.handleKeyPress(keycode, modifiers);
        },
        .dialog => unreachable, // handled above
    }

    for (self.getMenubar().?.menus.items) |m|
        for (m.menu_items.items) |mi| {
            if (mi != null) if (mi.?._shortcut) |s| if (s.matches(keycode, modifiers)) {
                mi.?._chosen = true;
                return;
            };
        };

    var cit = self.controls.valueIterator();
    while (cit.next()) |c|
        switch (c.*) {
            .shortcut => |s| if (s.shortcut.matches(keycode, modifiers)) {
                s.*._chosen = true;
                return;
            },
            else => {},
        };
}

fn handleKeyUp(self: *Imtui, keycode: SDL.Keycode) !void {
    if (self.focus == .dialog)
        return try self.focus_dialog.handleKeyUp(keycode);

    if ((keycode == .left_alt or keycode == .right_alt) and self.alt_held) {
        self.alt_held = false;

        if (self.focus == .menu) {
            self.focus = .{ .menubar = .{ .index = self.focus.menu.index, .open = false } };
        } else if (self.focus != .menubar) {
            self.focus = .{ .menubar = .{ .index = 0, .open = false } };
        } else {
            self.focus = .editor;
        }
    }

    if (self.focus == .editor) {
        const e = try self.focusedEditor();
        try e.handleKeyUp(keycode);
    }
}

fn handleMouseAt(self: *Imtui, row: usize, col: usize) bool {
    const old_mouse_row = self.mouse_row;
    const old_mouse_col = self.mouse_col;

    self.mouse_row = row;
    self.mouse_col = col;

    return old_mouse_row != self.mouse_row or old_mouse_col != self.mouse_col;
}

fn handleMouseDown(self: *Imtui, b: SDL.MouseButton, clicks: u8, ct_match: bool) !?Control {
    if (self.focus == .dialog) {
        try self.focus_dialog.handleMouseDown(b, clicks, ct_match);
        return .{ .dialog = self.focus_dialog };
    }

    if (b == .left and (self.getMenubar().?.mouseIsOver() or
        (self.openMenu() != null and self.openMenu().?.mouseIsOverItem())))
    {
        // meu Deus.
        try self.getMenubar().?.handleMouseDown(b, clicks);
        return .{ .menubar = self.getMenubar().? };
    }

    if (b == .left and (self.focus == .menubar or self.focus == .menu)) {
        self.focus = .editor;
        // fall through
    }

    // I don't think it's critical to check for generational liveness in every
    // possible access. If something has indeed aged out, then a false match
    // here writes state that will never be read by user code, and the object
    // will be collected at the start of the next frame.
    var cit = self.controls.valueIterator();
    while (cit.next()) |c|
        switch (c.*) {
            .button => |bu| if (bu.mouseIsOver()) {
                try bu.handleMouseDown(b, clicks);
                return .{ .button = bu };
            },
            .editor => |e| if (e.mouseIsOver()) {
                try e.handleMouseDown(b, clicks, ct_match);
                return .{ .editor = e };
            },
            else => {},
        };

    return null;
}

fn handleMouseDrag(self: *Imtui, b: SDL.MouseButton) !void {
    // N.B.! Right now it's only happenstance that self.mouse_event_target's
    // value is never freed underneath it, since the "user" code so far never
    // doesn't construct a menubar or one of its editors from frame to frame.
    // If we added a target that could, we'd probably get a use-after-free.

    if (self.mouse_event_target) |target|
        try target.handleMouseDrag(b);
}

fn handleMouseUp(self: *Imtui, b: SDL.MouseButton, clicks: u8) !void {
    if (self.mouse_event_target) |target|
        try target.handleMouseUp(b, clicks);
}

fn interpolateMouse(self: *const Imtui, payload: anytype) struct { x: usize, y: usize } {
    return .{
        .x = @intFromFloat(@as(f32, @floatFromInt(@max(0, payload.x))) / self.scale),
        .y = @intFromFloat(@as(f32, @floatFromInt(@max(0, payload.y))) / self.scale),
    };
}

fn acceleratorMatch(label: []const u8, keycode: SDL.Keycode) bool {
    var next_acc = false;
    for (label) |c| {
        if (c == '&')
            next_acc = true
        else if (next_acc)
            return std.ascii.toLower(c) == @intFromEnum(keycode);
    }
    return false;
}

fn keycodeAlphanum(keycode: SDL.Keycode) bool {
    return @intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.a) and
        @intFromEnum(keycode) <= @intFromEnum(SDL.Keycode.z);
}
