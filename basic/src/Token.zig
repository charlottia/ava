const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const loc = @import("loc.zig");
const Range = loc.Range;
const Tokenizer = @import("Tokenizer.zig");

const Token = @This();

payload: Payload,
range: Range,

pub fn init(payload: Payload, range: Range) Token {
    return .{ .payload = payload, .range = range };
}

pub fn format(self: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try std.fmt.format(writer, "{any} {any}", .{ self.range, self.payload });
}

// Any references belong to the input string.
pub const Payload = union(enum) {
    const Self = @This();

    integer: i16,
    long: i32,
    single: f32,
    double: f64,
    label: []const u8,
    remark: []const u8, // includes leading "REM " or "'"
    string: []const u8, // doesn't include surrounding quotes
    jumplabel: []const u8, // includes trailing ":"
    fileno: usize, // XXX: doesn't support variable
    linefeed,
    comma,
    semicolon,
    colon,
    equals,
    plus,
    minus,
    asterisk,
    fslash,
    bslash,
    pareno,
    parenc,
    angleo,
    anglec,
    diamond,
    lte,
    gte,
    kw_if,
    kw_then,
    kw_elseif,
    kw_else,
    kw_end,
    kw_goto,
    kw_for,
    kw_to,
    kw_step,
    kw_next,
    kw_dim,
    kw_as,
    kw_gosub,
    kw_return,
    kw_stop,
    kw_do,
    kw_loop,
    kw_while,
    kw_until,
    kw_wend,
    kw_let,
    kw_and,
    kw_or,
    kw_xor,
    kw_pragma,
    kw_mod,

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .integer => |n| try std.fmt.format(writer, "Integer({d})", .{n}),
            .long => |n| try std.fmt.format(writer, "Long({d})", .{n}),
            .single => |n| try std.fmt.format(writer, "Single({d})", .{n}),
            .double => |n| try std.fmt.format(writer, "Double({d})", .{n}),
            .label => |l| try std.fmt.format(writer, "Label({s})", .{l}),
            .remark => |r| try std.fmt.format(writer, "Remark({s})", .{r}),
            .string => |s| try std.fmt.format(writer, "String({s})", .{s}),
            .jumplabel => |jl| try std.fmt.format(writer, "Jumplabel({s})", .{jl}),
            .fileno => |n| try std.fmt.format(writer, "Fileno({d})", .{n}),
            .linefeed => try std.fmt.format(writer, "Linefeed", .{}),
            .comma => try std.fmt.format(writer, "Comma", .{}),
            .semicolon => try std.fmt.format(writer, "Semicolon", .{}),
            .colon => try std.fmt.format(writer, "Colon", .{}),
            .equals => try std.fmt.format(writer, "Equals", .{}),
            .plus => try std.fmt.format(writer, "Plus", .{}),
            .minus => try std.fmt.format(writer, "Minus", .{}),
            .asterisk => try std.fmt.format(writer, "Asterisk", .{}),
            .fslash => try std.fmt.format(writer, "Fslash", .{}),
            .bslash => try std.fmt.format(writer, "Bslash", .{}),
            .pareno => try std.fmt.format(writer, "Pareno", .{}),
            .parenc => try std.fmt.format(writer, "Parenc", .{}),
            .angleo => try std.fmt.format(writer, "Angleo", .{}),
            .anglec => try std.fmt.format(writer, "Anglec", .{}),
            .diamond => try std.fmt.format(writer, "Diamond", .{}),
            .lte => try std.fmt.format(writer, "Lte", .{}),
            .gte => try std.fmt.format(writer, "Gte", .{}),
            inline else => |_, tag| {
                inline for (std.meta.fields(@TypeOf(BarewordTable))) |f| {
                    if (comptime tag == @field(Self, f.name))
                        return try std.fmt.format(writer, "{s}", .{@field(BarewordTable, f.name)});
                }
                @compileError("nope");
            },
        }
    }
};

pub const BarewordTable = .{
    .kw_if = "IF",
    .kw_then = "THEN",
    .kw_elseif = "ELSEIF",
    .kw_else = "ELSE",
    .kw_end = "END",
    .kw_goto = "GOTO",
    .kw_for = "FOR",
    .kw_to = "TO",
    .kw_step = "STEP",
    .kw_next = "NEXT",
    .kw_dim = "DIM",
    .kw_as = "AS",
    .kw_gosub = "GOSUB",
    .kw_return = "RETURN",
    .kw_stop = "STOP",
    .kw_do = "DO",
    .kw_loop = "LOOP",
    .kw_while = "WHILE",
    .kw_until = "UNTIL",
    .kw_wend = "WEND",
    .kw_let = "LET",
    .kw_and = "AND",
    .kw_or = "OR",
    .kw_xor = "XOR",
    .kw_pragma = "PRAGMA",
    .kw_mod = "MOD",
};

pub const Tag = std.meta.Tag(Payload);

test "formatting" {
    const tx = try Tokenizer.tokenize(testing.allocator,
        \\'Hello!!!!
    , null);
    defer testing.allocator.free(tx);

    try testing.expectFmt("(1:1)-(1:10) Remark('Hello!!!!)", "{any}", .{tx[0]});
}
