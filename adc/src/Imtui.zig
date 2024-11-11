const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const TextMode = @import("./TextMode.zig").TextMode;
const Font = @import("./Font.zig");
const ImtuiControls = @import("./ImtuiControls.zig");

const Imtui = @This();

allocator: Allocator,
text_mode: TextMode(25, 80),
scale: f32,

running: bool = true,
generation: usize = 0,

last_tick: u64,
delta_tick: u64 = 0,

keydown_tick: ?u64 = null,
keydown_sym: SDL.Keycode = .unknown,
keydown_mod: SDL.KeyModifierSet = undefined,
typematic_on: bool = false,

mouse_row: usize = 0,
mouse_col: usize = 0,
mouse_down: ?SDL.MouseButton = null,

mouse_menu_op: bool = false,
mouse_menu_op_closable: bool = false, // XXX

alt_held: bool = false,
focus: union(enum) {
    unknown,
    menubar: struct { index: usize, open: bool },
    menu: ImtuiControls.MenuItemReference,
} = .unknown,

controls: std.StringHashMapUnmanaged(Control) = .{},

const Control = union(enum) {
    button: *ImtuiControls.Button,
    menubar: *ImtuiControls.Menubar,
    menu: *ImtuiControls.Menu,
    menu_item: *ImtuiControls.MenuItem,
    editor: *ImtuiControls.Editor,

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
};

// https://ejmastnak.com/tutorials/arch/typematic-rate/
const TYPEMATIC_DELAY_MS = 500;
const TYPEMATIC_REPEAT_MS = 1000 / 25;

pub fn init(allocator: Allocator, renderer: SDL.Renderer, font: *Font, scale: f32) !*Imtui {
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

    self.allocator.destroy(self);
}

pub fn processEvent(self: *Imtui, event: SDL.Event) void {
    switch (event) {
        .key_down => |key| {
            if (key.is_repeat) return;
            try self.handleKeyPress(key.keycode, key.modifiers);
            self.keydown_tick = SDL.getTicks64();
            self.keydown_sym = key.keycode;
            self.keydown_mod = key.modifiers;
            self.typematic_on = false;
        },
        .key_up => |key| {
            // We don't try to match key down to up.
            try self.handleKeyUp(key.keycode);
            self.keydown_tick = null;
        },
        .mouse_motion => |ev| {
            const pos = self.interpolateMouse(ev);
            self.text_mode.positionMouseAt(pos.x, pos.y);
            if (self.handleMouseAt(self.text_mode.mouse_row, self.text_mode.mouse_col)) |old_loc| {
                if (self.mouse_down) |b|
                    try self.handleMouseDrag(b, old_loc.r, old_loc.c);
            }
        },
        .mouse_button_down => |ev| {
            const pos = self.interpolateMouse(ev);
            self.text_mode.positionMouseAt(pos.x, pos.y);
            _ = self.handleMouseAt(self.text_mode.mouse_row, self.text_mode.mouse_col);
            try self.handleMouseDown(ev.button, ev.clicks);
            self.mouse_down = ev.button;
        },
        .mouse_button_up => |ev| {
            const pos = self.interpolateMouse(ev);
            self.text_mode.positionMouseAt(pos.x, pos.y);
            _ = self.handleMouseAt(self.text_mode.mouse_row, self.text_mode.mouse_col);
            try self.handleMouseUp(ev.button, ev.clicks);
            self.mouse_down = null;
        },
        .quit => self.running = false,
        else => {},
    }
}

pub fn render(self: *Imtui) !void {
    self.text_mode.cursor_inhibit = self.focus == .menu or self.focus == .menubar;
    try self.text_mode.present(self.delta_tick);
}

