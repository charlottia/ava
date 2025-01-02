const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const TextMode = @import("./root.zig").TextMode(25, 80);
pub const Control = @import("./Control.zig");
pub const Controls = @import("./controls/root.zig");

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
focus_stack: std.ArrayListUnmanaged(Control) = .{}, // Always has an Editor at the bottom; never empty.

controls: std.StringHashMapUnmanaged(Control) = .{},

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
            self.keydown_sym = key.keycode;
            self.keydown_mod = key.modifiers;
            // treat Command as Control for all purposes.
            if (self.keydown_mod.get(.left_gui))
                self.keydown_mod.set(.left_control);
            if (self.keydown_mod.get(.right_gui))
                self.keydown_mod.set(.right_control);
            self.typematic_on = false;
            self.typematic_tick = SDL.getTicks64();
            try self.handleKeyPress(self.keydown_sym, self.keydown_mod);
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
        if (c.value_ptr.generationGet() != self.generation) {
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
            _ = try target.handleMouseDown(self.mouse_down.?, 0, true);
    }

    self.text_mode.clear(0x00);
}

// the following calls are kinda internal-external

pub fn getMenubar(self: *Imtui) !*Controls.Menubar.Impl {
    // XXX
    return (try self.getControl(Controls.Menubar, .{ 0, 0, 0 })).impl;
}

pub fn openMenu(self: *Imtui) ?*Controls.Menu.Impl {
    return switch (self.focus_stack.getLast()) {
        .menubar => |mb| mb.openMenu(),
        else => null,
    };
}

pub fn focus(self: *Imtui, control: Control) !void {
    std.debug.assert(control.is(Controls.Editor.Impl) == null);
    if (self.focused(control)) return;

    const curr = self.focus_stack.getLast();
    // First unfocus when we're focusing something with the same parent.
    const curr_parent = curr.parent();
    const new_parent = control.parent();
    if (curr_parent != null and new_parent != null and
        curr_parent.?.same(new_parent.?))
        try self.focus_stack.pop().onBlur();

    try self.focus_stack.append(self.allocator, control);
    try control.onFocus();
}

pub fn focused(self: *Imtui, control: Control) bool {
    std.debug.assert(control.is(Controls.Editor.Impl) == null);
    return self.focus_stack.getLast().same(control);
}

pub fn focusedAnywhere(self: *Imtui, control: Control) bool {
    // No dialog magic, currently only used by Designer.
    var i: usize = self.focus_stack.items.len - 1;
    while (true) : (i -= 1) {
        if (self.focus_stack.items[i].same(control))
            return true;
        if (i == 0) return false;
    }
}

pub fn unfocus(self: *Imtui, control: Control) void {
    if (control.is(Controls.Dialog.Impl)) |_| {
        // Myth: Cats can only have a little salami as a treat
        // Fact: Cats can have a lot of salami as a treat
        const focus_parent = self.focus_stack.getLast().parent();
        std.debug.assert(focus_parent != null and focus_parent.?.same(control));
        _ = self.focus_stack.pop();
    } else {
        std.debug.assert(self.focused(control));
        _ = self.focus_stack.pop();
    }
}

pub fn unfocusAnywhere(self: *Imtui, control: Control) void {
    // No dialog magic, currently only used by Designer.
    // Asserts the control is focused by simply running off the front.
    var i: usize = self.focus_stack.items.len - 1;
    while (true) : (i -= 1) {
        if (self.focus_stack.items[i].same(control)) {
            _ = self.focus_stack.orderedRemove(i);
            return;
        }
    }
}

pub fn focusedEditor(self: *Imtui) *Controls.Editor.Impl {
    return self.focus_stack.items[0].as(Controls.Editor.Impl);
}

pub fn focusEditor(self: *Imtui, e: *Controls.Editor.Impl) void {
    self.focus_stack.items[0] = e.control();
}

// 100% public

pub fn menubar(self: *Imtui, r: usize, c1: usize, c2: usize) !Controls.Menubar {
    return self.getOrPutControl(Controls.Menubar, .{ r, c1, c2 });
}

pub fn editor(self: *Imtui, editor_id: usize, r1: usize, c1: usize, r2: usize, c2: usize) !Controls.Editor {
    return self.getOrPutControl(Controls.Editor, .{ editor_id, r1, c1, r2, c2 });
}

pub fn button(self: *Imtui, r: usize, c: usize, colour: u8, label: []const u8) !Controls.Button {
    return self.getOrPutControl(Controls.Button, .{ r, c, colour, label });
}

pub fn shortcut(self: *Imtui, keycode: SDL.Keycode, modifier: ?ShortcutModifier) !Controls.Shortcut {
    return self.getOrPutControl(Controls.Shortcut, .{ keycode, modifier });
}

pub fn dialog(self: *Imtui, title: []const u8, height: usize, width: usize, position: Controls.Dialog.Position) !Controls.Dialog {
    return self.getOrPutControl(Controls.Dialog, .{ title, height, width, position });
}

pub fn dialogradio(self: *Imtui, parent: *Controls.Dialog.Impl, group_id: usize, item_id: usize, r: usize, c: usize, label: []const u8) !Imtui.Controls.DialogRadio {
    defer parent.controls_at += 1;
    return self.getOrPutControl(Controls.DialogRadio, .{ parent, parent.controls_at, group_id, item_id, r, c, label });
}

pub fn dialogselect(self: *Imtui, parent: *Controls.Dialog.Impl, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, selected: usize) !Imtui.Controls.DialogSelect {
    defer parent.controls_at += 1;
    return self.getOrPutControl(Controls.DialogSelect, .{ parent, parent.controls_at, r1, c1, r2, c2, colour, selected });
}

