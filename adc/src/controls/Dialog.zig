const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Dialog = @This();

imtui: *Imtui,
generation: usize,
title: []const u8,
r1: usize,
c1: usize,

pub fn create(imtui: *Imtui, title: []const u8, height: usize, width: usize) !*Dialog {
    var d = try imtui.allocator.create(Dialog);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .title = title,
        .r1 = undefined,
        .c1 = undefined,
    };
    d.describe(height, width);
    return d;
}

pub fn describe(self: *Dialog, height: usize, width: usize) void {
    self.r1 = (@TypeOf(self.imtui.text_mode).H - height) / 2;
    self.c1 = (@TypeOf(self.imtui.text_mode).W - width) / 2;
    const r2 = self.r1 + height;
    const c2 = self.c1 + width;

    self._groupbox(self.title, self.r1, self.c1, r2, c2, 0x70);
    for (self.r1 + 1..r2 + 1) |r| {
        self.imtui.text_mode.shadow(r, c2);
        self.imtui.text_mode.shadow(r, c2 + 1);
    }
    for (self.c1 + 2..c2) |c|
        self.imtui.text_mode.shadow(r2, c);
}

pub fn deinit(self: *Dialog) void {
    self.imtui.allocator.destroy(self);
}

pub fn groupbox(self: *Dialog, title: []const u8, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8) void {
    self._groupbox(title, self.r1 + r1, self.c1 + 1 + c1, self.r1 + r2, self.c1 + 1 + c2, colour);
}

fn _groupbox(self: *Dialog, title: []const u8, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8) void {
    self.imtui.text_mode.paint(r1, c1, r2, c2, colour, .Blank);
    self.imtui.text_mode.draw(r1, c1, colour, .TopLeft);
    self.imtui.text_mode.paint(r1, c1 + 1, r1 + 1, c2 - 1, colour, .Horizontal);
    self.imtui.text_mode.draw(r1, c2 - 1, colour, .TopRight);
    self.imtui.text_mode.paint(r1 + 1, c1, r2 - 1, c1 + 1, colour, .Vertical);
    self.imtui.text_mode.paint(r1 + 1, c2 - 1, r2 - 1, c2, colour, .Vertical);
    self.imtui.text_mode.draw(r2 - 1, c1, colour, .BottomLeft);
    self.imtui.text_mode.paint(r2 - 1, c1 + 1, r2, c2, colour, .Horizontal);
    self.imtui.text_mode.draw(r2 - 1, c2 - 1, colour, .BottomRight);

    const start = c1 + (c2 - c1 - title.len) / 2;
    self.imtui.text_mode.paint(r1, start - 1, r1 + 1, start + title.len + 1, colour, 0);
    self.imtui.text_mode.write(r1, start, title);
}