pub fn newFrame(self: *Imtui) !void {
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

    if (self.keydown_tick) |keydown_tick| {
        if (!self.typematic_on and this_tick >= keydown_tick + TYPEMATIC_DELAY_MS) {
            self.typematic_on = true;
            self.keydown_tick = keydown_tick + TYPEMATIC_DELAY_MS;
            try self.handleKeyPress(self.keydown_sym, self.keydown_mod);
        } else if (self.typematic_on and this_tick >= keydown_tick + TYPEMATIC_REPEAT_MS) {
            self.keydown_tick = keydown_tick + TYPEMATIC_REPEAT_MS;
            try self.handleKeyPress(self.keydown_sym, self.keydown_mod);
        }
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

    std.debug.print("controlById invalidating\n", .{});
    self.allocator.free(e.key_ptr.*);
    e.value_ptr.deinit();
    self.controls.removeByPtr(e.key_ptr);
    return null;
}

pub fn menubar(self: *Imtui, r: usize, c1: usize, c2: usize) !*ImtuiControls.Menubar {
    if (self.controlById(.menubar, "menubar")) |mb| {
        mb.describe(r, c1, c2);
        return mb;
    }

    const mb = try ImtuiControls.Menubar.create(self, r, c1, c2);
    try self.controls.putNoClobber(self.allocator, try self.allocator.dupe(u8, "menubar"), .{ .menubar = mb });
    return mb;
}

pub fn editor(self: *Imtui, r1: usize, c1: usize, r2: usize, c2: usize, editor_id: usize) !*ImtuiControls.Editor {
    var buf: [10]u8 = undefined; // editor.XYZ
    const key = try std.fmt.bufPrint(&buf, "editor.{d}", .{editor_id});
    if (self.controlById(.editor, key)) |e| {
        e.describe(r1, c1, r2, c2);
        return e;
    }

    const e = try ImtuiControls.Editor.create(self, r1, c1, r2, c2);
    try self.controls.putNoClobber(self.allocator, try self.allocator.dupe(u8, key), .{ .editor = e });
    return e;
}

pub fn button(self: *Imtui, r: usize, c: usize, colour: u8, label: []const u8) !*ImtuiControls.Button {
    var buf: [60]u8 = undefined; // button.blahblahblahblahblah
    const key = try std.fmt.bufPrint(&buf, "button.{s}", .{label});
    if (self.controlById(.button, key)) |b| {
        b.describe(r, c, colour);
        return b;
    }

    const b = try ImtuiControls.Button.create(self, r, c, colour, label);
    try self.controls.putNoClobber(self.allocator, try self.allocator.dupe(u8, key), .{ .button = b });
    return b;
}

pub fn getMenubar(self: *Imtui) ?*ImtuiControls.Menubar {
    return self.controlById(.menubar, "menubar");
}

pub fn openMenu(self: *Imtui) ?*ImtuiControls.Menu {
    switch (self.focus) {
        .menubar => |mb| if (mb.open) return self.getMenubar().?.menus.items[mb.index],
        .menu => |m| return self.getMenubar().?.menus.items[m.index],
        else => {},
    }
    return null;
}

fn handleKeyPress(self: *Imtui, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
    _ = modifiers;

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
            },
            .right => mb.index = (mb.index + 1) % self.getMenubar().?.menus.items.len,
            .up, .down => self.focus = .{ .menu = .{ .index = mb.index, .item = 0 } },
            .escape => {
                self.focus = .unknown; // XXX
            },
            .@"return" => self.focus = .{ .menu = .{ .index = mb.index, .item = 0 } },
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
            },
            .right => {
                m.item = 0;
                m.index = (m.index + 1) % self.getMenubar().?.menus.items.len;
            },
            .up => while (true) {
                if (m.item == 0)
                    m.item = self.getMenubar().?.menus.items[m.index].menu_items.items.len - 1
                else
                    m.item -= 1;
                if (self.getMenubar().?.menus.items[m.index].menu_items.items[m.item] == null)
                    continue;
                break;
            },
            .down => while (true) {
                m.item = (m.item + 1) % self.getMenubar().?.menus.items[m.index].menu_items.items.len;
                if (self.getMenubar().?.menus.items[m.index].menu_items.items[m.item] == null)
                    continue;
                break;
            },
            .escape => {
                self.focus = .unknown; // XXX
            },
            .@"return" => self.getMenubar().?.menus.items[m.index].menu_items.items[m.item].?._chosen = true,
            else => if (keycodeAlphanum(keycode)) {
                for (self.getMenubar().?.menus.items[m.index].menu_items.items) |*mi|
                    if (mi.* != null and acceleratorMatch(mi.*.?.label, keycode)) {
                        mi.*.?._chosen = true;
                    };
            },
        },
        else => {},
    }
}

fn handleKeyUp(self: *Imtui, keycode: SDL.Keycode) !void {
    if ((keycode == .left_alt or keycode == .right_alt) and self.alt_held) {
        self.alt_held = false;

        if (self.focus == .menu) {
            self.focus = .{ .menubar = .{ .index = self.focus.menu.index, .open = false } };
        } else if (self.focus != .menubar) {
            self.focus = .{ .menubar = .{ .index = 0, .open = false } };
        } else {
            self.focus = .unknown; // XXX
        }
    }
}

fn handleMouseAt(self: *Imtui, row: usize, col: usize) ?struct { r: usize, c: usize } {
    const old_mouse_row = self.mouse_row;
    const old_mouse_col = self.mouse_col;

    self.mouse_row = row;
    self.mouse_col = col;

    if (old_mouse_row != self.mouse_row or old_mouse_col != self.mouse_col)
        return .{ .r = old_mouse_row, .c = old_mouse_col };

    return null;
}

