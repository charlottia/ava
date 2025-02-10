const std = @import("std");
const Allocator = std.mem.Allocator;

const ty = @import("../ty.zig");
const Expr = @import("../ast/Expr.zig");

pub const Assembler = @import("./Assembler.zig");
pub const fmt = @import("./fmt.zig");

pub const Type = enum(u3) {
    INTEGER = 0b000,
    LONG = 0b001,
    SINGLE = 0b010,
    DOUBLE = 0b011,
    STRING = 0b100,

    pub fn fromTy(t: ty.Type) Type {
        return switch (t) {
            .integer => .INTEGER,
            .long => .LONG,
            .single => .SINGLE,
            .double => .DOUBLE,
            .string => .STRING,
        };
    }
};

pub const TypeCast = enum(u2) {
    INTEGER = 0b00,
    LONG = 0b01,
    SINGLE = 0b10,
    DOUBLE = 0b11,

    pub fn fromTy(t: ty.Type) TypeCast {
        return switch (t) {
            .integer => .INTEGER,
            .long => .LONG,
            .single => .SINGLE,
            .double => .DOUBLE,
            .string => unreachable,
        };
    }
};

pub const Op = enum(u4) {
    PUSH = 0b0001,
    CAST = 0b0010,
    LET = 0b0011,
    PRINT = 0b0100,
    PRINT_COMMA = 0b0101, // TODO: use space in rest of opcode for this
    PRINT_LINEFEED = 0b0110, // TODO: and this.
    ALU = 0b0111,
    JUMP = 0b1000,
    PRAGMA = 0b1110,
};

pub const AluOp = enum(u5) {
    ADD = 0b00000,
    MUL = 0b00001,
    FDIV = 0b00010,
    IDIV = 0b00011,
    SUB = 0b00100,
    // NEG = 0b00101, // XXX unimpl
    EQ = 0b00110,
    NEQ = 0b00111,
    LT = 0b01000,
    GT = 0b01001,
    LTE = 0b01010,
    GTE = 0b01011,
    AND = 0b01100,
    OR = 0b01101,
    XOR = 0b01110,
    MOD = 0b01111,

    pub fn fromExprOp(op: Expr.Op) AluOp {
        return switch (op) {
            .add => .ADD,
            .mul => .MUL,
            .fdiv => .FDIV,
            .idiv => .IDIV,
            .sub => .SUB,
            .eq => .EQ,
            .neq => .NEQ,
            .lt => .LT,
            .gt => .GT,
            .lte => .LTE,
            .gte => .GTE,
            .@"and" => .AND,
            .@"or" => .OR,
            .xor => .XOR,
            .mod => .MOD,
        };
    }
};

pub const InsnX = packed struct(u8) {
    op: Op,
    rest: u4 = 0,
};

pub const InsnT = packed struct(u8) {
    op: Op,
    t: Type,
    rest: u1 = 0,
};

pub const InsnTC = packed struct(u8) {
    op: Op,
    tf: TypeCast,
    tt: TypeCast,
};

pub const InsnAlu = packed struct(u16) {
    op: Op,
    t: Type,
    alu: AluOp,
    rest: u4 = 0,
};

pub const InsnC = packed struct(u8) {
    op: Op,
    cond: Cond,
};

const Cond = enum(u4) {
    UNCOND = 0b0000,
    FALSE = 0b0001,
};

pub const Opcode = struct {
    op: Op,
    t: ?Type = null,
    tc: ?struct { from: TypeCast, to: TypeCast } = null,
    alu: ?AluOp = null,
    slot: ?u8 = null,
    cond: ?Cond = null,
};

pub const Value = union(enum) {
    const Self = @This();

    integer: i16,
    long: i32,
    single: f32,
    double: f64,
    string: []const u8,

    pub fn @"type"(self: Self) ty.Type {
        return switch (self) {
            .integer => .integer,
            .long => .long,
            .single => .single,
            .double => .double,
            .string => .string,
        };
    }

    pub fn clone(self: Self, allocator: Allocator) !Self {
        return switch (self) {
            .integer, .long, .single, .double => self,
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
        };
    }
};

pub const Label = struct {
    id: []const u8,
};

pub const Target = union(enum) {
    label_id: []const u8,
    absolute: u16,
};

pub const Disassembly = struct {
    opcode: Opcode,
    value: ?Value,
    target: ?Target,
};

pub fn disasmAt(code: []const u8, i: *usize) Disassembly {
    const ix: InsnX = @bitCast(code[i.*]);
    const it: InsnT = @bitCast(code[i.*]);
    const itc: InsnTC = @bitCast(code[i.*]);
    const ic: InsnC = @bitCast(code[i.*]);
    i.* += 1;
    const op = ix.op;

    var opcode = Opcode{ .op = op };
    var value: ?Value = null;
    var target: ?Target = null;

    switch (op) {
        .PUSH => if (ix.rest == 0b1000) {
            i.* += 1;
            opcode.slot = code[i.*];
        } else {
            opcode.t = it.t;
            switch (it.t) {
                .INTEGER => {
                    value = .{ .integer = std.mem.readInt(i16, code[i.*..][0..2], .little) };
                    i.* += 2;
                },
                .LONG => {
                    value = .{ .long = std.mem.readInt(i32, code[i.*..][0..4], .little) };
                    i.* += 4;
                },
                .SINGLE => {
                    var r: [1]f32 = undefined;
                    @memcpy(std.mem.sliceAsBytes(r[0..]), code[i.*..][0..4]);
                    value = .{ .single = r[0] };
                    i.* += 4;
                },
                .DOUBLE => {
                    var r: [1]f64 = undefined;
                    @memcpy(std.mem.sliceAsBytes(r[0..]), code[i.*..][0..8]);
                    value = .{ .double = r[0] };
                    i.* += 8;
                },
                .STRING => {
                    const len = std.mem.readInt(u16, code[i.*..][0..2], .little);
                    i.* += 2;
                    value = .{ .string = code[i.*..][0..len] };
                    i.* += len;
                },
            }
        },
        .CAST => opcode.tc = .{ .from = itc.tf, .to = itc.tt },
        .LET => {
            opcode.slot = code[i.*];
            i.* += 1;
        },
        .PRINT => opcode.t = it.t,
        .PRINT_COMMA, .PRINT_LINEFEED => {},
        .ALU => {
            const ia: InsnAlu = @bitCast(code[i.* - 1 ..][0..2].*);
            i.* += 1;
            opcode.t = ia.t;
            opcode.alu = ia.alu;
        },
        .JUMP => {
            target = .{ .absolute = std.mem.readInt(u16, code[i.*..][0..2], .little) };
            i.* += 2;
            opcode.cond = ic.cond;
        },
        .PRAGMA => {
            const len = std.mem.readInt(u16, code[i.*..][0..2], .little);
            i.* += 2;
            value = .{ .string = code[i.*..][0..len] };
            i.* += len;
        },
    }

    return .{ .opcode = opcode, .value = value, .target = target };
}
