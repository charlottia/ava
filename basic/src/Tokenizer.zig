const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Token = @import("Token.zig");
const locz = @import("loc.zig");
const Loc = locz.Loc;
const Range = locz.Range;
const ErrorInfo = @import("ErrorInfo.zig");

const Tokenizer = @This();

allocator: Allocator,
loc: Loc = .{ .row = 1, .col = 1 },

pub const Error = error{
    UnexpectedChar,
    UnexpectedEnd,
};

const LocOffset = struct {
    loc: Loc,
    offset: usize,
};

const State = union(enum) {
    init,
    integer: LocOffset,
    minus: LocOffset,
    floating: LocOffset,
    floating_exponent: struct {
        start: LocOffset,
        double: bool, // [eE] for single, [dD] for double.
        pointed: bool, // Was the preceding token integral, or did it have a point?
        state: enum { init, sign, exp },
    },
    bareword: LocOffset,
    string: LocOffset,
    fileno: LocOffset,
    remark: LocOffset,
    angleo,
    anglec,
};

pub fn tokenize(allocator: Allocator, inp: []const u8, errorinfo: ?*ErrorInfo) ![]Token {
    var t = Tokenizer{
        .allocator = allocator,
    };
    return t.feed(allocator, inp) catch |err| {
        if (errorinfo) |ei|
            ei.loc = t.loc;
        return err;
    };
}

