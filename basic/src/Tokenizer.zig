const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Token = @import("Token.zig");
const loc = @import("loc.zig");
const Range = loc.Range;

const Tokenizer = @This();

loc: loc.Loc = .{ .row = 1, .col = 1 },

pub const Error = error{
    UnexpectedChar,
    UnexpectedEnd,
};

const LocOffset = struct {
    loc: loc.Loc,
    offset: usize,
};

const State = union(enum) {
    init,
    number: LocOffset,
    bareword: LocOffset,
    string: LocOffset,
    fileno: LocOffset,
    remark: LocOffset,
    angleo,
    anglec,
};

pub fn tokenize(allocator: Allocator, inp: []const u8, errorloc: ?*loc.Loc) ![]Token {
    var t = Tokenizer{};
    return t.feed(allocator, inp) catch |err| {
        if (errorloc) |el|
            el.* = t.loc;
        return err;
    };
}

fn feed(self: *Tokenizer, allocator: Allocator, inp: []const u8) ![]Token {
    var tx = std.ArrayList(Token).init(allocator);
    errdefer tx.deinit();

    var state: State = .init;
    var i: usize = 0;
    var rewind = false;
    while (i < inp.len) : ({
        if (rewind) {
            rewind = false;
        } else {
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
        }
    }) {
        const c = inp[i];

        switch (state) {
            .init => {
                if (c >= '0' and c <= '9') {
                    state = .{ .number = .{ .loc = self.loc, .offset = i } };
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    state = .{ .bareword = .{ .loc = self.loc, .offset = i } };
                } else if (c == '"') {
                    state = .{ .string = .{ .loc = self.loc, .offset = i + 1 } };
                } else if (c == ' ') {
                    // nop
                } else if (c == '\t') {
                    // nop
                } else if (c == '\n') {
                    try tx.append(attach(.linefeed, self.loc, self.loc));
                } else if (c == '\'') {
                    state = .{ .remark = .{ .loc = self.loc, .offset = i } };
                } else if (c == ',') {
                    try tx.append(attach(.comma, self.loc, self.loc));
                } else if (c == ';') {
                    try tx.append(attach(.semicolon, self.loc, self.loc));
                } else if (c == ':') {
                    try tx.append(attach(.colon, self.loc, self.loc));
                } else if (c == '=') {
                    try tx.append(attach(.equals, self.loc, self.loc));
                } else if (c == '+') {
                    try tx.append(attach(.plus, self.loc, self.loc));
                } else if (c == '-') {
                    try tx.append(attach(.minus, self.loc, self.loc));
                } else if (c == '*') {
                    try tx.append(attach(.asterisk, self.loc, self.loc));
                } else if (c == '/') {
                    try tx.append(attach(.fslash, self.loc, self.loc));
                } else if (c == '(') {
                    try tx.append(attach(.pareno, self.loc, self.loc));
                } else if (c == ')') {
                    try tx.append(attach(.parenc, self.loc, self.loc));
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
            .number => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    return Error.UnexpectedChar;
                } else {
                    try tx.append(attach(.{
                        .number = try std.fmt.parseInt(isize, inp[start.offset..i], 10),
                    }, start.loc, self.loc.back()));
                    state = .init;
                    rewind = true;
                }
            },
            .bareword => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    // nop
                } else if (c == '$' or c == '%' or c == '&') {
                    try tx.append(attach(.{ .label = inp[start.offset .. i + 1] }, start.loc, self.loc));
                    state = .init;
                } else if (c == ':') {
                    try tx.append(attach(.{ .jumplabel = inp[start.offset .. i + 1] }, start.loc, self.loc));
                    state = .init;
                } else if (std.ascii.eqlIgnoreCase(inp[start.offset..i], "rem")) {
                    state = .{ .remark = start };
                } else {
                    try tx.append(attach(classifyBareword(inp[start.offset..i]), start.loc, self.loc.back()));
                    state = .init;
                    rewind = true;
                }
            },
            .string => |start| {
                if (c == '"') {
                    try tx.append(attach(.{ .string = inp[start.offset..i] }, start.loc, self.loc));
                    state = .init;
                } else {
                    // nop
                }
            },
            .fileno => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else {
                    try tx.append(attach(.{
                        .fileno = try std.fmt.parseInt(usize, inp[start.offset + 1 .. i], 10),
                    }, start.loc, self.loc.back()));
                    state = .init;
                    rewind = true;
                }
            },
            .remark => |start| {
                if (c == '\n') {
                    try tx.append(attach(.{
                        .remark = inp[start.offset..i],
                    }, start.loc, self.loc.back()));
                    state = .init;
                    rewind = true;
                } else {
                    // nop
                }
            },
            .angleo => {
                if (c == '>') { // <>
                    try tx.append(attach(.diamond, self.loc.back(), self.loc));
                    state = .init;
                } else if (c == '=') { // <=
                    try tx.append(attach(.lte, self.loc.back(), self.loc));
                    state = .init;
                } else {
                    try tx.append(attach(.angleo, self.loc.back(), self.loc.back()));
                    state = .init;
                    rewind = true;
                }
            },
            .anglec => {
                if (c == '=') { // >=
                    try tx.append(attach(.gte, self.loc.back(), self.loc));
                    state = .init;
                } else {
                    try tx.append(attach(.anglec, self.loc.back(), self.loc.back()));
                    state = .init;
                    rewind = true;
                }
            },
        }
    }

    switch (state) {
        .init => {},
        .number => |start| try tx.append(attach(.{
            .number = try std.fmt.parseInt(isize, inp[start.offset..], 10),
        }, start.loc, self.loc.back())),
        .bareword => |start| {
            if (std.ascii.eqlIgnoreCase(inp[start.offset..], "rem")) {
                try tx.append(attach(.{
                    .remark = inp[start.offset..],
                }, start.loc, self.loc.back()));
            } else {
                try tx.append(attach(classifyBareword(inp[start.offset..]), start.loc, self.loc.back()));
            }
        },
        .string => return Error.UnexpectedEnd,
        .fileno => |start| try tx.append(attach(.{
            .fileno = try std.fmt.parseInt(usize, inp[start.offset + 1 ..], 10),
        }, start.loc, self.loc.back())),
        .remark => |start| try tx.append(attach(.{
            .remark = inp[start.offset..],
        }, start.loc, self.loc.back())),
        .angleo => try tx.append(attach(.angleo, self.loc.back(), self.loc.back())),
        .anglec => try tx.append(attach(.anglec, self.loc.back(), self.loc.back())),
    }

    return tx.toOwnedSlice();
}

