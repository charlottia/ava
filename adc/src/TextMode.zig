const std = @import("std");
const SDL = @import("sdl2");

const Font = @import("./Font.zig");

pub fn TextMode(W: usize, H: usize) type {
    return struct {
        const Self = @This();

        // CP437 box-drawing and other characters.
        const Special = enum(u8) {
            Blank = 0x00,
            TopLeft = 0xda,
            TopRight = 0xbf,
            BottomLeft = 0xc0,
            BottomRight = 0xd9,
            Vertical = 0xb3,
            Horizontal = 0xc4,
            VerticalRight = 0xc3,
            VerticalLeft = 0xb4,
            ArrowVertical = 0x12,
            ArrowUp = 0x18,
            ArrowDown = 0x19,
            ArrowRight = 0x1a,
            ArrowLeft = 0x1b,
            DotsLight = 0xb0,
        };

        screen: [W * H]u16 = [_]u16{0} ** (W * H),
        renderer: SDL.Renderer,
        font: *Font,
        mouse_row: usize = H - 1,
        mouse_col: usize = W - 1,

        pub fn init(renderer: SDL.Renderer, font: *Font) !Self {
            try font.prepare(renderer);
            return .{
                .renderer = renderer,
                .font = font,
            };
        }

        pub fn positionMouseAt(self: *Self, mouse_x: usize, mouse_y: usize) void {
            self.mouse_row = mouse_y / self.font.char_height;
            self.mouse_col = mouse_x / self.font.char_width;
        }

        pub fn present(self: *const Self) !void {
            try self.renderer.clear();

            for (0..H) |r|
                for (0..W) |c| {
                    var pair = self.screen[r * W + c];
                    if (self.mouse_row == r and self.mouse_col == c)
                        pair = ((7 - (pair >> 12)) << 12) |
                            ((7 - ((pair >> 8) & 0x7)) << 8) |
                            (pair & 0xFF);
                    try self.font.render(self.renderer, pair, c, r);
                };

            // if (self.cursor_on and !self.cursor_inhibit) {
            //     const pair = self.screen[self.cursor_y * W + self.cursor_x];
            //     const fg = Font.CgaColors[(pair >> 8) & 0xF];
            //     try self.renderer.setColorRGBA(@intCast(fg >> 16), @intCast((fg >> 8) & 0xFF), @intCast(fg & 0xFF), 255);
            //     try self.renderer.fillRect(.{
            //         .x = @intCast(self.cursor_x * self.font.char_width),
            //         .y = @intCast(self.cursor_y * self.font.char_height + self.font.char_height - 3),
            //         .width = @intCast(self.font.char_width - 1),
            //         .height = 2,
            //     });
            // }

            self.renderer.present();
        }

        pub fn clear(self: *Self, colour: u8) void {
            @memset(&self.screen, @as(u16, colour) << 8);
        }

        pub fn draw(self: *Self, r: usize, c: usize, colour: u8, special: Special) void {
            self.screen[r * W + c] = @as(u16, colour) << 8 | @intFromEnum(special);
        }

        pub fn paint(self: *Self, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8, char: anytype) void {
            std.debug.assert(r1 >= 0 and r1 <= H and r2 >= 0 and r2 <= H);
            std.debug.assert(c1 >= 0 and c1 <= W and c2 >= 0 and c2 <= W);
            for (r1..r2) |r|
                for (c1..c2) |c| {
                    self.screen[r * W + c] = @as(u16, colour) << 8 |
                        (if (@TypeOf(char) == @TypeOf(.enum_literal)) @intFromEnum(@as(Special, char)) else char);
                };
        }

        pub fn shadow(self: *Self, r: usize, c: usize) void {
            self.screen[r * W + c] &= 0x00ff;
            self.screen[r * W + c] |= 0x0800;
        }

        pub fn write(self: *Self, r: usize, c: usize, text: []const u8) void {
            // For now we depend on there being zero char value in the cell.
            for (text, 0..) |char, i|
                self.screen[r * W + c + i] |= char;
        }

        pub fn writeAccelerated(self: *Self, r: usize, c: usize, text: []const u8, show_acc: bool) void {
            // As above.

            var next_highlight = false;
            var j: usize = 0;
            for (text) |char| {
                if (char == '&')
                    next_highlight = true
                else {
                    self.screen[r * W + c + j] |= char;
                    if (next_highlight and show_acc) {
                        self.screen[r * W + c + j] &= 0xf0ff;
                        self.screen[r * W + c + j] |= 0x0f00;
                        next_highlight = false;
                    }
                    j += 1;
                }
            }
        }
    };
}