fn feed(self: *Tokenizer, allocator: Allocator, inp: []const u8) ![]Token {
    var tx = std.ArrayListUnmanaged(Token){};
    errdefer tx.deinit(allocator);

    var state: State = .init;
    var i: usize = 0;
    var rewind: usize = 0;
    var rewinds: [1]Loc = undefined;
    var last_was_cr = false;
    while (i < inp.len) : ({
        // XXX: This rewinder isn't robust to multiple consecutive rewind=2.
        if (rewind == 0) {
            rewinds[0] = self.loc;
            if (inp[i] == '\n') {
                self.loc.row += 1;
                self.loc.col = 1;
            } else if (inp[i] == '\t') {
                self.loc.col += 1;
                while (self.loc.col % 8 != 0)
                    self.loc.col += 1;
            } else {
                self.loc.col += 1;
            }
            i += 1;
        } else if (rewind == 1) {
            rewind = 0;
        } else if (rewind == 2) {
            rewind = 0;
            i -= 1;
            self.loc = rewinds[0];
        } else {
            @panic("rewind > 2 unhandled");
        }
    }) {
        const c = inp[i];
        const last_last_was_cr = last_was_cr;
        last_was_cr = false;

        switch (state) {
            .init => {
                if (c >= '0' and c <= '9') {
                    state = .{ .integer = .{ .loc = self.loc, .offset = i } };
                } else if (c == '.') {
                    state = .{ .floating = .{ .loc = self.loc, .offset = i } };
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    state = .{ .bareword = .{ .loc = self.loc, .offset = i } };
                } else if (c == '"') {
                    state = .{ .string = .{ .loc = self.loc, .offset = i + 1 } };
                } else if (c == ' ') {
                    // nop
                } else if (c == '\t') {
                    // nop
                } else if (c == '\r') {
                    last_was_cr = true;
                } else if (c == '\n') {
                    try tx.append(allocator, attach(
                        .linefeed,
                        if (last_last_was_cr) self.loc.back() else self.loc,
                        self.loc,
                        inp[(if (last_last_was_cr) i - 1 else i) .. i + 1],
                    ));
                } else if (c == '\'') {
                    state = .{ .remark = .{ .loc = self.loc, .offset = i } };
                } else if (c == ',') {
                    try tx.append(allocator, attach(.comma, self.loc, self.loc, inp[i .. i + 1]));
                } else if (c == ';') {
                    try tx.append(allocator, attach(.semicolon, self.loc, self.loc, inp[i .. i + 1]));
                } else if (c == ':') {
                    try tx.append(allocator, attach(.colon, self.loc, self.loc, inp[i .. i + 1]));
                } else if (c == '=') {
                    try tx.append(allocator, attach(.equals, self.loc, self.loc, inp[i .. i + 1]));
                } else if (c == '+') {
                    try tx.append(allocator, attach(.plus, self.loc, self.loc, inp[i .. i + 1]));
                } else if (c == '-') {
                    state = .{ .minus = .{ .loc = self.loc, .offset = i } };
                } else if (c == '*') {
                    try tx.append(allocator, attach(.asterisk, self.loc, self.loc, inp[i .. i + 1]));
                } else if (c == '/') {
                    try tx.append(allocator, attach(.fslash, self.loc, self.loc, inp[i .. i + 1]));
                } else if (c == '\\') {
                    try tx.append(allocator, attach(.bslash, self.loc, self.loc, inp[i .. i + 1]));
                } else if (c == '(') {
                    try tx.append(allocator, attach(.pareno, self.loc, self.loc, inp[i .. i + 1]));
                } else if (c == ')') {
                    try tx.append(allocator, attach(.parenc, self.loc, self.loc, inp[i .. i + 1]));
                } else if (c == '<') {
                    state = .angleo;
                } else if (c == '>') {
                    state = .anglec;
                } else if (c == '#') {
                    state = .{ .fileno = .{ .loc = self.loc, .offset = i } };
                } else {
                    return Error.UnexpectedChar;
                }
            },
            .integer => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else if (c == 'e' or c == 'E') {
                    state = .{ .floating_exponent = .{
                        .start = start,
                        .double = false,
                        .pointed = false,
                        .state = .init,
                    } };
                } else if (c == 'd' or c == 'D') {
                    state = .{ .floating_exponent = .{
                        .start = start,
                        .double = true,
                        .pointed = false,
                        .state = .init,
                    } };
                } else if (c == '.') {
                    state = .{ .floating = start };
                } else if (c == '%') {
                    const span = inp[start.offset .. i + 1];
                    try tx.append(allocator, attach(.{
                        .integer = try std.fmt.parseInt(i16, span[0 .. span.len - 1], 10),
                    }, start.loc, self.loc, span));
                    state = .init;
                } else if (c == '&') {
                    const span = inp[start.offset .. i + 1];
                    try tx.append(allocator, attach(.{
                        .long = try std.fmt.parseInt(i32, span[0 .. span.len - 1], 10),
                    }, start.loc, self.loc, span));
                    state = .init;
                } else if (c == '!') {
                    const span = inp[start.offset .. i + 1];
                    try tx.append(allocator, attach(.{
                        .single = try std.fmt.parseFloat(f32, span[0 .. span.len - 1]),
                    }, start.loc, self.loc, span));
                    state = .init;
                } else if (c == '#') {
                    const span = inp[start.offset .. i + 1];
                    try tx.append(allocator, attach(.{
                        .double = try std.fmt.parseFloat(f64, span[0 .. span.len - 1]),
                    }, start.loc, self.loc, span));
                    state = .init;
                } else {
                    const span = inp[start.offset..i];
                    try tx.append(allocator, attach(
                        try resolveIntegral(span),
                        start.loc,
                        self.loc.back(),
                        span,
                    ));
                    state = .init;
                    rewind = 1;
                }
            },
            .minus => |start| {
                if (c >= '0' and c <= '9') {
                    state = .{ .integer = start };
                } else if (c == '.') {
                    state = .{ .floating = start };
                } else {
                    try tx.append(allocator, attach(.minus, start.loc, start.loc, inp[i - 1 .. i]));
                    state = .init;
                    rewind = 1;
                }
            },
            .floating => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else if (c == 'e' or c == 'E') {
                    state = .{ .floating_exponent = .{
                        .start = start,
                        .double = false,
                        .pointed = true,
                        .state = .init,
                    } };
                } else if (c == 'd' or c == 'D') {
                    state = .{ .floating_exponent = .{
                        .start = start,
                        .double = true,
                        .pointed = true,
                        .state = .init,
                    } };
                } else if (c == '!') {
                    const span = inp[start.offset .. i + 1];
                    try tx.append(allocator, attach(.{
                        .single = try std.fmt.parseFloat(f32, span[0 .. span.len - 1]),
                    }, start.loc, self.loc, span));
                    state = .init;
                } else if (c == '#') {
                    const span = inp[start.offset .. i + 1];
                    try tx.append(allocator, attach(.{
                        .double = try std.fmt.parseFloat(f64, span[0 .. span.len - 1]),
                    }, start.loc, self.loc, span));
                    state = .init;
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    return Error.UnexpectedChar;
                } else {
                    const span = inp[start.offset..i];
                    try tx.append(allocator, attach(
                        try resolveFloating(span),
                        start.loc,
                        self.loc.back(),
                        span,
                    ));
                    state = .init;
                    rewind = 1;
                }
            },
            .floating_exponent => |*fe| {
                switch (fe.state) {
                    .init => {
                        if (c == '+' or c == '-') {
                            fe.state = .sign;
                        } else if (c >= '0' and c <= '9') {
                            fe.state = .exp;
                        } else {
                            const span = inp[fe.start.offset .. i - 1];
                            if (fe.pointed)
                                // 1.2eX
                                try tx.append(allocator, attach(
                                    try resolveFloating(span),
                                    fe.start.loc,
                                    self.loc.back().back(),
                                    span,
                                ))
                            else
                                // 1eX
                                try tx.append(allocator, attach(
                                    try resolveIntegral(span),
                                    fe.start.loc,
                                    self.loc.back().back(),
                                    span,
                                ));
                            state = .init;
                            rewind = 2;
                        }
                    },
                    .sign => {
                        if (c >= '0' and c <= '9') {
                            fe.state = .exp;
                        } else {
                            const span = inp[fe.start.offset..i];
                            try tx.append(allocator, attach(
                                try self.resolveExponent(fe.double, span),
                                fe.start.loc,
                                self.loc.back(),
                                span,
                            ));
                            state = .init;
                            rewind = 1;
                        }
                    },
                    .exp => {
                        if (c >= '0' and c <= '9') {
                            // nop
                        } else {
                            const span = inp[fe.start.offset..i];
                            try tx.append(allocator, attach(
                                try self.resolveExponent(fe.double, span),
                                fe.start.loc,
                                self.loc.back(),
                                span,
                            ));
                            state = .init;
                            rewind = 1;
                        }
                    },
                }
            },
            .bareword => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    // nop
                } else if (c == '%' or c == '&' or c == '!' or c == '#' or c == '$') {
                    const span = inp[start.offset .. i + 1];
                    try tx.append(allocator, attach(
                        .{ .label = span },
                        start.loc,
                        self.loc,
                        span,
                    ));
                    state = .init;
                } else if (c == ':') {
                    const span = inp[start.offset .. i + 1];
                    try tx.append(allocator, attach(
                        .{ .jumplabel = span },
                        start.loc,
                        self.loc,
                        span,
                    ));
                    state = .init;
                } else if (std.ascii.eqlIgnoreCase(inp[start.offset..i], "rem")) {
                    state = .{ .remark = start };
                } else {
                    const span = inp[start.offset..i];
                    try tx.append(allocator, attach(
                        classifyBareword(span),
                        start.loc,
                        self.loc.back(),
                        span,
                    ));
                    state = .init;
                    rewind = 1;
                }
            },
            .string => |start| {
                if (c == '"') {
                    try tx.append(allocator, attach(
                        .{ .string = inp[start.offset..i] },
                        start.loc,
                        self.loc,
                        inp[start.offset - 1 .. i + 1],
                    ));
                    state = .init;
                } else {
                    // nop
                }
            },
            .fileno => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else {
                    try tx.append(allocator, attach(.{
                        .fileno = try std.fmt.parseInt(usize, inp[start.offset + 1 .. i], 10),
                    }, start.loc, self.loc.back(), inp[start.offset..i]));
                    state = .init;
                    rewind = 1;
                }
            },
            .remark => |start| {
                if (c == '\r' or c == '\n') {
                    const span = inp[start.offset..i];
                    try tx.append(allocator, attach(.{
                        .remark = span,
                    }, start.loc, self.loc.back(), span));
                    state = .init;
                    rewind = 1;
                } else {
                    // nop
                }
            },
            .angleo => {
                if (c == '>') { // <>
                    try tx.append(allocator, attach(.diamond, self.loc.back(), self.loc, inp[i - 1 .. i + 1]));
                    state = .init;
                } else if (c == '=') { // <=
                    try tx.append(allocator, attach(.lte, self.loc.back(), self.loc, inp[i - 1 .. i + 1]));
                    state = .init;
                } else {
                    try tx.append(allocator, attach(.angleo, self.loc.back(), self.loc.back(), inp[i - 1 .. i]));
                    state = .init;
                    rewind = 1;
                }
            },
            .anglec => {
                if (c == '=') { // >=
                    try tx.append(allocator, attach(.gte, self.loc.back(), self.loc, inp[i - 1 .. i + 1]));
                    state = .init;
                } else {
                    try tx.append(allocator, attach(.anglec, self.loc.back(), self.loc.back(), inp[i - 1 .. i]));
                    state = .init;
                    rewind = 1;
                }
            },
        }
    }

    switch (state) {
        .init => {},
        .integer => |start| try tx.append(allocator, attach(
            try resolveIntegral(inp[start.offset..]),
            start.loc,
            self.loc.back(),
            inp[start.offset..],
        )),
        .minus => |start| try tx.append(allocator, attach(
            .minus,
            start.loc,
            start.loc,
            inp[inp.len - 1 ..],
        )),
        .floating => |start| try tx.append(allocator, attach(
            try resolveFloating(inp[start.offset..]),
            start.loc,
            self.loc.back(),
            inp[start.offset..],
        )),
        .floating_exponent => |fe| {
            switch (fe.state) {
                .init => {
                    if (fe.pointed)
                        // 1.2e$
                        try tx.append(allocator, attach(
                            try resolveFloating(inp[fe.start.offset .. inp.len - 1]),
                            fe.start.loc,
                            self.loc.back().back(),
                            inp[fe.start.offset .. inp.len - 1],
                        ))
                    else
                        // 1e$
                        try tx.append(allocator, attach(
                            try resolveIntegral(inp[fe.start.offset .. inp.len - 1]),
                            fe.start.loc,
                            self.loc.back().back(),
                            inp[fe.start.offset .. inp.len - 1],
                        ));
                    try tx.append(allocator, attach(
                        .{ .label = inp[inp.len - 1 ..] },
                        self.loc.back(),
                        self.loc.back(),
                        inp[inp.len - 1 ..],
                    ));
                },
                .sign => {
                    try tx.append(allocator, attach(
                        try self.resolveExponent(fe.double, inp[fe.start.offset..]),
                        fe.start.loc,
                        self.loc.back(),
                        inp[fe.start.offset..],
                    ));
                },
                .exp => {
                    try tx.append(allocator, attach(
                        try self.resolveExponent(fe.double, inp[fe.start.offset..]),
                        fe.start.loc,
                        self.loc.back(),
                        inp[fe.start.offset..],
                    ));
                },
            }
        },
        .bareword => |start| {
            if (std.ascii.eqlIgnoreCase(inp[start.offset..], "rem")) {
                try tx.append(allocator, attach(.{
                    .remark = inp[start.offset..],
                }, start.loc, self.loc.back(), inp[start.offset..]));
            } else {
                try tx.append(allocator, attach(
                    classifyBareword(inp[start.offset..]),
                    start.loc,
                    self.loc.back(),
                    inp[start.offset..],
                ));
            }
        },
        .string => return Error.UnexpectedEnd,
        .fileno => |start| try tx.append(allocator, attach(.{
            .fileno = try std.fmt.parseInt(usize, inp[start.offset + 1 ..], 10),
        }, start.loc, self.loc.back(), inp[start.offset..])),
        .remark => |start| try tx.append(allocator, attach(.{
            .remark = inp[start.offset..],
        }, start.loc, self.loc.back(), inp[start.offset..])),
        .angleo => try tx.append(allocator, attach(.angleo, self.loc.back(), self.loc.back(), inp[inp.len - 1 ..])),
        .anglec => try tx.append(allocator, attach(.anglec, self.loc.back(), self.loc.back(), inp[inp.len - 1 ..])),
    }

    return tx.toOwnedSlice(allocator);
}