fn attach(payload: Token.Payload, start: loc.Loc, end: loc.Loc) Token {
    return .{
        .payload = payload,
        .range = .{
            .start = start,
            .end = end,
        },
    };
}

// TODO: replace with table (same with other direction above).
fn classifyBareword(bw: []const u8) Token.Payload {
    if (std.ascii.eqlIgnoreCase(bw, "if")) {
        return .kw_if;
    } else if (std.ascii.eqlIgnoreCase(bw, "then")) {
        return .kw_then;
    } else if (std.ascii.eqlIgnoreCase(bw, "elseif")) {
        return .kw_elseif;
    } else if (std.ascii.eqlIgnoreCase(bw, "else")) {
        return .kw_else;
    } else if (std.ascii.eqlIgnoreCase(bw, "end")) {
        return .kw_end;
    } else if (std.ascii.eqlIgnoreCase(bw, "goto")) {
        return .kw_goto;
    } else if (std.ascii.eqlIgnoreCase(bw, "for")) {
        return .kw_for;
    } else if (std.ascii.eqlIgnoreCase(bw, "to")) {
        return .kw_to;
    } else if (std.ascii.eqlIgnoreCase(bw, "step")) {
        return .kw_step;
    } else if (std.ascii.eqlIgnoreCase(bw, "next")) {
        return .kw_next;
    } else if (std.ascii.eqlIgnoreCase(bw, "dim")) {
        return .kw_dim;
    } else if (std.ascii.eqlIgnoreCase(bw, "as")) {
        return .kw_as;
    } else if (std.ascii.eqlIgnoreCase(bw, "gosub")) {
        return .kw_gosub;
    } else if (std.ascii.eqlIgnoreCase(bw, "return")) {
        return .kw_return;
    } else if (std.ascii.eqlIgnoreCase(bw, "stop")) {
        return .kw_stop;
    } else if (std.ascii.eqlIgnoreCase(bw, "do")) {
        return .kw_do;
    } else if (std.ascii.eqlIgnoreCase(bw, "loop")) {
        return .kw_loop;
    } else if (std.ascii.eqlIgnoreCase(bw, "while")) {
        return .kw_while;
    } else if (std.ascii.eqlIgnoreCase(bw, "until")) {
        return .kw_until;
    } else if (std.ascii.eqlIgnoreCase(bw, "wend")) {
        return .kw_wend;
    } else if (std.ascii.eqlIgnoreCase(bw, "let")) {
        return .kw_let;
    } else if (std.ascii.eqlIgnoreCase(bw, "and")) {
        return .kw_and;
    } else if (std.ascii.eqlIgnoreCase(bw, "or")) {
        return .kw_or;
    } else if (std.ascii.eqlIgnoreCase(bw, "xor")) {
        return .kw_xor;
    } else {
        return .{ .label = bw };
    }
}