pub fn dialogcheckbox(self: *Imtui, parent: *Controls.Dialog.Impl, r: usize, c: usize, label: []const u8, selected: bool) !Imtui.Controls.DialogCheckbox {
    defer parent.controls_at += 1;
    return self.getOrPutControl(Controls.DialogCheckbox, .{ parent, parent.controls_at, r, c, label, selected });
}

pub fn dialoginput(self: *Imtui, parent: *Controls.Dialog.Impl, r: usize, c1: usize, c2: usize) !Imtui.Controls.DialogInput {
    defer parent.controls_at += 1;
    return self.getOrPutControl(Controls.DialogInput, .{ parent, parent.controls_at, r, c1, c2 });
}

pub fn dialogbutton(self: *Imtui, parent: *Controls.Dialog.Impl, r: usize, c: usize, label: []const u8) !Imtui.Controls.DialogButton {
    defer parent.controls_at += 1;
    return self.getOrPutControl(Imtui.Controls.DialogButton, .{ parent, parent.controls_at, r, c, label });
}

pub fn getOrPutControl(self: *Imtui, comptime T: type, args: anytype) !T {
    Control.assertBase(T);

    // Not guaranteed to be large enough ... https://media1.tenor.com/m/ZaxUeXcUtDkAAAAd/shrug-smug.gif
    var buf: [100]u8 = undefined;
    const id = if (@hasDecl(T, "bufPrintImtuiId"))
        try @call(.auto, T.bufPrintImtuiId, .{&buf} ++ args)
    else
        // HACK: This is bad and you should feel bad.
        try @call(.auto, T.Impl.bufPrintImtuiId, .{ &buf, args[2] }); // .{root, dialog, id, ...}

    var e = try self.controls.getOrPut(self.allocator, id);

    if (e.found_existing and e.value_ptr.lives(self.generation)) {
        const pc = e.value_ptr.as(T.Impl);
        // Designer's controls don't update state on describe() and so take no arguments.
        if (@typeInfo(@TypeOf(T.Impl.describe)).Fn.params.len == 1)
            @call(.auto, T.Impl.describe, .{pc})
        else
            @call(.auto, T.Impl.describe, .{pc} ++ args);
        return .{ .impl = e.value_ptr.as(T.Impl) };
    }

    if (e.found_existing)
        e.value_ptr.deinit()
    else
        e.key_ptr.* = try self.allocator.dupe(u8, id);

    const pc = try @call(.auto, T.create, .{self} ++ args);
    e.value_ptr.* = pc.impl.control();
    return pc;
}

fn getControl(self: *Imtui, comptime T: type, args: anytype) !T {
    var buf: [100]u8 = undefined;
    const id = try @call(.auto, T.bufPrintImtuiId, .{&buf} ++ args);
    return .{ .impl = self.controls.get(id).?.as(T.Impl) };
}

fn handleKeyPress(self: *Imtui, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    if ((keycode == .left_alt or keycode == .right_alt) and !self.alt_held)
        self.alt_held = true;

    try self.focus_stack.getLast().handleKeyPress(keycode, modifiers);
}

pub fn fallbackKeyPress(self: *Imtui, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    if (keycode == .left_alt or keycode == .right_alt) {
        var mb = try self.getMenubar();
        mb.focus = .pre;
        try self.focus(mb.control());
        return;
    }

    for ((try self.getMenubar()).menus.items) |m|
        for (m.menu_items.items) |mi| {
            if (mi != null) if (mi.?.shortcut) |s| if (s.matches(keycode, modifiers)) {
                mi.?.chosen = true;
                return;
            };
        };

    var cit = self.controls.valueIterator();
    while (cit.next()) |c|
        if (c.is(Controls.Shortcut.Impl)) |s|
            if (s.shortcut.matches(keycode, modifiers)) {
                s.*.chosen = true;
                return;
            };
}

fn handleKeyUp(self: *Imtui, keycode: SDL.Keycode) !void {
    try self.focus_stack.getLast().handleKeyUp(keycode);

    if ((keycode == .left_alt or keycode == .right_alt) and self.alt_held)
        self.alt_held = false;
}

fn handleMouseAt(self: *Imtui, row: usize, col: usize) bool {
    const old_mouse_row = self.mouse_row;
    const old_mouse_col = self.mouse_col;

    self.mouse_row = row;
    self.mouse_col = col;

    return old_mouse_row != self.mouse_row or old_mouse_col != self.mouse_col;
}

fn handleMouseDown(self: *Imtui, b: SDL.MouseButton, clicks: u8, cm: bool) !?Control {
    // The return value becomes self.mouse_event_target.
    // This means a focused dialog control can take the event, decide it doesn't
    // match it, and dispatch to the dialog to see if another one does instead.
    // (If one doesn't, the dialog takes it for itself, and swallows them fro
    // now.)

    return self.focus_stack.getLast().handleMouseDown(b, clicks, cm);
}

pub fn fallbackMouseDown(self: *Imtui, b: SDL.MouseButton, clicks: u8, cm: bool) !?struct { ?Control } {
    // To be used by control code when the click should go to whatever passes
    // isMouseOver().

    var cit = self.controls.valueIterator();
    while (cit.next()) |c|
        if (c.isMouseOver()) {
            return .{try c.handleMouseDown(b, clicks, cm)};
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

// TODO: use this more, and also figure out a nice way to do it for items reset
// in describe().
pub fn describeValue(self: *const Imtui, current: []const u8, new: []const u8) ![]const u8 {
    if (std.mem.eql(u8, current, new))
        return current;

    self.allocator.free(current);
    return self.allocator.dupe(u8, new);
}