fn attach(payload: Token.Payload, start: Loc, end: Loc, span: []const u8) Token {
    return .{
        .payload = payload,
        .range = .{ .start = start, .end = end },
        .span = span,
    };
}

fn resolveIntegral(s: []const u8) !Token.Payload {
    const n = try std.fmt.parseInt(isize, s, 10);
    if (n >= std.math.minInt(i16) and n <= std.math.maxInt(i16)) {
        return .{ .integer = @intCast(n) };
    } else if (n >= std.math.minInt(i32) and n <= std.math.maxInt(i32)) {
        return .{ .long = @intCast(n) };
    } else {
        return .{ .double = @floatFromInt(n) };
    }
}

fn resolveFloating(s: []const u8) !Token.Payload {
    // This is an ugly heuristic, but it approximates QBASIC's ...
    return if (s.len > 8)
        .{ .double = try std.fmt.parseFloat(f64, s) }
    else
        .{ .single = try std.fmt.parseFloat(f32, s) };
}

fn resolveExponent(self: *Tokenizer, double: bool, s: []const u8) !Token.Payload {
    std.debug.assert(s.len > 0);

    var s2 = std.ArrayListUnmanaged(u8){};
    defer s2.deinit(self.allocator);

    try s2.appendSlice(self.allocator, s);

    if (s2.items[s2.items.len - 1] == '+' or s2.items[s2.items.len - 1] == '-') {
        // QBASIC allows "5e+" or "12e-"; std.fmt.parseFloat does not.
        try s2.append(self.allocator, '0');
    }

    for (s2.items) |*c| {
        // QBASIC differentiates 1e5 (SINGLE) from 1d5 (DOUBLE).
        // std.fmt.parseFloat doesn't like 'd'.
        if (c.* == 'd')
            c.* = 'e'
        else if (c.* == 'D')
            c.* = 'E';
    }

    return if (double)
        .{ .double = try std.fmt.parseFloat(f64, s2.items) }
    else
        .{ .single = try std.fmt.parseFloat(f32, s2.items) };
}

