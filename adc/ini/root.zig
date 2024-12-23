const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const Parser = struct {
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

    pub fn init(input: []const u8, error_handling: ErrorHandling) Parser {
        return .{
            .input = input,
            .error_handling = error_handling,
            .i = 0,
        };
    }

    pub fn next(self: *Parser) Error!?Event {
        var state: enum {
            idle,
            comment,
            key,
            value,
        } = .idle;
        var key_start: usize = undefined;
        var value_start: usize = undefined;

        var i = self.i;
        defer self.i = i;

        while (i < self.input.len) : (i += 1) {
            const c = self.input[i];
            switch (state) {
                .idle => switch (c) {
                    ';', '#' => state = .comment,
                    'a'...'z' => {
                        key_start = i;
                        state = .key;
                    },
                    ' ', '\t', '\r', '\n' => {},
                    else => try self.err(Error.UnknownCharacter),
                },
                .comment => switch (c) {
                    '\r', '\n' => state = .idle,
                    else => {},
                },
                .key => switch (c) {
                    'a'...'z', '_', ' ' => {},
                    '=' => {
                        value_start = i + 1;
                        state = .value;
                    },
                    '\r', '\n' => {
                        try self.err(Error.KeyWithoutValue);
                        state = .idle;
                    },
                    else => try self.err(Error.UnknownCharacter),
                },
                .value => switch (c) {
                    '\r', '\n' => {
                        const key = std.mem.trim(u8, self.input[key_start .. value_start - 1], "\t ");
                        const value = std.mem.trim(u8, self.input[value_start..i], "\t ");
                        i += 1;
                        return .{ .pair = .{ .key = key, .value = value } };
                    },
                    else => {},
                },
            }
        }

        switch (state) {
            .idle, .comment => {},
            .key => try self.err(Error.KeyWithoutValue),
            .value => {
                const key = std.mem.trim(u8, self.input[key_start .. value_start - 1], "\t ");
                const value = std.mem.trim(u8, self.input[value_start..], "\t ");
                return .{ .pair = .{ .key = key, .value = value } };
            },
        }

        return null;
    }

    fn err(self: *const Parser, e: Error) Error!void {
        if (self.error_handling == .report)
            return e;
    }
};

fn expectPairs(input: []const u8, pairs: anytype) !void {
    var p = Parser.init(input, .report);

    inline for (pairs) |pair| {
        if (@TypeOf(pair) == Parser.Error) {
            try testing.expectError(pair, p.next());
            // Parser state is undefined after reporting an error.
            return;
        }

        try testing.expectEqualDeep(
            Parser.Event{ .pair = .{ .key = pair.@"0", .value = pair.@"1" } },
            p.next(),
        );
    }
    try testing.expectEqualDeep(null, p.next());
    try testing.expectEqualDeep(null, p.next());
}

test "Parser" {
    try expectPairs(
        \\x=y
    ,
        .{.{ "x", "y" }},
    );

    try expectPairs(
        \\abc  = 0x123
        \\  ; nah
        \\# comments ...
        \\ not a comment=isn't # a comment ; at all   
        \\
    ,
        .{
            .{ "abc", "0x123" },
            .{ "not a comment", "isn't # a comment ; at all" },
        },
    );

    try expectPairs(
        \\
        \\ f = 3
        \\ z
    ,
        .{
            .{ "f", "3" },
            Parser.Error.KeyWithoutValue,
        },
    );
}

test "Parser.ErrorHandling.ignore" {
    var p = Parser.init(
        \\ m()=9
        \\ fazenda
        \\ h==
    , .ignore);
    try testing.expectEqualDeep(Parser.Event{ .pair = .{ .key = "m()", .value = "9" } }, p.next());
    try testing.expectEqualDeep(Parser.Event{ .pair = .{ .key = "h", .value = "=" } }, p.next());
    try testing.expectEqualDeep(null, p.next());
}
