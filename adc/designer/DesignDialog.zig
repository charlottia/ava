const std = @import("std");
const imtuilib = @import("imtui");
const SDL = imtuilib.SDL;

const Imtui = imtuilib.Imtui;

const DesignDialog = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,

    // state
    r1: usize,
    c1: usize,
    r2: usize,
    c2: usize,
    title: std.ArrayListUnmanaged(u8),
    title_orig: std.ArrayListUnmanaged(u8),

    state: union(enum) {
        idle,
        resize: struct { cix: usize },
        move: struct { origin_row: usize, origin_col: usize },
        title_edit,
    } = .idle,

    title_start: usize = undefined,

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
                .handleMouseDrag = handleMouseDrag,
                .handleMouseUp = handleMouseUp,
            },
        };
    }

    pub fn describe(self: *Impl, _: usize, _: usize, _: usize, _: usize, _: []const u8) void {
        self.imtui.text_mode.box(self.r1, self.c1, self.r2, self.c2, 0x70);

        self.title_start = self.c1 + (self.c2 - self.c1 - self.title.items.len) / 2;
        const title_colour: u8 = if (self.state == .title_edit) 0xa0 else 0x70;
        self.imtui.text_mode.paint(self.r1, self.title_start - 1, self.r1 + 1, self.title_start + self.title.items.len + 1, title_colour, 0);
        self.imtui.text_mode.write(self.r1, self.title_start, self.title.items);

        switch (self.state) {
            .idle => {
                var highlighted = false;
                for (self.corners()) |corner|
                    if (!highlighted and self.imtui.text_mode.mouse_row == corner.r and self.imtui.text_mode.mouse_col == corner.c) {
                        self.imtui.text_mode.paintColour(corner.r -| 1, corner.c -| 1, corner.r + 2, corner.c + 2, 0x20, .outline);
                        highlighted = true;
                        break;
                    };

                if (!highlighted and
                    self.imtui.text_mode.mouse_row == self.r1 and
                    self.imtui.text_mode.mouse_col >= self.title_start - 1 and self.imtui.text_mode.mouse_col < self.title_start + self.title.items.len + 1)
                {
                    self.imtui.text_mode.paintColour(self.r1, self.title_start - 1, self.r1 + 1, self.title_start + self.title.items.len + 1, 0x20, .fill);
                    highlighted = true;
                }

                if (!highlighted and
                    (self.imtui.text_mode.mouse_row == self.r1 or self.imtui.text_mode.mouse_row == self.r2 - 1 or
                    self.imtui.text_mode.mouse_col == self.c1 or self.imtui.text_mode.mouse_col == self.c2 - 1))
                {
                    self.imtui.text_mode.paintColour(self.r1 - 1, self.c1 - 1, self.r2 + 1, self.c2 + 1, 0x20, .outline);
                    highlighted = true;
                }

                self.imtui.text_mode.cursor_inhibit = true;
            },
            .resize => |d| {
                const corner = self.corners()[d.cix];
                self.imtui.text_mode.paintColour(corner.r -| 1, corner.c -| 1, corner.r + 2, corner.c + 2, 0xa0, .outline);
            },
            .move => |_| {},
            .title_edit => {
                self.imtui.text_mode.cursor_row = self.r1;
                self.imtui.text_mode.cursor_col = self.title_start + self.title.items.len;
                self.imtui.text_mode.cursor_inhibit = false;
            },
        }
    }

    fn corners(self: *const Impl) [4]struct { r: usize, c: usize } {
        return .{
            .{ .r = self.r1, .c = self.c1 },
            .{ .r = self.r1, .c = self.c2 - 1 },
            .{ .r = self.r2 - 1, .c = self.c1 },
            .{ .r = self.r2 - 1, .c = self.c2 - 1 },
        };
    }

    pub fn deinit(ptr: *anyopaque) void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        self.title.deinit(self.imtui.allocator);
        self.title_orig.deinit(self.imtui.allocator);
        self.imtui.allocator.destroy(self);
    }

    pub fn handleKeyPress(ptr: *anyopaque, keycode: SDL.Keycode, modifiers: SDL.KeyModifierSet) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));

        switch (self.state) {
            .title_edit => switch (keycode) {
                .backspace => if (self.title.items.len > 0) {
                    if (modifiers.get(.left_control) or modifiers.get(.right_control) or
                        modifiers.get(.left_gui) or modifiers.get(.right_gui))
                        self.title.items.len = 0
                    else
                        self.title.items.len -= 1;
                },
                .@"return" => self.state = .idle,
                .escape => {
                    self.state = .idle;
                    try self.title.replaceRange(self.imtui.allocator, 0, self.title.items.len, self.title_orig.items);
                },
                else => if (Imtui.Controls.isPrintableKey(keycode)) {
                    try self.title.append(self.imtui.allocator, Imtui.Controls.getCharacter(keycode, modifiers));
                },
            },
            else => {},
        }
    }

    fn handleKeyUp(_: *anyopaque, _: SDL.Keycode) !void {}

    fn isMouseOver(ptr: *const anyopaque) bool {
        const self: *const Impl = @ptrCast(@alignCast(ptr));
        return self.state == .title_edit or (self.imtui.mouse_row >= self.r1 and self.imtui.mouse_row < self.r2 and
            self.imtui.mouse_col >= self.c1 and self.imtui.mouse_col < self.c2);
    }

    fn handleMouseDown(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8, cm: bool) !?Imtui.Control {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = clicks;

        if (cm) return null;
        if (!isMouseOver(ptr)) return null;
        if (b != .left) return null;

        switch (self.state) {
            .idle => {
                for (self.corners(), 0..) |corner, cix|
                    if (self.imtui.text_mode.mouse_row == corner.r and self.imtui.text_mode.mouse_col == corner.c) {
                        self.state = .{ .resize = .{ .cix = cix } };
                        return self.control();
                    };

                if (self.imtui.text_mode.mouse_row == self.r1 and
                    self.imtui.text_mode.mouse_col >= self.title_start and self.imtui.text_mode.mouse_col < self.title_start + self.title.items.len + 1)
                {
                    try self.title_orig.replaceRange(self.imtui.allocator, 0, self.title_orig.items.len, self.title.items);
                    self.state = .title_edit;
                    return null;
                }

                if (self.imtui.text_mode.mouse_row == self.r1 or self.imtui.text_mode.mouse_row == self.r2 - 1 or
                    self.imtui.text_mode.mouse_col == self.c1 or self.imtui.text_mode.mouse_col == self.c2 - 1)
                {
                    self.state = .{ .move = .{
                        .origin_row = self.imtui.text_mode.mouse_row,
                        .origin_col = self.imtui.text_mode.mouse_col,
                    } };
                    return self.control();
                }

                return null;
            },
            .title_edit => {
                if (!(self.imtui.text_mode.mouse_row == self.r1 and
                    self.imtui.text_mode.mouse_col >= self.title_start and self.imtui.text_mode.mouse_col < self.title_start + self.title.items.len + 1))
                {
                    self.state = .idle;
                }

                return null;
            },
            else => return null,
        }
    }

    fn handleMouseDrag(ptr: *anyopaque, b: SDL.MouseButton) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;

        switch (self.state) {
            .resize => |d| {
                switch (d.cix) {
                    0, 1 => self.r1 = self.imtui.text_mode.mouse_row,
                    2, 3 => self.r2 = self.imtui.text_mode.mouse_row + 1,
                    else => unreachable,
                }
                switch (d.cix) {
                    0, 2 => self.c1 = self.imtui.text_mode.mouse_col,
                    1, 3 => self.c2 = self.imtui.text_mode.mouse_col + 1,
                    else => unreachable,
                }
            },
            .move => |*d| {
                const dr = @as(isize, @intCast(self.imtui.text_mode.mouse_row)) - @as(isize, @intCast(d.origin_row));
                const dc = @as(isize, @intCast(self.imtui.text_mode.mouse_col)) - @as(isize, @intCast(d.origin_col));
                const r1: isize = @as(isize, @intCast(self.r1)) + dr;
                const c1: isize = @as(isize, @intCast(self.c1)) + dc;
                const r2: isize = @as(isize, @intCast(self.r2)) + dr;
                const c2: isize = @as(isize, @intCast(self.c2)) + dc;
                // Don't allow moving right up to the edge:
                // (a) why would you need to; and,
                // (b) the hover outline crashes on render due to OOB. :)
                if (r1 > 0 and r2 < self.imtui.text_mode.H) {
                    self.r1 = @intCast(r1);
                    self.r2 = @intCast(r2);
                    d.origin_row = @intCast(@as(isize, @intCast(d.origin_row)) + dr);
                }
                if (c1 > 0 and c2 < self.imtui.text_mode.W) {
                    self.c1 = @intCast(c1);
                    self.c2 = @intCast(c2);
                    d.origin_col = @intCast(@as(isize, @intCast(d.origin_col)) + dc);
                }
            },
            else => unreachable,
        }
    }

    fn handleMouseUp(ptr: *anyopaque, b: SDL.MouseButton, clicks: u8) !void {
        const self: *Impl = @ptrCast(@alignCast(ptr));
        _ = b;
        _ = clicks;

        switch (self.state) {
            .resize, .move => self.state = .idle,
            else => unreachable,
        }
    }
};

impl: *Impl,

pub fn bufPrintImtuiId(buf: []u8, _: usize, _: usize, _: usize, _: usize, _: []const u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}", .{"designer.DesignDialog"});
}

pub fn create(imtui: *Imtui, r1: usize, c1: usize, r2: usize, c2: usize, title: []const u8) !DesignDialog {
    var d = try imtui.allocator.create(Impl);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .r1 = r1,
        .c1 = c1,
        .r2 = r2,
        .c2 = c2,
        .title = std.ArrayListUnmanaged(u8).fromOwnedSlice(try imtui.allocator.dupe(u8, title)),
        .title_orig = .{},
    };
    d.describe(r1, c1, r2, c2, title);
    return .{ .impl = d };
}
