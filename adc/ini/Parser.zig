const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Parser = @This();

pub const Event = union(enum) {
    group: []const u8,
    pair: struct { key: []const u8, value: []const u8 },
};

pub const ErrorHandling = enum {
    ignore,
    report,
};

pub const Error = error{
    InvalidCharacter,
    Incomplete,
};

input: []const u8,
error_handling: ErrorHandling,

i: usize,
state: enum { idle, comment, group, group_after, key, value },
unputted: ?Event = null,

pub fn init(input: []const u8, error_handling: ErrorHandling) Parser {
    return .{
        .input = input,
        .error_handling = error_handling,
        .i = 0,
        .state = .idle,
    };
}

pub fn next(self: *Parser) Error!?Event {
    if (self.unputted) |ev| {
        self.unputted = null;
        return ev;
    }

    var key_start: usize = undefined;
    var value_start: usize = undefined;

    var i = self.i;
    defer self.i = i;

    while (i < self.input.len) : (i += 1) {
        const c = self.input[i];
        switch (self.state) {
            .idle => switch (c) {
                ';', '#' => self.state = .comment,
                'a'...'z', 'A'...'Z' => {
                    key_start = i;
                    self.state = .key;
                },
                '[' => {
                    key_start = i;
                    self.state = .group;
                },
                ' ', '\t', '\r', '\n' => {},
                else => {
                    self.state = .comment; // eat rest of line
                    try self.err(Error.InvalidCharacter);
                },
            },
            .group => switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '_', ' ' => {},
                ']' => {
                    i += 1;
                    self.state = .group_after;
                    return .{ .group = std.mem.trim(u8, self.input[key_start + 1 .. i - 1], " ") };
                },
                else => {
                    self.state = .comment; // eat rest of line
                    try self.err(Error.InvalidCharacter);
                },
            },
            .group_after => switch (c) {
                ' ' => {},
                '\r', '\n' => self.state = .idle,
                else => {
                    self.state = .comment; // eat rest of line
                    try self.err(Error.InvalidCharacter);
                },
            },
            .comment => switch (c) {
                '\r', '\n' => self.state = .idle,
                else => {},
            },
            .key => switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '_', ' ' => {},
                '=' => {
                    value_start = i + 1;
                    self.state = .value;
                },
                '\r', '\n' => {
                    self.state = .idle;
                    try self.err(Error.Incomplete);
                },
                else => {
                    self.state = .comment; // eat rest of line
                    try self.err(Error.InvalidCharacter);
                },
            },
            .value => switch (c) {
                '\r', '\n' => {
                    const key = std.mem.trim(u8, self.input[key_start .. value_start - 1], "\t ");
                    const value = std.mem.trim(u8, self.input[value_start..i], "\t ");
                    i += 1;
                    self.state = .idle;
                    return .{ .pair = .{ .key = key, .value = value } };
                },
                else => {},
            },
        }
    }

    switch (self.state) {
        .idle, .comment => {},
        .group => try self.err(Error.Incomplete),
        .group_after => {},
        .key => try self.err(Error.Incomplete),
        .value => {
            const key = std.mem.trim(u8, self.input[key_start .. value_start - 1], "\t ");
            const value = std.mem.trim(u8, self.input[value_start..], "\t ");
            self.state = .idle;
            return .{ .pair = .{ .key = key, .value = value } };
        },
    }

    self.state = .idle;
    return null;
}

pub fn unput(self: *Parser, ev: Event) void {
    std.debug.assert(self.unputted == null);
    self.unputted = ev;
}

fn err(self: *const Parser, e: Error) Error!void {
    if (self.error_handling == .report)
        return e;
}

fn expectEventsHandling(input: []const u8, events: anytype, error_handling: Parser.ErrorHandling) !void {
    var p = Parser.init(input, error_handling);

    inline for (events) |ev| {
        const E = @TypeOf(ev);
        if (E == Parser.Error) {
            if (error_handling == .report)
                try testing.expectError(ev, p.next());
        } else if (@typeInfo(@TypeOf(ev)) == .pointer) {
            try testing.expectEqualDeep(Parser.Event{ .group = ev }, p.next());
        } else {
            try testing.expectEqualDeep(
                Parser.Event{ .pair = .{ .key = ev.@"0", .value = ev.@"1" } },
                p.next(),
            );
        }
    }
    try testing.expectEqualDeep(null, p.next());
    try testing.expectEqualDeep(null, p.next());
}

fn expectEvents(input: []const u8, events: anytype) !void {
    try expectEventsHandling(input, events, .report);
    try expectEventsHandling(input, events, .ignore);
}

test "base" {
    try expectEvents(
        \\x=y
    , .{
        .{ "x", "y" },
    });

    try expectEvents(
        \\abc  = 0x123
        \\  ; nah
        \\# comments ...
        \\ not a comment=isn't # a comment ; at all   
        \\
    , .{
        .{ "abc", "0x123" },
        .{ "not a comment", "isn't # a comment ; at all" },
    });

    try expectEvents(
        \\
        \\ f = 3
        \\ z
        \\ awa=wa
    , .{
        .{ "f", "3" },
        Parser.Error.Incomplete,
        .{ "awa", "wa" },
    });

    try expectEvents(
        \\
        \\ f = 3
        \\ lmnop?=8
        \\ z=zz
    , .{
        .{ "f", "3" },
        Parser.Error.InvalidCharacter,
        .{ "z", "zz" },
    });

    try expectEvents(
        \\ m__=9
        \\ fazenda
        \\ h==
        \\ s?=8
    , .{
        .{ "m__", "9" },
        Parser.Error.Incomplete,
        .{ "h", "=" },
        Parser.Error.InvalidCharacter,
    });
}

test "group" {
    try expectEvents(
        \\a=1
        \\[b_f_g]
        \\c=2
    , .{
        .{ "a", "1" },
        "b_f_g",
        .{ "c", "2" },
    });
}
