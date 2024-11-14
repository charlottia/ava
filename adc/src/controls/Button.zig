const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Button = @This();

imtui: *Imtui,
generation: usize,
r: usize = undefined,
c: usize = undefined,
colour: u8 = undefined,
label: []const u8,

_chosen: bool = false,
inverted: bool = false,

pub fn create(imtui: *Imtui, r: usize, c: usize, colour: u8, label: []const u8) !*Button {
    var b = try imtui.allocator.create(Button);
    b.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .label = label,
    };
    b.describe(r, c, colour);
    return b;
}

pub fn describe(self: *Button, r: usize, c: usize, colour: u8) void {
    self.r = r;
    self.c = c;
    self.colour = if (self.inverted)
        ((colour & 0x0f) << 4) | ((colour & 0xf0) >> 4)
    else
        colour;
    self.imtui.text_mode.paint(r, c, r + 1, c + self.label.len, self.colour, .Blank);
    self.imtui.text_mode.write(r, c, self.label);
}

pub fn deinit(self: *Button) void {
    self.imtui.allocator.destroy(self);
}

pub fn mouseIsOver(self: *const Button) bool {
    return self.imtui.mouse_row == self.r and self.imtui.mouse_col >= self.c and self.imtui.mouse_col < self.c + self.label.len;
}

pub fn chosen(self: *Button) bool {
    defer self._chosen = false;
    return self._chosen;
}

pub fn handleMouseDown(self: *Button, b: SDL.MouseButton, clicks: u8) !void {
    // These don't discriminate on mouse button.
    _ = b;
    _ = clicks;

    self.inverted = true;
}

pub fn handleMouseDrag(self: *Button, b: SDL.MouseButton, old_row: usize, old_col: usize) !void {
    _ = b;
    _ = old_row;
    _ = old_col;

    self.inverted = self.mouseIsOver();
}

pub fn handleMouseUp(self: *Button, b: SDL.MouseButton, clicks: u8) !void {
    _ = b;
    _ = clicks;

    if (self.inverted) {
        self.inverted = false;
        self._chosen = true;
    }
}