fn handleMouseDown(self: *Imtui, b: SDL.MouseButton, clicks: u8) !void {
    _ = clicks;

    // "mouse_menu_op" is a bit of hack. We might be able to generalise it by
    // saying that whatever control a mouse operation starts in then receives
    // further events until it ends (i.e. from down to up).
    //
    // ^- This is obviously the way it should be?? This suggests a slightly more
    //    generic object model (the one we're currently pretending to have);
    //    controls directly receiving the mouse events. Is the Menubar a whole
    //    receiver, or do individual items receive events? If the latter, how do
    //    we deal with e.g. mouse drag from menubar (on no particular item) over
    //    an item toggling that menu, in the same way it happens when starting
    //    from an item? tbblobnoern
    self.mouse_menu_op = false;

    if (b == .left and (self.getMenubar().?.mouseIsOver(self) or
        (self.openMenu() != null and self.openMenu().?.mouseIsOverItem(self))))
    {
        self.mouse_menu_op = true;
        return self.handleMenuMouseDown();
    }

    if (b == .left and (self.focus == .menubar or self.focus == .menu)) {
        self.focus = .unknown; // XXX
        return;
    }

    if (b == .left) {
        // I don't think it's not critical to check for generational liveness in
        // every possible access. If it has indeed aged out, then a false match
        // here writes state that will never be read by the client, and the
        // object will be collected at the start of the next frame.
        var cit = self.controls.valueIterator();
        while (cit.next()) |c|
            switch (c.*) {
                .button => |bu| {
                    if (bu.*.mouseIsOver(self)) {
                        std.debug.print("button event target found mark\n", .{});
                        bu.*._chosen = true;
                        return;
                    }
                },
                else => {},
            };
        // if (c.
        // if (bu.*.generation == self.generation) {
        //     if (bu.*.mouseIsOver(self)) {
        //         bu.*._chosen = true;
        //         return;
        //     }
        // } else std.debug.print("button failed gen check\n", .{});
    }
}

fn handleMouseDrag(self: *Imtui, b: SDL.MouseButton, old_row: usize, old_col: usize) !void {
    _ = b;

    if (self.mouse_menu_op)
        return self.handleMenuMouseDrag(old_row, old_col);
}

fn handleMouseUp(self: *Imtui, b: SDL.MouseButton, clicks: u8) !void {
    _ = b;
    _ = clicks;

    if (self.mouse_menu_op)
        return self.handleMenuMouseUp();
}

fn handleMenuMouseDown(self: *Imtui) void {
    self.mouse_menu_op_closable = false;

    for (self.getMenubar().?.menus.items, 0..) |*m, mix|
        if (m.*.mouseIsOver(self)) {
            if (self.openMenu()) |om|
                self.mouse_menu_op_closable = om.index == mix;
            self.focus = .{ .menubar = .{ .index = mix, .open = true } };
            return;
        };

    if (self.openMenu()) |m|
        if (m.mouseOverItem(self)) |i| {
            self.focus = .{ .menu = .{ .index = m.index, .item = i.index } };
            return;
        };
}

fn handleMenuMouseDrag(self: *Imtui, old_row: usize, old_col: usize) !void {
    _ = old_row;
    _ = old_col;

    if (self.mouse_row == self.getMenubar().?.r) {
        for (self.getMenubar().?.menus.items, 0..) |*m, mix|
            if (m.*.mouseIsOver(self)) {
                if (self.openMenu()) |om|
                    self.mouse_menu_op_closable = self.mouse_menu_op_closable and
                        om.index == mix;
                self.focus = .{ .menubar = .{ .index = mix, .open = true } };
                return;
            };
        self.focus = .unknown; // XXX
        return;
    }

    if (self.openMenu()) |m| {
        if (m.mouseOverItem(self)) |i| {
            self.mouse_menu_op_closable = false;
            self.focus = .{ .menu = .{ .index = m.index, .item = i.index } };
        } else self.focus = .{ .menubar = .{ .index = m.index, .open = true } };
        return;
    }
}

fn handleMenuMouseUp(self: *Imtui) void {
    self.mouse_menu_op = false;

    if (self.openMenu()) |m| {
        if (m.mouseOverItem(self)) |i| {
            i._chosen = true;
            self.focus = .unknown; // XXX
            return;
        }

        if (m.mouseIsOver(self) and !self.mouse_menu_op_closable) {
            self.focus = .{ .menu = .{ .index = m.index, .item = 0 } };
            return;
        }

        self.focus = .unknown; // XXX
    }
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