fn classifyBareword(bw: []const u8) Token.Payload {
    inline for (std.meta.fields(@TypeOf(Token.BarewordTable))) |f| {
        if (std.ascii.eqlIgnoreCase(bw, @field(Token.BarewordTable, f.name)))
            return @field(Token.Payload, f.name);
    }
    return .{ .label = bw };
}

fn expectTokens(input: []const u8, expected: []const Token) !void {
    const tx = try tokenize(testing.allocator, input, null);
    defer testing.allocator.free(tx);

    try testing.expectEqualDeep(expected, tx);
}

test "tokenizes basics" {
    try expectTokens(
        \\if 10 Then END;
        \\  tere maailm%, ava$ = siin& 'okok
        \\Awawa: #7<<>>
        \\REM Hiii :3
        \\REM
    , &.{
        Token.init(.kw_if, Range.init(.{ 1, 1 }, .{ 1, 2 }), "if"),
        Token.init(.{ .integer = 10 }, Range.init(.{ 1, 4 }, .{ 1, 5 }), "10"),
        Token.init(.kw_then, Range.init(.{ 1, 7 }, .{ 1, 10 }), "Then"),
        Token.init(.kw_end, Range.init(.{ 1, 12 }, .{ 1, 14 }), "END"),
        Token.init(.semicolon, Range.init(.{ 1, 15 }, .{ 1, 15 }), ";"),
        Token.init(.linefeed, Range.init(.{ 1, 16 }, .{ 1, 16 }), "\n"),
        Token.init(.{ .label = "tere" }, Range.init(.{ 2, 3 }, .{ 2, 6 }), "tere"),
        Token.init(.{ .label = "maailm%" }, Range.init(.{ 2, 8 }, .{ 2, 14 }), "maailm%"),
        Token.init(.comma, Range.init(.{ 2, 15 }, .{ 2, 15 }), ","),
        Token.init(.{ .label = "ava$" }, Range.init(.{ 2, 17 }, .{ 2, 20 }), "ava$"),
        Token.init(.equals, Range.init(.{ 2, 22 }, .{ 2, 22 }), "="),
        Token.init(.{ .label = "siin&" }, Range.init(.{ 2, 24 }, .{ 2, 28 }), "siin&"),
        Token.init(.{ .remark = "'okok" }, Range.init(.{ 2, 30 }, .{ 2, 34 }), "'okok"),
        Token.init(.linefeed, Range.init(.{ 2, 35 }, .{ 2, 35 }), "\n"),
        Token.init(.{ .jumplabel = "Awawa:" }, Range.init(.{ 3, 1 }, .{ 3, 6 }), "Awawa:"),
        Token.init(.{ .fileno = 7 }, Range.init(.{ 3, 8 }, .{ 3, 9 }), "#7"),
        Token.init(.angleo, Range.init(.{ 3, 10 }, .{ 3, 10 }), "<"),
        Token.init(.diamond, Range.init(.{ 3, 11 }, .{ 3, 12 }), "<>"),
        Token.init(.anglec, Range.init(.{ 3, 13 }, .{ 3, 13 }), ">"),
        Token.init(.linefeed, Range.init(.{ 3, 14 }, .{ 3, 14 }), "\n"),
        Token.init(.{ .remark = "REM Hiii :3" }, Range.init(.{ 4, 1 }, .{ 4, 11 }), "REM Hiii :3"),
        Token.init(.linefeed, Range.init(.{ 4, 12 }, .{ 4, 12 }), "\n"),
        Token.init(.{ .remark = "REM" }, Range.init(.{ 5, 1 }, .{ 5, 3 }), "REM"),
    });
}

