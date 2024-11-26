const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Dialog = @This();

imtui: *Imtui,
generation: usize,
title: []const u8,
height: usize,
width: usize,

pub fn create(imtui: *Imtui, title: []const u8, height: usize, width: usize) !*Dialog {
    var d = try imtui.allocator.create(Dialog);
    d.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .title = title,
        .height = undefined,
        .width = undefined,
    };
    d.describe(height, width);
    return d;
}

pub fn describe(self: *Dialog, height: usize, width: usize) void {
    self.height = height;
    self.width = width;

    const r1 = 1;
    const c1 = 10;
    const r2 = r1 + height + 1;
    const c2 = c1 + width + 1;

    self.imtui.text_mode.paint(r1, c1, r2, c2, 0x70, .Blank);
    self.imtui.text_mode.draw(r1, c1, 0x70, .TopLeft);
    self.imtui.text_mode.paint(r1, c1 + 1, r1 + 1, c2 - 1, 0x70, .Horizontal);
    self.imtui.text_mode.draw(r1, c2 - 1, 0x70, .TopRight);
    self.imtui.text_mode.paint(r1 + 1, c1, r2 - 1, c1 + 1, 0x70, .Vertical);
    self.imtui.text_mode.paint(r1 + 1, c2 - 1, r2 - 1, c2, 0x70, .Vertical);
    self.imtui.text_mode.draw(r2 - 1, c1, 0x70, .BottomLeft);
    self.imtui.text_mode.paint(r2 - 1, c1 + 1, r2, c2, 0x70, .Horizontal);
    self.imtui.text_mode.draw(r2 - 1, c2 - 1, 0x70, .BottomRight);
    for (r1 + 1..r2 + 1) |r| {
        self.imtui.text_mode.shadow(r, c2);
        self.imtui.text_mode.shadow(r, c2 + 1);
    }
    for (c1 + 2..c2) |c|
        self.imtui.text_mode.shadow(r2, c);

    const start = c1 + (c2 - c1 - self.title.len) / 2;
    self.imtui.text_mode.paint(r1, start - 1, r1 + 1, start + self.title.len + 1, 0x70, 0);
    self.imtui.text_mode.write(r1, start, self.title);
}

pub fn deinit(self: *Dialog) void {
    self.imtui.allocator.destroy(self);
}