test "tokenizes basics" {
    const tx = try tokenize(testing.allocator,
        \\if 10 Then END;
        \\  tere maailm%, ava$ = siin& 'okok
        \\Awawa: #7<<>>
        \\REM Hiii :3
        \\REM
    , null);
    defer testing.allocator.free(tx);

    try testing.expectEqualDeep(&[_]Token{
        Token.init(.kw_if, Range.init(.{ 1, 1 }, .{ 1, 2 })),
        Token.init(.{ .number = 10 }, Range.init(.{ 1, 4 }, .{ 1, 5 })),
        Token.init(.kw_then, Range.init(.{ 1, 7 }, .{ 1, 10 })),
        Token.init(.kw_end, Range.init(.{ 1, 12 }, .{ 1, 14 })),
        Token.init(.semicolon, Range.init(.{ 1, 15 }, .{ 1, 15 })),
        Token.init(.linefeed, Range.init(.{ 1, 16 }, .{ 1, 16 })),
        Token.init(.{ .label = "tere" }, Range.init(.{ 2, 3 }, .{ 2, 6 })),
        Token.init(.{ .label = "maailm%" }, Range.init(.{ 2, 8 }, .{ 2, 14 })),
        Token.init(.comma, Range.init(.{ 2, 15 }, .{ 2, 15 })),
        Token.init(.{ .label = "ava$" }, Range.init(.{ 2, 17 }, .{ 2, 20 })),
        Token.init(.equals, Range.init(.{ 2, 22 }, .{ 2, 22 })),
        Token.init(.{ .label = "siin&" }, Range.init(.{ 2, 24 }, .{ 2, 28 })),
        Token.init(.{ .remark = "'okok" }, Range.init(.{ 2, 30 }, .{ 2, 34 })),
        Token.init(.linefeed, Range.init(.{ 2, 35 }, .{ 2, 35 })),
        Token.init(.{ .jumplabel = "Awawa:" }, Range.init(.{ 3, 1 }, .{ 3, 6 })),
        Token.init(.{ .fileno = 7 }, Range.init(.{ 3, 8 }, .{ 3, 9 })),
        Token.init(.angleo, Range.init(.{ 3, 10 }, .{ 3, 10 })),
        Token.init(.diamond, Range.init(.{ 3, 11 }, .{ 3, 12 })),
        Token.init(.anglec, Range.init(.{ 3, 13 }, .{ 3, 13 })),
        Token.init(.linefeed, Range.init(.{ 3, 14 }, .{ 3, 14 })),
        Token.init(.{ .remark = "REM Hiii :3" }, Range.init(.{ 4, 1 }, .{ 4, 11 })),
        Token.init(.linefeed, Range.init(.{ 4, 12 }, .{ 4, 12 })),
        Token.init(.{ .remark = "REM" }, Range.init(.{ 5, 1 }, .{ 5, 3 })),
    }, tx);
}

test "tokenizes strings" {
    // There is no escape.
    const tx = try tokenize(testing.allocator,
        \\"abc" "!"
    , null);
    defer testing.allocator.free(tx);

    try testing.expectEqualDeep(&[_]Token{
        Token.init(.{ .string = "abc" }, Range.init(.{ 1, 1 }, .{ 1, 5 })),
        Token.init(.{ .string = "!" }, Range.init(.{ 1, 7 }, .{ 1, 9 })),
    }, tx);
}