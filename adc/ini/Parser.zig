const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Parser = @This();

pub const Event = union(enum) {
    pair: struct { key: []const u8, value: []const u8 },
};

pub const ErrorHandling = enum {
    ignore,
    report,
};

pub const Error = error{
    UnknownCharacter,
    KeyWithoutValue,
};

input: []const u8,
error_handling: ErrorHandling,

i: usize,
state: enum { idle, comment, key, value },

pub fn init(input: []const u8, error_handling: ErrorHandling) Parser {
    return .{
        .input = input,
        .error_handling = error_handling,
        .i = 0,
        .state = .idle,
    };
}

pub fn next(self: *Parser) Error!?Event {
    var key_start: usize = undefined;
    var value_start: usize = undefined;

    var i = self.i;
    defer self.i = i;

    while (i < self.input.len) : (i += 1) {
        const c = self.input[i];
        switch (self.state) {
            .idle => switch (c) {
                ';', '#' => self.state = .comment,
                'a'...'z' => {
                    key_start = i;
                    self.state = .key;
                },
                ' ', '\t', '\r', '\n' => {},
                else => {
                    self.state = .comment; // eat rest of line
                    try self.err(Error.UnknownCharacter);
                },
            },
            .comment => switch (c) {
                '\r', '\n' => self.state = .idle,
                else => {},
            },
            .key => switch (c) {
                'a'...'z', '_', ' ' => {},
                '=' => {
                    value_start = i + 1;
                    self.state = .value;
                },
                '\r', '\n' => {
                    self.state = .idle;
                    try self.err(Error.KeyWithoutValue);
                },
                else => {
                    self.state = .comment; // eat rest of line
                    try self.err(Error.UnknownCharacter);
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
        .key => try self.err(Error.KeyWithoutValue),
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

fn err(self: *const Parser, e: Error) Error!void {
    if (self.error_handling == .report)
        return e;
}

fn expectPairsHandling(input: []const u8, pairs: anytype, error_handling: Parser.ErrorHandling) !void {
    var p = Parser.init(input, error_handling);

    inline for (pairs) |pair| {
        if (@TypeOf(pair) == Parser.Error) {
            if (error_handling == .report)
                try testing.expectError(pair, p.next());
            continue;
        }

        try testing.expectEqualDeep(
            Parser.Event{ .pair = .{ .key = pair.@"0", .value = pair.@"1" } },
            p.next(),
        );
    }
    try testing.expectEqualDeep(null, p.next());
    try testing.expectEqualDeep(null, p.next());
}

fn expectPairs(input: []const u8, pairs: anytype) !void {
    try expectPairsHandling(input, pairs, .report);
    try expectPairsHandling(input, pairs, .ignore);
}

test Parser {
    try expectPairs(
        \\x=y
    , .{
        .{ "x", "y" },
    });

    try expectPairs(
        \\abc  = 0x123
        \\  ; nah
        \\# comments ...
        \\ not a comment=isn't # a comment ; at all   
        \\
    , .{
        .{ "abc", "0x123" },
        .{ "not a comment", "isn't # a comment ; at all" },
    });

    try expectPairs(
        \\
        \\ f = 3
        \\ z
        \\ awa=wa
    , .{
        .{ "f", "3" },
        Parser.Error.KeyWithoutValue,
        .{ "awa", "wa" },
    });

    try expectPairs(
        \\
        \\ f = 3
        \\ lmnop?=8
        \\ z=zz
    , .{
        .{ "f", "3" },
        Parser.Error.UnknownCharacter,
        .{ "z", "zz" },
    });

    try expectPairs(
        \\ m__=9
        \\ fazenda
        \\ h==
        \\ s?=8
    , .{
        .{ "m__", "9" },
        Parser.Error.KeyWithoutValue,
        .{ "h", "=" },
        Parser.Error.UnknownCharacter,
    });
}
