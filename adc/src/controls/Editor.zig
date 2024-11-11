const Imtui = @import("../Imtui.zig");

const Editor = @This();

imtui: *Imtui,
generation: usize,
id: usize,
r1: usize,
c1: usize,
r2: usize,
c2: usize,
_title: []const u8,
_immediate: bool,

pub fn create(imtui: *Imtui, id: usize, r1: usize, c1: usize, r2: usize, c2: usize) !*Editor {
    var e = try imtui.allocator.create(Editor);
    e.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .id = id,
        .r1 = undefined,
        .c1 = undefined,
        .r2 = undefined,
        .c2 = undefined,
        ._title = undefined,
        ._immediate = undefined,
    };
    e.describe(r1, c1, r2, c2);
    return e;
}

pub fn describe(self: *Editor, r1: usize, c1: usize, r2: usize, c2: usize) void {
    self.r1 = r1;
    self.c1 = c1;
    self.r2 = r2;
    self.c2 = c2;
    self._title = "";
    self._immediate = false;
}

pub fn deinit(self: *Editor) void {
    self.imtui.allocator.destroy(self);
}

pub fn title(self: *Editor, t: []const u8) void {
    self._title = t;
}

pub fn immediate(self: *Editor) void {
    self._immediate = true;
}

pub fn end(self: *Editor) void {
    const active = self.imtui.focus_editor == self.id;
    const fullscreened = false; // XXX
    const verticalScrollThumb = 0; // XXX
    const horizontalScrollThumb = 0; // XXX

    // XXX: r1==1 checks here are iffy.

    self.imtui.text_mode.draw(self.r1, self.c1, 0x17, if (self.r1 == 1) .TopLeft else .VerticalRight);
    for (self.c1 + 1..self.c2 - 1) |x|
        self.imtui.text_mode.draw(self.r1, x, 0x17, .Horizontal);

    const start = self.c1 + (self.c2 - self._title.len) / 2;
    const colour: u8 = if (active) 0x71 else 0x17;
    self.imtui.text_mode.paint(self.r1, start - 1, self.r1 + 1, start + self._title.len + 1, colour, 0);
    self.imtui.text_mode.write(self.r1, start, self._title);
    self.imtui.text_mode.draw(self.r1, self.c2 - 1, 0x17, if (self.r1 == 1) .TopRight else .VerticalLeft);

    if (!self._immediate) {
        // TODO: fullscreen control separate, rendered on top?
        self.imtui.text_mode.draw(self.r1, self.c2 - 5, 0x17, .VerticalLeft);
        self.imtui.text_mode.draw(self.r1, self.c2 - 4, 0x71, if (fullscreened) .ArrowVertical else .ArrowUp);
        self.imtui.text_mode.draw(self.r1, self.c2 - 3, 0x17, .VerticalRight);
    }

    self.imtui.text_mode.paint(self.r1 + 1, self.c1, self.r2, self.c1 + 1, 0x17, .Vertical);
    self.imtui.text_mode.paint(self.r1 + 1, self.c2 - 1, self.r2, self.c2, 0x17, .Vertical);
    self.imtui.text_mode.paint(self.r1 + 1, self.c1 + 1, self.r2, self.c2 - 1, 0x17, .Blank);

    // --8<-- editor contents go here --8<--

    if (active and !self._immediate) {
        if (self.r2 - self.r1 > 4) {
            self.imtui.text_mode.draw(self.r1 + 1, self.c2 - 1, 0x70, .ArrowUp);
            self.imtui.text_mode.paint(self.r1 + 2, self.c2 - 1, self.r2 - 2, self.c2, 0x70, .DotsLight);
            self.imtui.text_mode.draw(self.r1 + 2 + verticalScrollThumb, self.c2 - 1, 0x00, .Blank);
            self.imtui.text_mode.draw(self.r2 - 2, self.c2 - 1, 0x70, .ArrowDown);
        }

        if (self.r2 - self.r1 > 2) {
            self.imtui.text_mode.draw(self.r2 - 1, self.c1 + 1, 0x70, .ArrowLeft);
            self.imtui.text_mode.paint(self.r2 - 1, self.c1 + 2, self.r2, self.c2 - 2, 0x70, .DotsLight);
            self.imtui.text_mode.draw(self.r2 - 1, self.c1 + 2 + horizontalScrollThumb, 0x00, .Blank);
            self.imtui.text_mode.draw(self.r2 - 1, self.c2 - 2, 0x70, .ArrowRight);
        }
    }
}
