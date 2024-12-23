const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const TextMode = @import("./root.zig").TextMode(25, 80);
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

pub const Control = struct {
    pub const Base = struct {
        imtui: *Imtui,
        generation: usize,
    };

    pub const VTable = struct {
        orphan: bool = false,
        no_key: bool = false,
        no_mouse: bool = false,

        parent: ?*const fn (self: *const anyopaque) ?Control = null,
        deinit: *const fn (self: *anyopaque) void,
        accelGet: ?*const fn (self: *const anyopaque) ?u8 = null,
        accelerate: ?*const fn (self: *anyopaque) Allocator.Error!void = null,
        handleKeyPress: ?*const fn (self: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) Allocator.Error!void = null,
        handleKeyUp: ?*const fn (self: *anyopaque, keycode: SDL.Keycode) Allocator.Error!void = null,
        isMouseOver: ?*const fn (self: *const anyopaque) bool = null,
        handleMouseDown: ?*const fn (self: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) Allocator.Error!?Control = null,
        handleMouseDrag: ?*const fn (self: *anyopaque, b: SDL.MouseButton) Allocator.Error!void = null,
        handleMouseUp: ?*const fn (self: *anyopaque, b: SDL.MouseButton, clicks: u8) Allocator.Error!void = null,
    };

    ptr: *anyopaque,
    vtable: *const VTable,

    fn assertBase(comptime T: type) void {
        const base_fields = std.meta.fields(Base);
        const timpl_fields = std.meta.fields(T.Impl);

        inline for (0..base_fields.len) |i| {
            if (!comptime std.mem.eql(u8, base_fields[i].name, timpl_fields[i].name))
                @compileError(std.fmt.comptimePrint(
                    "field {d} of {s}.Impl name does not match Base's: {s} != {s}",
                    .{ i, @typeName(T), timpl_fields[i].name, base_fields[i].name },
                ));
            if (!comptime std.meta.eql(base_fields[i].type, timpl_fields[i].type))
                @compileError(std.fmt.comptimePrint(
                    "field {d} of {s}.Impl type does not match Base's: {s} != {s}",
                    .{ i, @typeName(T), @typeName(timpl_fields[i].type), @typeName(base_fields[i].type) },
                ));
        }
    }

    pub fn is(self: Control, comptime T: type) ?*T {
        // HACK
        if (self.vtable.deinit != &T.deinit)
            return null;
        return @ptrCast(@alignCast(self.ptr));
    }

    fn as(self: Control, comptime T: type) *T {
        return self.is(T).?;
    }

    fn same(self: Control, other: Control) bool {
        return self.vtable == other.vtable and self.ptr == other.ptr;
    }

    fn lives(self: Control, n: usize) bool {
        if (self.generationGet() < n - 1)
            return false;
        self.generationSet(n);
        return true;
    }

    fn generationGet(self: Control) usize {
        const base: *const Base = @ptrCast(@alignCast(self.ptr));
        return base.generation;
    }

    fn generationSet(self: Control, n: usize) void {
        const base: *Base = @ptrCast(@alignCast(self.ptr));
        base.generation = n;
    }

    // Pure forwarded methods follow.

    pub fn parent(self: Control) ?Control {
        return if (self.vtable.orphan) null else self.vtable.parent.?(self.ptr);
    }

    fn deinit(self: Control) void {
        self.vtable.deinit(self.ptr);
    }

    // TODO: merge below two, only used by Dialog itself
    pub fn accelGet(self: Control) ?u8 {
        return self.vtable.accelGet.?(self.ptr);
    }

    pub fn accelerate(self: Control) !void {
        return self.vtable.accelerate.?(self.ptr);
    }

    fn handleKeyPress(self: Control, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        return if (self.vtable.no_key) {} else self.vtable.handleKeyPress.?(self.ptr, keycode, modifiers);
    }

    fn handleKeyUp(self: Control, keycode: SDL.Keycode) !void {
        return if (self.vtable.no_key) {} else self.vtable.handleKeyUp.?(self.ptr, keycode);
    }

    pub fn isMouseOver(self: Control) bool {
        return if (self.vtable.no_mouse) false else self.vtable.isMouseOver.?(self.ptr);
    }

    pub fn handleMouseDown(self: Control, b: SDL.MouseButton, clicks: u8, cm: bool) !?Control {
        return if (self.vtable.no_mouse) null else self.vtable.handleMouseDown.?(self.ptr, b, clicks, cm);
    }

    fn handleMouseDrag(self: Control, b: SDL.MouseButton) !void {
        return if (self.vtable.no_mouse) {} else self.vtable.handleMouseDrag.?(self.ptr, b);
    }

    fn handleMouseUp(self: Control, b: SDL.MouseButton, clicks: u8) !void {
        return if (self.vtable.no_mouse) {} else self.vtable.handleMouseUp.?(self.ptr, b, clicks);
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

    self.text_mode.clear(0x07);
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
        _ = self.focus_stack.pop();

    try self.focus_stack.append(self.allocator, control);
}

pub fn focused(self: *Imtui, control: Control) bool {
    std.debug.assert(control.is(Controls.Editor.Impl) == null);
    return self.focus_stack.getLast().same(control);
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

pub fn dialog(self: *Imtui, title: []const u8, height: usize, width: usize) !Controls.Dialog {
    return self.getOrPutControl(Controls.Dialog, .{ title, height, width });
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
    const id = try @call(.auto, T.bufPrintImtuiId, .{&buf} ++ args);

    var e = try self.controls.getOrPut(self.allocator, id);

    if (e.found_existing and e.value_ptr.lives(self.generation)) {
        const pc = e.value_ptr.as(T.Impl);
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

    if (try self.focus_stack.getLast().handleMouseDown(b, clicks, cm)) |t|
        return t;

    // This fallback is rather awkward. It takes care of the menu and help-line
    // shortcuts for us, but we have to explicitly avoid it whenever we're not
    // focusing an editor, i.e. like the dialog case above. Perhaps we should
    // just put it in Editor. XXX
    var cit = self.controls.valueIterator();
    while (cit.next()) |c|
        if (c.isMouseOver()) {
            return try c.handleMouseDown(b, clicks, cm);
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
