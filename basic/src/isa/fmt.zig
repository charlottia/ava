const std = @import("std");
const Allocator = std.mem.Allocator;

const isa = @import("./root.zig");

pub fn print(allocator: Allocator, writer: anytype, v: isa.Value) !void {
    switch (v) {
        .integer => |n| {
            if (n >= 0)
                try writer.writeByte(' ');
            try std.fmt.format(writer, "{d} ", .{n});
        },
        .long => |n| {
            if (n >= 0)
                try writer.writeByte(' ');
            try std.fmt.format(writer, "{d} ", .{n});
        },
        .single => |n| {
            if (n >= 0)
                try writer.writeByte(' ');
            try printFloating(allocator, writer, n);
            try writer.writeByte(' ');
        },
        .double => |n| {
            if (n >= 0)
                try writer.writeByte(' ');
            try printFloating(allocator, writer, n);
            try writer.writeByte(' ');
        },
        .string => |s| try writer.writeAll(s),
    }
}

fn printFloating(allocator: Allocator, writer: anytype, f: anytype) !void {
    const s = try std.fmt.allocPrint(allocator, "{d}", .{f});
    defer allocator.free(s);

    var len = s.len;
    // QB accepts and prefers ".1" and "-.1".
    if (std.mem.startsWith(u8, s, "0.")) {
        std.mem.copyForwards(u8, s, s[1..]);
        len -= 1;
    } else if (std.mem.startsWith(u8, s, "-0.")) {
        std.mem.copyForwards(u8, s[1..], s[2..]);
        len -= 1;
    }

    // Round the last digit(s) to match QBASIC.
    //
    // This is an enormous hack and I don't like it. Is precise compatibility
    // worth this? Is there a better way to do it that'd more closely follow how
    // QB actually works?
    var has_point = false;
    for (s[0..len]) |c|
        if (c == '.') {
            has_point = true;
            break;
        };

    if (has_point) {
        var digits = len - 1;
        if (s[0] == '-') digits -= 1;
        const cap = switch (@TypeOf(f)) {
            f32 => 8,
            f64 => 16,
            else => @compileError("printFloating given f " ++ @typeName(@TypeOf(f))),
        };
        while (digits >= cap) : (digits -= 1) {
            std.debug.assert(s[len - 1] >= '0' and s[len - 1] <= '9');
            std.debug.assert(s[len - 2] >= '0' and s[len - 2] <= '9');
            if (s[len - 1] >= '5') {
                if (!(s[len - 2] >= '0' and s[len - 2] <= '8')) {
                    // Note to self: I fully expect this won't be sufficient and
                    // we'll have to iterate backwards. Sorry.
                    std.debug.panic("nope: '{s}'", .{s[0..len]});
                }
                std.debug.assert(s[len - 2] <= '8');
                s[len - 2] += 1;
                len -= 1;
            } else {
                len -= 1;
            }
        }
    }

    try writer.writeAll(s[0..len]);
}
