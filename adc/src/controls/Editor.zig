const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");
const Source = @import("./Source.zig");
const EditorLike = @import("./EditorLike.zig");

const Editor = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    // id
    id: usize,

    // config
    r1: usize = undefined,
    c1: usize = undefined,
    r2: usize = undefined,
    c2: usize = undefined,
    hidden: bool = undefined,
    immediate: bool = undefined,
    colours: struct {
        normal: u8,
        current: u8,
        breakpoint: u8,
    } = undefined,

    last_source: ?*Source = undefined,
    source: ?*Source = null,

    // user events
    toggled_fullscreen: bool = false,
    dragged_header_to: ?usize = null,

    // state
    el: EditorLike,
    dragging_header: bool = false,

    comptime orphan: void = {},

    pub fn describe(self: *Impl, r1: usize, c1: usize, r2: usize, c2: usize) void {
        self.r1 = r1;
        self.c1 = c1;
        self.r2 = r2;
        self.c2 = c2;
        self.hidden = false;
        self.immediate = false;
        self.colours = .{ .normal = 0x17, .current = 0x1f, .breakpoint = 0x47 };
        self.last_source = self.source;
        self.source = null;

        self.el.describe(r1 + 1, c1 + 1, r2, c2 - 1);
    }

    pub fn deinit(self: *Impl) void {
        if (self.last_source != self.source) {
            if (self.last_source) |ls| ls.release();
        }
        if (self.source) |s| s.release();
        self.imtui.allocator.destroy(self);
    }

    pub fn isMouseOver(self: *const Impl) bool {
        return self.imtui.mouse_row >= self.r1 and self.imtui.mouse_row < self.r2 and self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2;
    }

    pub fn handleKeyPress(self: *Impl, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        if (keycode == .left_alt or keycode == .right_alt) {
            var mb = try self.imtui.getMenubar();
            mb.focus = .pre;
            try self.imtui.focus(mb);
            return;
        }

        const no_cursor = self.r2 - self.r1 <= 1;
        if (no_cursor)
            return;

        if (!try self.el.handleKeyPress(keycode, modifiers)) {
            for ((try self.imtui.getMenubar()).menus.items) |m|
                for (m.menu_items.items) |mi| {
                    if (mi != null) if (mi.?.shortcut) |s| if (s.matches(keycode, modifiers)) {
                        mi.?.chosen = true;
                        return;
                    };
                };

            var cit = self.imtui.controls.valueIterator();
            while (cit.next()) |c|
                switch (c.*) {
                    .shortcut => |s| if (s.shortcut.matches(keycode, modifiers)) {
                        s.*.chosen = true;
                        return;
                    },
                    else => {},
                };
        }
    }

    pub fn handleKeyUp(self: *Impl, keycode: SDL.Keycode) !void {
        try self.el.handleKeyUp(keycode);
    }

    pub fn handleMouseDown(self: *Impl, button: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const r = self.imtui.mouse_row;
        const c = self.imtui.mouse_col;

        const active = self.imtui.focusedEditor() == self;

        if (!cm) {
            self.dragging_header = false;

            if (!(r >= self.r1 and r < self.r2 and c >= self.c1 and c < self.c2))
                return null;
        } else {
            // cm
            if (self.dragging_header)
                return null;

            if (try self.el.handleMouseDown(active, button, clicks, cm))
                return .{ .editor = self };
            return null;
        }

        if (r == self.r1) {
            // Fullscreen triggers on MouseUp, not here.
            self.imtui.focusEditor(self);
            self.dragging_header = true;
            return .{ .editor = self };
        }

        if (try self.el.handleMouseDown(active, button, clicks, cm)) {
            self.imtui.focusEditor(self);
            if (!active and !cm) {
                // Remove any other editors' selections.
                var cit = self.imtui.controls.valueIterator();
                while (cit.next()) |control| {
                    switch (control.*) {
                        .editor => |e| if (e != self) {
                            e.el.selection_start = null;
                        },
                        else => {},
                    }
                }
            }
            return .{ .editor = self };
        }

        return null;
    }

    pub fn handleMouseDrag(self: *Impl, b: SDL.MouseButton) !void {
        if (self.dragging_header and self.r1 != self.imtui.mouse_row) {
            self.dragged_header_to = self.imtui.mouse_row;
            return;
        }

        try self.el.handleMouseDrag(b);
    }

    pub fn handleMouseUp(self: *Impl, button: SDL.MouseButton, clicks: u8) !void {
        _ = button;

        const r = self.imtui.mouse_row;
        const c = self.imtui.mouse_col;

        if (r == self.r1) {
            if ((!self.immediate and c == self.c2 - 4) or clicks == 2)
                self.toggled_fullscreen = true;
            return;
        }
    }
};

