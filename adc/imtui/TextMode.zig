const std = @import("std");
const SDL = @import("sdl2");

const Font = @import("./Font.zig");

pub fn TextMode(H: usize, W: usize) type {
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
            Bullet = 0x07,
        };

        // https://retrocomputing.stackexchange.com/a/27805/20624
        // 4.380 Hz period.
        const FLIP_MS = @as(i16, @intFromFloat(@divFloor(1000, 4.380 * 2)));

        comptime H: usize = H,
        comptime W: usize = W,

        screen: [W * H]u16 = [_]u16{0x0000} ** (W * H),
        renderer: SDL.Renderer,
        font: Font,
        font_rendered: Font.Rendered,
        mouse_row: usize = H - 1,
        mouse_col: usize = W - 1,
        flip_timer: i16 = FLIP_MS,

        cursor_on: bool = true,
        cursor_inhibit: bool = false,
        cursor_row: usize = 0,
        cursor_col: usize = 0,

        pub fn init(renderer: SDL.Renderer, font: Font) !Self {
            return .{
                .renderer = renderer,
                .font = font,
                .font_rendered = try font.prepare(renderer),
            };
        }

        pub fn deinit(self: *const Self) void {
            self.font_rendered.deinit();
        }

        pub fn positionMouseAt(self: *Self, mouse_x: usize, mouse_y: usize) void {
            self.mouse_row = @max(0, @min(H - 1, mouse_y / self.font.char_height));
            self.mouse_col = @max(0, @min(W - 1, mouse_x / self.font.char_width));
        }

        pub fn present(self: *Self, delta_tick: u64) !void {
            var r: usize = 0;
            var c: usize = 0;
            for (self.screen) |pair| {
                const p = if (self.mouse_row == r and self.mouse_col == c)
                    ((7 - ((pair >> 12) & 0x7)) << 12) |
                        ((7 - ((pair >> 8) & 0x7)) << 8) |
                        (pair & 0xFF)
                    // This is an interesting alternative, which inverts within
                    // each half of the palette rather than forcing the lower
                    // half and making pairs like 0x7f degrade to 0x00 on hover
                    // (which is the authentic behaviour, above):
                    // (((((pair >> 12) & 0x8) | 7) - ((pair >> 12) & 0x7)) << 12) |
                    //     (((((pair >> 8) & 0x8) | 7) - ((pair >> 8) & 0x7)) << 8) |
                    //     (pair & 0xFF)
                else
                    pair;
                try self.font_rendered.render(self.renderer, p, c, r);

                if (c == W - 1) {
                    c = 0;
                    r += 1;
                } else c += 1;
            }

            // Don't crash if we get a huge delta_tick, such as on sleep, or
            // when using a debugger.
            self.flip_timer -|= @truncate(@as(i64, @intCast(delta_tick)));
            if (self.flip_timer <= 0) {
                self.flip_timer += FLIP_MS;
                self.cursor_on = !self.cursor_on;
            }

            if (self.cursor_on and !self.cursor_inhibit) {
                if (self.cursor_row >= H or self.cursor_col >= W)
                    std.debug.panic("cursed: {d},{d}", .{ self.cursor_row, self.cursor_col });
                const pair = self.screen[self.cursor_row * W + self.cursor_col];
                const fg = Font.CgaColours[(pair >> 8) & 0xF];
                try self.renderer.setColorRGBA(@intCast(fg >> 16), @intCast((fg >> 8) & 0xFF), @intCast(fg & 0xFF), 255);
                try self.renderer.fillRect(.{
                    .x = @intCast(self.cursor_col * self.font.char_width),
                    .y = @intCast(self.cursor_row * self.font.char_height + self.font.char_height - 3),
                    .width = @intCast(self.font.char_width - 1),
                    .height = 2,
                });
            }
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

        pub fn paintColour(
            self: *Self,
            r1: usize,
            c1: usize,
            r2: usize,
            c2: usize,
            colour: u8,
            mode: enum { fill, outline },
        ) void {
            std.debug.assert(r1 >= 0 and r1 <= H and r2 >= 0 and r2 <= H);
            std.debug.assert(c1 >= 0 and c1 <= W and c2 >= 0 and c2 <= W);
            for (r1..r2) |r|
                for (c1..c2) |c| {
                    if (mode == .outline and !(r == r1 or r == r2 - 1 or c == c1 or c == c2 - 1)) continue;
                    self.screen[r * W + c] = @as(u16, colour) << 8 |
                        (self.screen[r * W + c] & 0xFF);
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
            for (text, 0..) |char, i| {
                if (char == '&' and i != text.len - 1)
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

        pub fn box(self: *Self, r1: usize, c1: usize, r2: usize, c2: usize, colour: u8) void {
            self.paint(r1, c1, r2, c2, colour, .Blank);
            self.draw(r1, c1, colour, .TopLeft);
            self.paint(r1, c1 + 1, r1 + 1, c2 - 1, colour, .Horizontal);
            self.draw(r1, c2 - 1, colour, .TopRight);
            self.paint(r1 + 1, c1, r2 - 1, c1 + 1, colour, .Vertical);
            self.paint(r1 + 1, c2 - 1, r2 - 1, c2, colour, .Vertical);
            self.draw(r2 - 1, c1, colour, .BottomLeft);
            self.paint(r2 - 1, c1 + 1, r2, c2, colour, .Horizontal);
            self.draw(r2 - 1, c2 - 1, colour, .BottomRight);
        }

        pub const ScrollbarTarget = enum {
            hscr_left,
            hscr_right,
            hscr_toward_left,
            hscr_toward_right,
            vscr_up,
            vscr_down,
            vscr_toward_up,
            vscr_toward_down,

            pub fn isHscr(self: ScrollbarTarget) bool {
                return switch (self) {
                    .hscr_left, .hscr_right, .hscr_toward_left, .hscr_toward_right => true,
                    else => false,
                };
            }

            pub fn isVscr(self: ScrollbarTarget) bool {
                return switch (self) {
                    .vscr_up, .vscr_down, .vscr_toward_up, .vscr_toward_down => true,
                    else => false,
                };
            }
        };

        pub const Hscrollbar = struct {
            r: usize = 0,
            c1: usize = 0,
            c2: usize = 0,
            thumb: usize = 0,
            highest: usize = 0,

            pub const Hit = enum { left, toward_left, thumb, toward_right, right };

            pub fn hit(self: *const Hscrollbar, c: usize, cm: bool, cmt: ?ScrollbarTarget) ?Hit {
                if (c == self.c1 and (!cm or cmt == .hscr_left))
                    return .left;

                if (c > self.c1 and c < self.c2 - 1) {
                    if (c - self.c1 - 1 < self.thumb and (!cm or cmt == .hscr_toward_left))
                        return .toward_left
                    else if (c - self.c1 - 1 > self.thumb and (!cm or cmt == .hscr_toward_right))
                        return .toward_right
                    else if (!cm)
                        return .thumb;
                } else if (c == self.c2 - 1 and (!cm or cmt == .hscr_right))
                    return .right;

                return null;
            }
        };

        pub fn hscrollbar(self: *Self, r: usize, c1: usize, c2: usize, ix: usize, highest: usize) Hscrollbar {
            self.draw(r, c1, 0x70, .ArrowLeft);
            self.paint(r, c1 + 1, r + 1, c2 - 1, 0x70, .DotsLight);
            const thumb = if (highest > 0) ix * (c2 - c1 - 3) / highest else 0;
            self.draw(r, c1 + 1 + thumb, 0x00, .Blank);
            self.draw(r, c2 - 1, 0x70, .ArrowRight);
            return .{
                .r = r,
                .c1 = c1,
                .c2 = c2,
                .thumb = thumb,
                .highest = highest,
            };
        }

        pub const Vscrollbar = struct {
            c: usize = 0,
            r1: usize = 0,
            r2: usize = 0,
            thumb: usize = 0,
            highest: usize = 0,

            pub const Hit = enum { up, toward_up, thumb, toward_down, down };

            pub fn hit(self: *const Vscrollbar, r: usize, cm: bool, cmt: ?ScrollbarTarget) ?Hit {
                if (r == self.r1 and (!cm or cmt == .vscr_up))
                    return .up;

                if (r > self.r1 and r < self.r2 - 1) {
                    if (r - self.r1 - 1 < self.thumb and (!cm or cmt == .vscr_toward_up))
                        return .toward_up
                    else if (r - self.r1 - 1 > self.thumb and (!cm or cmt == .vscr_toward_down))
                        return .toward_down
                    else if (!cm)
                        return .thumb;
                } else if (r == self.r2 - 1 and (!cm or cmt == .vscr_down))
                    return .down;

                return null;
            }
        };

        pub fn vscrollbar(self: *Self, c: usize, r1: usize, r2: usize, ix: usize, highest: usize) Vscrollbar {
            self.draw(r1, c, 0x70, .ArrowUp);
            self.paint(r1 + 1, c, r2 - 1, c + 1, 0x70, .DotsLight);
            const thumb = if (highest > 0) ix * (r2 - r1 - 3) / highest else 0;
            self.draw(r1 + 1 + thumb, c, 0x00, .Blank);
            self.draw(r2 - 1, c, 0x70, .ArrowDown);
            return .{
                .c = c,
                .r1 = r1,
                .r2 = r2,
                .thumb = thumb,
                .highest = highest,
            };
        }
    };
}