test "tokenizes strings" {
    // There is no escape.
    try expectTokens(
        \\"abc" "!"
    , &.{
        Token.init(.{ .string = "abc" }, Range.init(.{ 1, 1 }, .{ 1, 5 }), "\"abc\""),
        Token.init(.{ .string = "!" }, Range.init(.{ 1, 7 }, .{ 1, 9 }), "\"!\""),
    });
}

test "tokenizes SINGLEs" {
    try expectTokens(
        \\1. 2.2 3! 4.! 5.5! 1e10 2E-5 4.4e+8 5E+ 6e
    , &.{
        Token.init(.{ .single = 1.0 }, Range.init(.{ 1, 1 }, .{ 1, 2 }), "1."),
        Token.init(.{ .single = 2.2 }, Range.init(.{ 1, 4 }, .{ 1, 6 }), "2.2"),
        Token.init(.{ .single = 3.0 }, Range.init(.{ 1, 8 }, .{ 1, 9 }), "3!"),
        Token.init(.{ .single = 4.0 }, Range.init(.{ 1, 11 }, .{ 1, 13 }), "4.!"),
        Token.init(.{ .single = 5.5 }, Range.init(.{ 1, 15 }, .{ 1, 18 }), "5.5!"),
        Token.init(.{ .single = 1e10 }, Range.init(.{ 1, 20 }, .{ 1, 23 }), "1e10"),
        Token.init(.{ .single = 2e-5 }, Range.init(.{ 1, 25 }, .{ 1, 28 }), "2E-5"),
        Token.init(.{ .single = 4.4e+8 }, Range.init(.{ 1, 30 }, .{ 1, 35 }), "4.4e+8"),
        Token.init(.{ .single = 5E+0 }, Range.init(.{ 1, 37 }, .{ 1, 39 }), "5E+"),
        Token.init(.{ .integer = 6 }, Range.init(.{ 1, 41 }, .{ 1, 41 }), "6"),
        Token.init(.{ .label = "e" }, Range.init(.{ 1, 42 }, .{ 1, 42 }), "e"),
    });
}

