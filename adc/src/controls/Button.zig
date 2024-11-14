const Imtui = @import("../Imtui.zig");

const Button = @This();

imtui: *Imtui,
generation: usize,
r: usize = undefined,
c: usize = undefined,
colour: u8 = undefined,
label: []const u8,

_chosen: bool = false,

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
    self.colour = colour;
    self.imtui.text_mode.paint(r, c, r + 1, c + self.label.len, colour, .Blank);
    self.imtui.text_mode.write(r, c, self.label);
}

pub fn deinit(self: *Button) void {
    self.imtui.allocator.destroy(self);
}

pub fn mouseIsOver(self: *const Button, imtui: *const Imtui) bool {
    return imtui.mouse_row == self.r and imtui.mouse_col >= self.c and imtui.mouse_col < self.c + self.label.len;
}

pub fn chosen(self: *Button) bool {
    defer self._chosen = false;
    return self._chosen;
}
