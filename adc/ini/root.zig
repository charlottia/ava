const std = @import("std");
const testing = std.testing;

pub const Parser = @import("./Parser.zig");
const serdes = @import("./SerDes.zig");
pub const SerDes = serdes.SerDes;

comptime {
    testing.refAllDeclsRecursive(Parser);
    testing.refAllDeclsRecursive(serdes);
}