test "tokenizes DOUBLEs" {
    try expectTokens(
        \\1.2345678 2# 2147483648 3.45# 1d10 2D-5 4.4d+8 5D+ 6d
    , &.{
        Token.init(.{ .double = 1.2345678 }, Range.init(.{ 1, 1 }, .{ 1, 9 }), "1.2345678"),
        Token.init(.{ .double = 2.0 }, Range.init(.{ 1, 11 }, .{ 1, 12 }), "2#"),
        Token.init(.{ .double = 2147483648.0 }, Range.init(.{ 1, 14 }, .{ 1, 23 }), "2147483648"),
        Token.init(.{ .double = 3.45 }, Range.init(.{ 1, 25 }, .{ 1, 29 }), "3.45#"),
        Token.init(.{ .double = 1e10 }, Range.init(.{ 1, 31 }, .{ 1, 34 }), "1d10"),
        Token.init(.{ .double = 2e-5 }, Range.init(.{ 1, 36 }, .{ 1, 39 }), "2D-5"),
        Token.init(.{ .double = 4.4e+8 }, Range.init(.{ 1, 41 }, .{ 1, 46 }), "4.4d+8"),
        Token.init(.{ .double = 5E+0 }, Range.init(.{ 1, 48 }, .{ 1, 50 }), "5D+"),
        Token.init(.{ .integer = 6 }, Range.init(.{ 1, 52 }, .{ 1, 52 }), "6"),
        Token.init(.{ .label = "d" }, Range.init(.{ 1, 53 }, .{ 1, 53 }), "d"),
    });
}

