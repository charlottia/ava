const SDL = @import("sdl2");

const Imtui = @import("../Imtui.zig");

const Button = @This();

pub const Impl = struct {
    imtui: *Imtui,
    generation: usize,
    r: usize = undefined,
    c: usize = undefined,
    colour: u8 = undefined,
    label: []const u8,

    chosen: bool = false,
    inverted: bool = false,

    pub fn describe(self: *Impl, r: usize, c: usize, colour: u8) void {
        self.r = r;
        self.c = c;
        self.colour = if (self.inverted)
            ((colour & 0x0f) << 4) | ((colour & 0xf0) >> 4)
        else
            colour;
        self.imtui.text_mode.paint(r, c, r + 1, c + self.label.len, self.colour, .Blank);
        self.imtui.text_mode.write(r, c, self.label);
    }

    pub fn deinit(self: *Impl) void {
        self.imtui.allocator.destroy(self);
    }

    pub fn mouseIsOver(self: *const Impl) bool {
        return self.imtui.mouse_row == self.r and self.imtui.mouse_col >= self.c and self.imtui.mouse_col < self.c + self.label.len;
    }

    pub fn handleMouseDown(self: *Impl, b: SDL.MouseButton, clicks: u8) !void {
        // These don't discriminate on mouse button.
        _ = b;
        _ = clicks;

        self.inverted = true;
    }

    pub fn handleMouseDrag(self: *Impl, b: SDL.MouseButton) !void {
        _ = b;

        self.inverted = self.mouseIsOver();
    }

    pub fn handleMouseUp(self: *Impl, b: SDL.MouseButton, clicks: u8) !void {
        _ = b;
        _ = clicks;

        if (self.inverted) {
            self.inverted = false;
            self.chosen = true;
        }
    }
};

impl: *Impl,

pub fn create(imtui: *Imtui, r: usize, c: usize, colour: u8, label: []const u8) !Button {
    var b = try imtui.allocator.create(Impl);
    b.* = .{
        .imtui = imtui,
        .generation = imtui.generation,
        .label = label,
    };
    b.describe(r, c, colour);
    return .{ .impl = b };
}

pub fn chosen(self: Button) bool {
    defer self.impl.chosen = false;
    return self.impl.chosen;
}
