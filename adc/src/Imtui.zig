const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

pub const TextMode = @import("./TextMode.zig").TextMode(25, 80);
pub const Controls = @import("./ImtuiControls.zig");

const Font = @import("./Font.zig");

const Imtui = @This();

allocator: Allocator,
text_mode: TextMode,
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
clickmatic_on: bool = false,
clickmatic_tick: ?u64 = null, // Only set when a mouse_event_target is moused down on.

alt_held: bool = false,
focus_stack: std.ArrayListUnmanaged(Control) = .{},
focus_editor: usize = 0,

controls: std.StringHashMapUnmanaged(Control) = .{},

const Control = union(enum) {
    button: *Controls.Button.Impl,
    shortcut: *Controls.Shortcut.Impl,
    menubar: *Controls.Menubar.Impl,
    editor: *Controls.Editor.Impl,
    dialog: *Controls.Dialog.Impl,
    // dialog_radio: *Controls.DialogRadio.Impl,
    // dialog_select: *Controls.DialogSelect.Impl,
    // dialog_checkbox: *Controls.DialogCheckbox.Impl,
    // dialog_input: *Controls.DialogInput.Impl,
    dialog_button: *Controls.DialogButton.Impl,

    // Consider a real vtable for these (Zig has examples).

    fn same(self: Control, other: Control) bool {
        return switch (self) {
            inline else => |lhs| switch (other) {
                inline else => |rhs| {
                    if (@TypeOf(lhs) != @TypeOf(rhs)) return false;
                    return lhs == rhs;
                },
            },
        };
    }

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

    fn isMouseOver(self: Control) bool {
        switch (self) {
            inline else => |c| if (@hasDecl(@TypeOf(c.*), "isMouseOver")) {
                return c.isMouseOver();
            },
        }
        return false;
    }

    fn handleKeyPress(self: Control, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        switch (self) {
            inline else => |c| if (@hasDecl(@TypeOf(c.*), "handleKeyPress")) {
                try c.handleKeyPress(keycode, modifiers);
            },
        }
    }

    fn handleKeyUp(self: Control, keycode: SDL.Keycode) !void {
        switch (self) {
            inline else => |c| if (@hasDecl(@TypeOf(c.*), "handleKeyUp")) {
                try c.handleKeyUp(keycode);
            },
        }
    }

    fn handleMouseDown(self: Control, b: SDL.MouseButton, clicks: u8, cm: bool) !bool {
        switch (self) {
            inline else => |c| if (@hasDecl(@TypeOf(c.*), "handleMouseDown")) {
                return c.handleMouseDown(b, clicks, cm);
            },
        }
        return false;
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
        .text_mode = try TextMode.init(renderer, font),
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

    self.focus_stack.deinit(self.allocator);
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
    try self.text_mode.present(self.delta_tick);
}

pub fn newFrame(self: *Imtui) !void {
    self.text_mode.cursor_inhibit = false;

    var cit = self.controls.iterator();
    while (cit.next()) |c| {
        if (c.value_ptr.generation() != self.generation) {
            std.log.debug("newFrame: {s} has aged out", .{@tagName(c.value_ptr.*)});
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
        if (trigger) {
            const handled = try target.handleMouseDown(self.mouse_down.?, 0, true);
            std.debug.assert(handled); // ...
        }
    }

    self.text_mode.clear(0x07);
}

// the following calls are kinda internal-external

pub fn getMenubar(self: *Imtui) !*Controls.Menubar.Impl {
    return (try self.getOrPutControl(.menubar, "", .{})).present;
}

pub fn openMenu(self: *Imtui) !?*Controls.Menu.Impl {
    if (self.focus_stack.getLastOrNull()) |f| switch (f) {
        .menubar => |mb| return mb.openMenu(),
        else => {},
    };
    return null;
}

pub fn focus(self: *Imtui, control: Control) !void {
    // TODO: will this ever be called with an Editor?
    if (!self.focused(control))
        try self.focus_stack.append(self.allocator, control);
}

pub fn focused(self: *Imtui, control: Control) bool {
    // TODO: will this ever be called with an Editor?
    return (self.focus_stack.getLastOrNull() orelse return false).same(control);
}

pub fn unfocus(self: *Imtui, control: Control) void {
    std.debug.assert(self.focused(control));
    _ = self.focus_stack.pop();
}

pub fn focusedEditor(self: *Imtui) !*Controls.Editor.Impl {
    // TODO: but it may not be _focused_.
    // XXX: this is ridiculous and i cant take it seriously
    return (try self.getOrPutControl(.editor, "{d}", .{self.focus_editor})).present;
}

// 100% public

pub fn menubar(self: *Imtui, r: usize, c1: usize, c2: usize) !Controls.Menubar {
    switch (try self.getOrPutControl(.menubar, "", .{})) {
        .present => |mb| {
            mb.describe(r, c1, c2);
            return .{ .impl = mb };
        },
        .absent => |mbp| {
            const mb = try Controls.Menubar.create(self, r, c1, c2);
            mbp.* = mb.impl;
            return mb;
        },
    }
}

pub fn editor(self: *Imtui, editor_id: usize, r1: usize, c1: usize, r2: usize, c2: usize) !Controls.Editor {
    switch (try self.getOrPutControl(.editor, "{d}", .{editor_id})) {
        .present => |e| {
            e.describe(r1, c1, r2, c2);
            return .{ .impl = e };
        },
        .absent => |ep| {
            const e = try Controls.Editor.create(self, editor_id, r1, c1, r2, c2);
            ep.* = e.impl;
            return e;
        },
    }
}

pub fn button(self: *Imtui, r: usize, c: usize, colour: u8, label: []const u8) !Controls.Button {
    switch (try self.getOrPutControl(.button, "{s}", .{label})) {
        .present => |b| {
            b.describe(r, c, colour);
            return .{ .impl = b };
        },
        .absent => |bp| {
            const b = try Controls.Button.create(self, r, c, colour, label);
            bp.* = b.impl;
            return b;
        },
    }
}

pub fn shortcut(self: *Imtui, keycode: SDL.Keycode, modifier: ?ShortcutModifier) !Controls.Shortcut {
    switch (try self.getOrPutControl(.shortcut, "{s}.{s}", .{ @tagName(keycode), if (modifier) |m| @tagName(m) else "none" })) {
        .present => |s| return .{ .impl = s },
        .absent => |sp| {
            const s = try Controls.Shortcut.create(self, keycode, modifier);
            sp.* = s.impl;
            return s;
        },
    }
}

pub fn dialog(self: *Imtui, title: []const u8, height: usize, width: usize) !Controls.Dialog {
    // self.focus = .dialog;

    switch (try self.getOrPutControl(.dialog, "{s}", .{title})) {
        .present => |d| {
            // self.focus_dialog = d;
            d.describe(height, width);
            return .{ .impl = d };
        },
        .absent => |dp| {
            const d = try Controls.Dialog.create(self, title, height, width);
            // self.focus_dialog = d.impl;
            dp.* = d.impl;
            return d;
        },
    }
}

pub fn dialogbutton(self: *Imtui, parent: *Controls.Dialog.Impl, r: usize, c: usize, label: []const u8) !Imtui.Controls.DialogButton {
    // We don't actually have a proper ID descendent thing going on here. Get to it XXX
    defer parent.controls_at += 1;
    switch (try self.getOrPutControl(.dialog_button, "{s}.{s}", .{ parent.title, label })) {
        .present => |b| {
            b.describe(parent.controls_at, r, c, label);
            return .{ .impl = b };
        },
        .absent => |bp| {
            const b = try Imtui.Controls.DialogButton.create(parent, parent.controls_at, r, c, label);
            bp.* = b.impl;
            try parent.controls.append(self.allocator, .{ .button = b.impl });
            return b;
        },
    }
}

fn getOrPutControl(self: *Imtui, comptime tag: std.meta.Tag(Control), comptime fmt: []const u8, parts: anytype) !union(enum) {
    present: std.meta.TagPayload(Control, tag),
    absent: *std.meta.TagPayload(Control, tag),
} {
    // Not guaranteed to be large enough ... https://media1.tenor.com/m/ZaxUeXcUtDkAAAAd/shrug-smug.gif
    var buf: [100]u8 = undefined;
    const id = try std.fmt.bufPrint(&buf, "{s}." ++ fmt, .{@tagName(tag)} ++ parts);

    var e = try self.controls.getOrPut(self.allocator, id);

    if (e.found_existing and e.value_ptr.generation() >= self.generation - 1) {
        e.value_ptr.setGeneration(self.generation);
        return switch (e.value_ptr.*) {
            tag => |p| .{ .present = p },
            else => unreachable,
        };
    }

    if (e.found_existing)
        e.value_ptr.deinit()
    else
        e.key_ptr.* = try self.allocator.dupe(u8, id);

    e.value_ptr.* = @unionInit(Control, @tagName(tag), undefined);
    std.log.debug("creating {s}, id \"{s}\", &e.value_ptr.*.tag {*}", .{ @tagName(tag), id, &@field(e.value_ptr.*, @tagName(tag)) });
    return .{ .absent = &@field(e.value_ptr.*, @tagName(tag)) };
}

fn handleKeyPress(self: *Imtui, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    // if (self.focus == .dialog)
    //     return try self.focus_dialog.handleKeyPress(keycode, modifiers);

    if ((keycode == .left_alt or keycode == .right_alt) and !self.alt_held)
        self.alt_held = true;

    if (self.focus_stack.getLastOrNull()) |c| {
        try c.handleKeyPress(keycode, modifiers);
    } else {
        const e = try self.focusedEditor();
        try e.handleKeyPress(keycode, modifiers);
    }
}

fn handleKeyUp(self: *Imtui, keycode: SDL.Keycode) !void {
    // if (self.focus == .dialog)
    //     return try self.focus_dialog.handleKeyUp(keycode);

    if ((keycode == .left_alt or keycode == .right_alt) and self.alt_held)
        self.alt_held = false;

    if (self.focus_stack.getLastOrNull()) |c| {
        try c.handleKeyUp(keycode);
    } else {
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

fn handleMouseDown(self: *Imtui, b: SDL.MouseButton, clicks: u8, cm: bool) !?Control {
    if (self.focus_stack.getLastOrNull()) |c| {
        if (try c.handleMouseDown(b, clicks, cm))
            return c;
    } else {
        const e = try self.focusedEditor();
        if (try e.handleMouseDown(b, clicks, cm))
            return .{ .editor = e };
    }

    var cit = self.controls.valueIterator();
    while (cit.next()) |c|
        if (c.isMouseOver()) {
            const handled = try c.handleMouseDown(b, clicks, cm);
            std.debug.assert(handled); // ...
            return c.*;
        };

    // if (self.focus == .dialog) {
    //     try self.focus_dialog.handleMouseDown(b, clicks, cm);
    //     return .{ .dialog = self.focus_dialog };
    // }

    // if (b == .left and ((try self.getMenubar()).isMouseOver() or
    //     ((try self.openMenu()) != null and (try self.openMenu()).?.isMouseOverItem())))
    // {
    //     // meu Deus.
    //     try (try self.getMenubar()).handleMouseDown(b, clicks);
    //     return .{ .menubar = (try self.getMenubar()) };
    // }

    // if (b == .left and (self.focus == .menubar or self.focus == .menu)) {
    //     self.focus = .editor;
    //     // fall through
    // }

    // // I don't think it's critical to check for generational liveness in every
    // // possible access. If something has indeed aged out, then a false match
    // // here writes state that will never be read by user code, and the object
    // // will be collected at the start of the next frame.

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

pub fn acceleratorMatch(label: []const u8, keycode: SDL.Keycode) bool {
    var next_acc = false;
    for (label) |c| {
        if (c == '&')
            next_acc = true
        else if (next_acc)
            return std.ascii.toLower(c) == @intFromEnum(keycode);
    }
    return false;
}

pub fn keycodeAlphanum(keycode: SDL.Keycode) bool {
    return @intFromEnum(keycode) >= @intFromEnum(SDL.Keycode.a) and
        @intFromEnum(keycode) <= @intFromEnum(SDL.Keycode.z);
}
