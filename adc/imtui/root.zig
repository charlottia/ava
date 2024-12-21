pub const SDL = @import("sdl2");
pub const Imtui = @import("./Imtui.zig");
pub const Font = @import("./Font.zig");
pub const TextMode = @import("./TextMode.zig").TextMode;

pub const fonts = .{
    .@"8x16" = @embedFile("./fonts/8x16.txt"),
    .@"9x16" = @embedFile("./fonts/9x16.txt"),
    .moderndos = @embedFile("./fonts/moderndos.txt"),
};
