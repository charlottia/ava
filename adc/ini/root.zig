const std = @import("std");
const testing = std.testing;

pub const Parser = @import("./Parser.zig");
const serdes = @import("./SerDes.zig");
pub const SerDes = serdes.SerDes;
const preferences = @import("./Preferences.zig");
pub const Preferences = preferences.Preferences;

comptime {
    testing.refAllDeclsRecursive(Parser);
    testing.refAllDeclsRecursive(serdes);
    testing.refAllDeclsRecursive(preferences);
}