test "handles carriage returns" {
    // If you save a file from QBASIC for realsies ...
    try expectTokens("awa\r\nwa\n", &.{
        Token.init(.{ .label = "awa" }, Range.init(.{ 1, 1 }, .{ 1, 3 }), "awa"),
        Token.init(.linefeed, Range.init(.{ 1, 4 }, .{ 1, 5 }), "\r\n"),
        Token.init(.{ .label = "wa" }, Range.init(.{ 2, 1 }, .{ 2, 2 }), "wa"),
        Token.init(.linefeed, Range.init(.{ 2, 3 }, .{ 2, 3 }), "\n"),
    });
}

test "tokenizes leading negation" {
    try expectTokens("-1 --2", &.{
        Token.init(.{ .integer = -1 }, Range.init(.{ 1, 1 }, .{ 1, 2 }), "-1"),
        Token.init(.minus, Range.init(.{ 1, 4 }, .{ 1, 4 }), "-"),
        Token.init(.{ .integer = -2 }, Range.init(.{ 1, 5 }, .{ 1, 6 }), "-2"),
    });
}

test "tokenizes floats without integral part" {
    try expectTokens(".1 -.2", &.{
        Token.init(.{ .single = 0.1 }, Range.init(.{ 1, 1 }, .{ 1, 2 }), ".1"),
        Token.init(.{ .single = -0.2 }, Range.init(.{ 1, 4 }, .{ 1, 6 }), "-.2"),
    });
}