impl: *Impl,

pub fn create(imtui: *Imtui, id: usize, r1: usize, c1: usize, r2: usize, c2: usize) !Editor {
    var e = try imtui.allocator.create(Impl);
    e.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .id = id,
        .el = .{ .imtui = imtui },
    };
    e.describe(r1, c1, r2, c2);
    return .{ .impl = e };
}

pub fn colours(self: Editor, normal: u8, current: u8, breakpoint: u8) void {
    self.impl.colours = .{
        .normal = normal,
        .current = current,
        .breakpoint = breakpoint,
    };
}

pub fn scroll_bars(self: Editor, shown: bool) void {
    self.impl.el.scroll_bars = shown;
}

pub fn tab_stops(self: Editor, n: u8) void {
    self.impl.el.tab_stops = n;
}

pub fn source(self: Editor, s: *Source) void {
    // XXX no support for multiple calls in one frame.
    // Want to avoid repeatedly rel/acq if we end up needing to do so, already
    // have one field being written every frame.
    if (self.impl.source != null) unreachable;

    self.impl.source = s;
    if (self.impl.last_source != self.impl.source)
        s.acquire();

    self.impl.el.source = s;
}

pub fn hidden(self: Editor) void {
    self.impl.hidden = true;
}

pub fn immediate(self: Editor) void {
    self.impl.immediate = true;
}

pub fn end(self: Editor) void {
    const impl = self.impl;

    if (impl.last_source != impl.source)
        if (impl.last_source) |ls| {
            ls.release();
            impl.last_source = null;
        };

    if (impl.hidden or impl.r1 == impl.r2)
        return;

    const active = impl.imtui.focusedEditor() == impl;

    // XXX: r1==1 checks here are iffy.

    const colnorm = impl.colours.normal;
    const colnorminv = ((colnorm & 0x0f) << 4) | ((colnorm & 0xf0) >> 4);

    impl.imtui.text_mode.draw(impl.r1, impl.c1, colnorm, if (impl.r1 == 1) .TopLeft else .VerticalRight);
    for (impl.c1 + 1..impl.c2 - 1) |x|
        impl.imtui.text_mode.draw(impl.r1, x, colnorm, .Horizontal);

    const src = impl.el.source.?;
    const start = impl.c1 + (impl.c2 - impl.c1 - 1 - src.title.len) / 2;
    const colour: u8 = if (active) colnorminv else colnorm;
    impl.imtui.text_mode.paint(impl.r1, start - 1, impl.r1 + 1, start + src.title.len + 1, colour, 0);
    impl.imtui.text_mode.write(impl.r1, start, src.title);
    impl.imtui.text_mode.draw(impl.r1, impl.c2 - 1, colnorm, if (impl.r1 == 1) .TopRight else .VerticalLeft);

    if (!impl.immediate) {
        // TODO: fullscreen control separate, rendered on top?
        impl.imtui.text_mode.draw(impl.r1, impl.c2 - 5, colnorm, .VerticalLeft);
        // XXX: heuristic.
        impl.imtui.text_mode.draw(impl.r1, impl.c2 - 4, colnorminv, if (impl.r2 - impl.r1 == 23) .ArrowVertical else .ArrowUp);
        impl.imtui.text_mode.draw(impl.r1, impl.c2 - 3, colnorm, .VerticalRight);
    }

    impl.imtui.text_mode.paint(impl.r1 + 1, impl.c1, impl.r2, impl.c1 + 1, colnorm, .Vertical);
    impl.imtui.text_mode.paint(impl.r1 + 1, impl.c2 - 1, impl.r2, impl.c2, colnorm, .Vertical);
    impl.imtui.text_mode.paint(impl.r1 + 1, impl.c1 + 1, impl.r2, impl.c2 - 1, colnorm, .Blank);

    impl.el.draw(active, colnorminv);
}

pub fn toggledFullscreen(self: Editor) bool {
    defer self.impl.toggled_fullscreen = false;
    return self.impl.toggled_fullscreen;
}

pub fn headerDraggedTo(self: Editor) ?usize {
    defer self.impl.dragged_header_to = null;
    return self.impl.dragged_header_to;
}
