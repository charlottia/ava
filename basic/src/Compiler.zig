const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const loc = @import("./loc.zig");
const Loc = loc.Loc;
const Stmt = @import("./ast/Stmt.zig");
const Expr = @import("./ast/Expr.zig");
const Parser = @import("./Parser.zig");
const isa = @import("./isa/root.zig");
const ErrorInfo = @import("./ErrorInfo.zig");
const ty = @import("./ty.zig");
const stack = @import("./stack.zig");

const Compiler = @This();

allocator: Allocator,
as: isa.Assembler,
errorinfo: ?*ErrorInfo,

deftypes: [26]ty.Type = [_]ty.Type{.single} ** 26,
slots: std.StringHashMapUnmanaged(u8) = .{}, // key is UPPERCASE with sigil
nextslot: u8 = 0,
csx: std.ArrayListUnmanaged(ControlStructure) = .{},

const Error = error{
    Unimplemented,
    TypeMismatch,
    Overflow,
    DuplicateLabel,
    MissingTarget,
    MissingEndIf,
    MissingWend,
    InvalidElse,
    InvalidEndIf,
    InvalidWend,
};

const ControlStructure = union(enum) {
    @"if": struct {
        index_t: usize,
        index_f: ?usize = null,
    },
    @"while": struct {
        start: usize,
        index_e: usize,
    },
};

pub fn compile(allocator: Allocator, sx: []const Stmt, errorinfo: ?*ErrorInfo) (Error || Parser.Error || Allocator.Error)![]const u8 {
    var compiler = init(allocator, errorinfo);
    defer compiler.deinit();

    return compiler.compileStmts(sx);
}

pub fn compileText(allocator: Allocator, inp: []const u8, errorinfo: ?*ErrorInfo) (Error || Parser.Error || Allocator.Error)![]const u8 {
    const sx = try Parser.parse(allocator, inp, errorinfo);
    defer Parser.free(allocator, sx);

    return compile(allocator, sx, errorinfo);
}

pub fn init(allocator: Allocator, errorinfo: ?*ErrorInfo) Compiler {
    return .{
        .allocator = allocator,
        .as = isa.Assembler.init(allocator, errorinfo),
        .errorinfo = errorinfo,
    };
}

pub fn deinit(self: *Compiler) void {
    self.csx.deinit(self.allocator);
    {
        var it = self.slots.keyIterator();
        while (it.next()) |k|
            self.allocator.free(k.*);
    }
    self.slots.deinit(self.allocator);
    self.as.deinit();
}

pub fn compileStmts(self: *Compiler, sx: []const Stmt) (Error || Allocator.Error)![]const u8 {
    for (sx) |s|
        try self.compileStmt(s);

    if (self.csx.items.len > 0)
        return switch (self.csx.items[self.csx.items.len - 1]) {
            .@"if" => Error.MissingEndIf,
            .@"while" => Error.MissingWend,
        };

    try self.as.link();

    return self.as.buffer.toOwnedSlice(self.allocator);
}

fn compileStmt(self: *Compiler, s: Stmt) (Error || Allocator.Error)!void {
    switch (s.payload) {
        .remark => {},
        .call => |c| {
            for (c.args) |a| {
                _ = try self.compileExpr(a.payload);
            }
            return ErrorInfo.ret(self, Error.Unimplemented, "call to \"{s}\"", .{c.name.payload});
        },
        .print => |p| {
            // Each argument gets PRINTed.
            // After each argument, a comma separator uses PRINT_COMMA to
            // advance the next print zone.
            // At the end, a PRINT_LINEFEED is issued if there was no separator after the last
            // argument.
            for (p.args, 0..) |a, i| {
                const t = try self.compileExpr(a.payload);
                try self.as.one(isa.Opcode{ .op = .PRINT, .t = isa.Type.fromTy(t) });
                if (i < p.separators.len) {
                    switch (p.separators[i].payload) {
                        ';' => {},
                        ',' => try self.as.one(isa.Opcode{ .op = .PRINT_COMMA }),
                        else => unreachable,
                    }
                }
            }
            if (p.separators.len < p.args.len)
                try self.as.one(isa.Opcode{ .op = .PRINT_LINEFEED });
        },
        .let => |l| {
            const resolved = try self.labelResolve(l.lhs.payload, .write);
            const rhs_ty = try self.compileExpr(l.rhs.payload);
            try self.compileCoerce(rhs_ty, resolved.type);
            try self.as.one(isa.Opcode{ .op = .LET, .slot = resolved.slot });
        },
        .@"if" => |i| {
            // XXX: do we want to coerce here? can be any number? string?
            _ = try self.compileExpr(i.cond.payload);
            try self.as.one(isa.Opcode{ .op = .JUMP, .cond = .FALSE });
            try self.csx.append(self.allocator, .{ .@"if" = .{ .index_t = self.as.buffer.items.len } });
            try self.as.one(isa.Target{ .absolute = 0xffff });
        },
        .@"else" => {
            if (self.csx.items.len == 0) return Error.InvalidElse;
            const cs = &self.csx.items[self.csx.items.len - 1];
            const i = switch (cs.*) {
                .@"if" => |*i| i,
                else => return Error.InvalidElse,
            };
            if (i.*.index_f != null) return Error.InvalidElse;

            try self.as.one(isa.Opcode{ .op = .JUMP, .cond = .UNCOND });
            i.*.index_f = self.as.buffer.items.len;
            try self.as.one(isa.Target{ .absolute = 0xffff });

            // XXX shares much with Assembler.link
            const dest = self.as.buffer.items[i.*.index_t..][0..2];
            std.debug.assert(std.mem.readInt(u16, dest, .little) == 0xffff);
            std.mem.writeInt(u16, dest, @intCast(self.as.buffer.items.len), .little);
        },
        .endif => {
            const cs = self.csx.popOrNull() orelse return Error.InvalidEndIf;
            const i = switch (cs) {
                .@"if" => |i| i,
                else => return Error.InvalidEndIf,
            };
            // XXX shares much with Assembler.link
            const dest = self.as.buffer.items[i.index_f orelse i.index_t ..][0..2];
            std.debug.assert(std.mem.readInt(u16, dest, .little) == 0xffff);
            std.mem.writeInt(u16, dest, @intCast(self.as.buffer.items.len), .little);
        },
        .if1 => |i| {
            _ = try self.compileExpr(i.cond.payload);

            const index = self.as.buffer.items.len;
            try self.compileStmt(i.stmt_t.*);
            const stmt_t_code = try self.allocator.dupe(u8, self.as.buffer.items[index..]);
            defer self.allocator.free(stmt_t_code);
            self.as.buffer.items.len = index;

            try self.as.one(isa.Opcode{ .op = .JUMP, .cond = .FALSE });
            try self.as.one(isa.Target{ .absolute = @intCast(index + stmt_t_code.len + 3) });
            try self.as.buffer.appendSlice(self.allocator, stmt_t_code);
        },
        .if2 => |i| {
            _ = try self.compileExpr(i.cond.payload);

            {
                const index = self.as.buffer.items.len;
                try self.compileStmt(i.stmt_t.*);
                const stmt_t_code = try self.allocator.dupe(u8, self.as.buffer.items[index..]);
                defer self.allocator.free(stmt_t_code);
                self.as.buffer.items.len = index;

                try self.as.one(isa.Opcode{ .op = .JUMP, .cond = .FALSE });
                try self.as.one(isa.Target{ .absolute = @intCast(index + stmt_t_code.len + 3 + 3) });
                try self.as.buffer.appendSlice(self.allocator, stmt_t_code);
            }
            {
                const index = self.as.buffer.items.len;
                try self.compileStmt(i.stmt_f.*);
                const stmt_f_code = try self.allocator.dupe(u8, self.as.buffer.items[index..]);
                defer self.allocator.free(stmt_f_code);
                self.as.buffer.items.len = index;

                try self.as.one(isa.Opcode{ .op = .JUMP, .cond = .UNCOND });
                try self.as.one(isa.Target{ .absolute = @intCast(index + stmt_f_code.len + 3) });
                try self.as.buffer.appendSlice(self.allocator, stmt_f_code);
            }
        },
        .@"while" => |w| {
            const start = self.as.buffer.items.len;
            _ = try self.compileExpr(w.cond.payload);
            try self.as.one(isa.Opcode{ .op = .JUMP, .cond = .FALSE });
            try self.csx.append(self.allocator, .{ .@"while" = .{ .start = start, .index_e = self.as.buffer.items.len } });
            try self.as.one(isa.Target{ .absolute = 0xffff });
        },
        .wend => {
            const cs = self.csx.popOrNull() orelse return Error.InvalidEndIf;
            const w = switch (cs) {
                .@"while" => |w| w,
                else => return Error.InvalidEndIf,
            };
            try self.as.one(isa.Opcode{ .op = .JUMP, .cond = .UNCOND });
            try self.as.one(isa.Target{ .absolute = @intCast(w.start) });
            // XXX shares much with Assembler.link
            const dest = self.as.buffer.items[w.index_e..][0..2];
            std.debug.assert(std.mem.readInt(u16, dest, .little) == 0xffff);
            std.mem.writeInt(u16, dest, @intCast(self.as.buffer.items.len), .little);
        },
        .lineno => |n| {
            const ns = try std.fmt.allocPrint(self.allocator, "{d}", .{n});
            defer self.allocator.free(ns);
            try self.as.one(isa.Label{ .id = ns });
        },
        .jumplabel => |l| {
            const lowered = try std.ascii.allocLowerString(self.allocator, l);
            defer self.allocator.free(lowered);
            try self.as.one(isa.Label{ .id = lowered });
        },
        .goto => |l| {
            try self.as.one(isa.Opcode{ .op = .JUMP, .cond = .UNCOND });
            try self.as.one(isa.Target{ .label_id = l.payload });
        },
        .pragma_printed => |p| {
            try self.as.one(isa.Opcode{ .op = .PRAGMA });
            try self.as.one(isa.Value{ .string = p.payload });
        },
        else => return ErrorInfo.ret(self, Error.Unimplemented, "unhandled stmt: {s}", .{@tagName(s.payload)}),
    }
}

fn compileExpr(self: *Compiler, e: Expr.Payload) (Allocator.Error || Error)!ty.Type {
    switch (e) {
        .imm_integer => |n| {
            try self.as.one(isa.Opcode{ .op = .PUSH, .t = .INTEGER });
            try self.as.one(isa.Value{ .integer = n });
            return .integer;
        },
        .imm_long => |n| {
            try self.as.one(isa.Opcode{ .op = .PUSH, .t = .LONG });
            try self.as.one(isa.Value{ .long = n });
            return .long;
        },
        .imm_single => |n| {
            try self.as.one(isa.Opcode{ .op = .PUSH, .t = .SINGLE });
            try self.as.one(isa.Value{ .single = n });
            return .single;
        },
        .imm_double => |n| {
            try self.as.one(isa.Opcode{ .op = .PUSH, .t = .DOUBLE });
            try self.as.one(isa.Value{ .double = n });
            return .double;
        },
        .imm_string => |s| {
            try self.as.one(isa.Opcode{ .op = .PUSH, .t = .STRING });
            try self.as.one(isa.Value{ .string = s });
            return .string;
        },
        .label => |l| {
            const resolved = try self.labelResolve(l, .read);
            if (resolved.slot) |slot| {
                try self.as.one(isa.Opcode{ .op = .PUSH, .slot = slot });
            } else {
                // autovivify
                _ = try self.compileExpr(Expr.Payload.zeroImm(resolved.type));
            }
            return resolved.type;
        },
        .binop => |b| {
            const tyx = try self.compileBinopOperands(b.lhs.payload, b.op.payload, b.rhs.payload);
            try self.as.one(isa.Opcode{
                .op = .ALU,
                .t = isa.Type.fromTy(tyx.widened),
                .alu = isa.AluOp.fromExprOp(b.op.payload),
            });

            return tyx.result;
        },
        .paren => |e2| return try self.compileExpr(e2.payload),
        // .negate => |e2| {
        //     const resultType = try self.compileExpr(e2.payload);
        //     switch (resultType) {
        //         .string => return ErrorInfo.ret(self, Error.TypeMismatch, "cannot negate a STRING", .{}),
        //         else => {},
        //     }
        //     const opc = isa.Opcode{
        //         .op = .ALU,
        //         .t = isa.Type.fromTy(resultType),
        //         .alu = .NEG,
        //     };
        //     try isa.assembleInto(self.writer, .{opc});
        //     return resultType;
        // },
        else => return ErrorInfo.ret(self, Error.Unimplemented, "unhandled Expr type in Compiler.push: {s}", .{@tagName(e)}),
    }
}

fn compileCoerce(self: *Compiler, from: ty.Type, to: ty.Type) !void {
    if (from == to) return;

    switch (from) {
        .integer, .long, .single, .double => switch (to) {
            .string => return self.cannotCoerce(from, to),
            else => {},
        },
        .string => return self.cannotCoerce(from, to),
    }

    try self.as.one(isa.Opcode{
        .op = .CAST,
        .tc = .{ .from = isa.TypeCast.fromTy(from), .to = isa.TypeCast.fromTy(to) },
    });
}

fn cannotCoerce(self: *const Compiler, from: ty.Type, to: ty.Type) (Error || Allocator.Error) {
    return ErrorInfo.ret(self, Error.TypeMismatch, "cannot coerce {any} to {any}", .{ from, to });
}

const BinopTypes = struct {
    widened: ty.Type,
    result: ty.Type,
};

fn compileBinopOperands(self: *Compiler, lhs: Expr.Payload, op: Expr.Op, rhs: Expr.Payload) !BinopTypes {
    const lhs_ty = try self.compileExpr(lhs);

    // Compile RHS to get type; snip off the generated code and append after we
    // do any necessary coercion. (It was either this or do stack swapsies in
    // the generated code.)
    //
    // XXX: Note that this is probably(?) robust to our linking mechanism
    // only because there are no jumps in expressions. Call expressions might
    // change this; if the jump target shifts position in the buffer after the
    // assembler records it in a Reloc, we're in trouble. :) In that case we're
    // probably better off just adding a SWAP op.
    const index = self.as.buffer.items.len;
    const rhs_ty = try self.compileExpr(rhs);
    const rhs_code = try self.allocator.dupe(u8, self.as.buffer.items[index..]);
    defer self.allocator.free(rhs_code);
    self.as.buffer.items.len = index;

    // Coerce both types to the wider of the two (if possible).
    const widened_ty = lhs_ty.widen(rhs_ty) orelse return self.cannotCoerce(rhs_ty, lhs_ty);
    try self.compileCoerce(lhs_ty, widened_ty);

    try self.as.buffer.appendSlice(self.allocator, rhs_code);
    try self.compileCoerce(rhs_ty, widened_ty);

    // Determine the type of the result of the operation, which might differ
    // from the input type (fdiv, idiv). The former is necessary for the
    // compilation to know what was placed on the stack; the latter is necessary
    // to determine which opcode to produce.
    const result_ty: ty.Type = switch (op) {
        .add => widened_ty,
        .mul => switch (widened_ty) {
            .string => return ErrorInfo.ret(self, Error.TypeMismatch, "cannot multiply a STRING", .{}),
            else => widened_ty,
        },
        .fdiv => switch (widened_ty) {
            .integer, .single => .single,
            .long, .double => .double,
            .string => return ErrorInfo.ret(self, Error.TypeMismatch, "cannot fdivide a STRING", .{}),
        },
        .sub => switch (widened_ty) {
            .string => return ErrorInfo.ret(self, Error.TypeMismatch, "cannot subtract a STRING", .{}),
            else => widened_ty,
        },
        .eq, .neq, .lt, .gt, .lte, .gte => .integer,
        .idiv, .@"and", .@"or", .xor, .mod => switch (widened_ty) {
            .integer => .integer,
            .long, .single, .double => .long,
            .string => return ErrorInfo.ret(self, Error.TypeMismatch, "cannot {s} a STRING", .{@tagName(widened_ty)}),
        },
        // else => return ErrorInfo.ret(self, Error.Unimplemented, "unknown result type of op {any}", .{op}),
    };

    return .{ .widened = widened_ty, .result = result_ty };
}

const Rw = enum { read, write };

fn ResolvedLabel(comptime rw: Rw) type {
    return if (rw == .read) struct {
        slot: ?u8 = null,
        type: ty.Type,
    } else struct {
        slot: u8,
        type: ty.Type,
    };
}

fn labelResolve(self: *Compiler, l: []const u8, comptime rw: Rw) !ResolvedLabel(rw) {
    std.debug.assert(l.len > 0);

    var key: []u8 = undefined;
    var typ: ty.Type = undefined;

    if (ty.Type.fromSigil(l[l.len - 1])) |t| {
        key = try self.allocator.alloc(u8, l.len);
        _ = std.ascii.upperString(key, l);

        typ = t;
    } else {
        key = try self.allocator.alloc(u8, l.len + 1);
        _ = std.ascii.upperString(key, l);

        std.debug.assert(key[0] >= 'A' and key[0] <= 'Z');
        typ = self.deftypes[key[0] - 'A'];
        key[l.len] = typ.sigil();
    }

    if (self.slots.getEntry(key)) |e| {
        self.allocator.free(key);
        return .{ .slot = e.value_ptr.*, .type = typ };
    } else if (rw == .read) {
        // autovivify
        self.allocator.free(key);
        return .{ .type = typ };
    } else {
        errdefer self.allocator.free(key);
        const slot = self.nextslot;
        self.nextslot += 1;
        try self.slots.putNoClobber(self.allocator, key, slot);
        return .{ .slot = slot, .type = typ };
    }
}

fn expectCompile(input: []const u8, assembly: anytype) !void {
    var errorinfo: ErrorInfo = .{};
    defer errorinfo.clear(testing.allocator);
    const code = Compiler.compileText(testing.allocator, input, &errorinfo) catch |err| {
        std.debug.print("err {any} in expectCompile at {any}\n", .{ err, errorinfo });
        return err;
    };
    defer testing.allocator.free(code);

    const exp = try isa.Assembler.assemble(testing.allocator, assembly);
    defer testing.allocator.free(exp);

    testing.expectEqualSlices(u8, exp, code) catch |err| {
        if (err == error.TestExpectedEqual) {
            const common = @import("./main/common.zig");
            common.handlesInitErr();
            try common.disasm(testing.allocator, exp, code);
            try common.handlesDeinit();
        }
        return err;
    };
}

test "compile shrimple" {
    try expectCompile(
        \\PRINT 123
        \\
    , .{
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 123 },
        isa.Opcode{ .op = .PRINT, .t = .INTEGER },
        isa.Opcode{ .op = .PRINT_LINEFEED },
    });
}

test "compile less shrimple" {
    try expectCompile(
        \\PRINT 6 + 5 * 4, 3; 2
        \\
    , .{
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 6 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 5 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 4 },
        isa.Opcode{ .op = .ALU, .alu = .MUL, .t = .INTEGER },
        isa.Opcode{ .op = .ALU, .alu = .ADD, .t = .INTEGER },
        isa.Opcode{ .op = .PRINT, .t = .INTEGER },
        isa.Opcode{ .op = .PRINT_COMMA },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 3 },
        isa.Opcode{ .op = .PRINT, .t = .INTEGER },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 2 },
        isa.Opcode{ .op = .PRINT, .t = .INTEGER },
        isa.Opcode{ .op = .PRINT_LINEFEED },
    });
}

test "compile variable access" {
    try expectCompile(
        \\a% = 12
        \\b% = 34
        \\c% = a% + b%
    , .{
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 12 },
        isa.Opcode{ .op = .LET, .slot = 0 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 34 },
        isa.Opcode{ .op = .LET, .slot = 1 },
        isa.Opcode{ .op = .PUSH, .slot = 0 },
        isa.Opcode{ .op = .PUSH, .slot = 1 },
        isa.Opcode{ .op = .ALU, .alu = .ADD, .t = .INTEGER },
        isa.Opcode{ .op = .LET, .slot = 2 },
    });
}

test "compile (parse) error" {
    var errorinfo: ErrorInfo = .{};
    const eu = compileText(testing.allocator, " -", &errorinfo);
    try testing.expectError(error.InvalidToken, eu);
    try testing.expectEqual(ErrorInfo{ .loc = Loc{ .row = 1, .col = 2 } }, errorinfo);
}

fn expectCompileErr(inp: []const u8, err: anyerror, msg: ?[]const u8) !void {
    var errorinfo: ErrorInfo = .{};
    defer errorinfo.clear(testing.allocator);
    const eu = compileText(testing.allocator, inp, &errorinfo);
    defer if (eu) |code| {
        testing.allocator.free(code);
    } else |_| {};
    try testing.expectError(err, eu);
    try testing.expectEqualDeep(msg, errorinfo.msg);
}

test "variable type mismatch" {
    try expectCompileErr(
        \\a="x"
    , Error.TypeMismatch, "cannot coerce STRING to SINGLE");
}

test "promotion and coercion" {
    try expectCompile(
        \\a% = 1 + 1.5 * 100000
    , .{
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .CAST, .tc = .{ .from = .INTEGER, .to = .SINGLE } },
        isa.Opcode{ .op = .PUSH, .t = .SINGLE },
        isa.Value{ .single = 1.5 },
        isa.Opcode{ .op = .PUSH, .t = .LONG },
        isa.Value{ .long = 100000 },
        isa.Opcode{ .op = .CAST, .tc = .{ .from = .LONG, .to = .SINGLE } },
        isa.Opcode{ .op = .ALU, .alu = .MUL, .t = .SINGLE },
        isa.Opcode{ .op = .ALU, .alu = .ADD, .t = .SINGLE },
        isa.Opcode{ .op = .CAST, .tc = .{ .from = .SINGLE, .to = .INTEGER } },
        isa.Opcode{ .op = .LET, .slot = 0 },
    });
}

test "autovivification" {
    try expectCompile(
        \\PRINT a%; a$
    , .{
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 0 },
        isa.Opcode{ .op = .PRINT, .t = .INTEGER },
        isa.Opcode{ .op = .PUSH, .t = .STRING },
        isa.Value{ .string = "" },
        isa.Opcode{ .op = .PRINT, .t = .STRING },
        isa.Opcode{ .op = .PRINT_LINEFEED },
    });
}

test "compiler and stack machine agree on binop expression types" {
    for (std.meta.tags(Expr.Op)) |op| {
        for (std.meta.tags(ty.Type)) |tyLhs| {
            for (std.meta.tags(ty.Type)) |tyRhs| {
                var c = Compiler.init(testing.allocator, null);
                defer c.deinit();

                const compiler_ty = c.compileExpr(.{ .binop = .{
                    .lhs = &Expr.init(Expr.Payload.oneImm(tyLhs), .{}),
                    .op = loc.WithRange(Expr.Op).init(op, .{}),
                    .rhs = &Expr.init(Expr.Payload.oneImm(tyRhs), .{}),
                } }) catch |err| switch (err) {
                    Error.TypeMismatch => continue, // keelatud eine
                    else => return err,
                };

                var m = stack.Machine(stack.TestEffects).init(
                    testing.allocator,
                    try stack.TestEffects.init(),
                    null,
                );
                defer m.deinit();

                const code = try c.as.buffer.toOwnedSlice(testing.allocator);
                defer testing.allocator.free(code);

                try m.run(code);

                try testing.expectEqual(1, m.stack.items.len);
                try testing.expectEqual(m.stack.items[0].type(), compiler_ty);
            }
        }
    }
}

test "goto" {
    try expectCompile(
        \\PRINT 1
        \\a: PRINT 2
        \\GOTO a
        \\77 GOTO 77
    , .{
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .PRINT, .t = .INTEGER },
        isa.Opcode{ .op = .PRINT_LINEFEED },
        isa.Label{ .id = "a" },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 2 },
        isa.Opcode{ .op = .PRINT, .t = .INTEGER },
        isa.Opcode{ .op = .PRINT_LINEFEED },
        isa.Opcode{ .op = .JUMP, .cond = .UNCOND },
        isa.Target{ .label_id = "a" },
        isa.Label{ .id = "77" },
        isa.Opcode{ .op = .JUMP, .cond = .UNCOND },
        isa.Target{ .label_id = "77" },
    });
}

test "duplicate linenos and jumplabels" {
    try expectCompileErr(
        \\10 PRINT "hi"
        \\20 PRINT "ok"
        \\20 GOTO 10
    , Error.DuplicateLabel, "duplicate jump label: 20");

    try expectCompileErr(
        \\   PRINT "hi"
        \\x: PRINT "ok"
        \\x: GOTO x
    , Error.DuplicateLabel, "duplicate jump label: x");
}

test "missing jump target" {
    try expectCompileErr(
        \\GOTO 10
    , Error.MissingTarget, "missing jump target: 10");
}

test "if1" {
    try expectCompile(
        \\PRINT "start"
        \\IF 1 = 2 THEN PRINT "impossible"
        \\PRINT "end"
        \\
    , .{
        isa.Opcode{ .op = .PUSH, .t = .STRING },
        isa.Value{ .string = "start" },
        isa.Opcode{ .op = .PRINT, .t = .STRING },
        isa.Opcode{ .op = .PRINT_LINEFEED },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 2 },
        isa.Opcode{ .op = .ALU, .alu = .EQ, .t = .INTEGER },
        isa.Opcode{ .op = .JUMP, .cond = .FALSE },
        isa.Target{ .label_id = "next" },
        isa.Opcode{ .op = .PUSH, .t = .STRING },
        isa.Value{ .string = "impossible" },
        isa.Opcode{ .op = .PRINT, .t = .STRING },
        isa.Opcode{ .op = .PRINT_LINEFEED },
        isa.Label{ .id = "next" },
        isa.Opcode{ .op = .PUSH, .t = .STRING },
        isa.Value{ .string = "end" },
        isa.Opcode{ .op = .PRINT, .t = .STRING },
        isa.Opcode{ .op = .PRINT_LINEFEED },
    });
}

test "if2" {
    try expectCompile(
        \\IF 1 = 2 THEN PRINT "false" ELSE PRINT "true"
    , .{
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 2 },
        isa.Opcode{ .op = .ALU, .alu = .EQ, .t = .INTEGER },
        isa.Opcode{ .op = .JUMP, .cond = .FALSE },
        isa.Target{ .label_id = "else" },
        isa.Opcode{ .op = .PUSH, .t = .STRING },
        isa.Value{ .string = "false" },
        isa.Opcode{ .op = .PRINT, .t = .STRING },
        isa.Opcode{ .op = .PRINT_LINEFEED },
        isa.Opcode{ .op = .JUMP, .cond = .UNCOND },
        isa.Target{ .label_id = "end" },
        isa.Label{ .id = "else" },
        isa.Opcode{ .op = .PUSH, .t = .STRING },
        isa.Value{ .string = "true" },
        isa.Opcode{ .op = .PRINT, .t = .STRING },
        isa.Opcode{ .op = .PRINT_LINEFEED },
        isa.Label{ .id = "end" },
    });
}

const fal_se = .{
    isa.Opcode{ .op = .PUSH, .t = .STRING },
    isa.Value{ .string = "fal" },
    isa.Opcode{ .op = .PRINT, .t = .STRING },
    isa.Opcode{ .op = .PUSH, .t = .STRING },
    isa.Value{ .string = "se" },
    isa.Opcode{ .op = .PRINT, .t = .STRING },
    isa.Opcode{ .op = .PRINT_LINEFEED },
};

const tr_ue = .{
    isa.Opcode{ .op = .PUSH, .t = .STRING },
    isa.Value{ .string = "tr" },
    isa.Opcode{ .op = .PRINT, .t = .STRING },
    isa.Opcode{ .op = .PUSH, .t = .STRING },
    isa.Value{ .string = "ue" },
    isa.Opcode{ .op = .PRINT, .t = .STRING },
    isa.Opcode{ .op = .PRINT_LINEFEED },
};

test "if" {
    try expectCompile(
        \\IF 1 = 2 THEN
        \\    PRINT "fal";
        \\    PRINT "se"
        \\ENDIF
        \\
        \\IF 1 = 1 THEN
        \\    PRINT "tr";
        \\    PRINT "ue"
        \\END IF
    , .{
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 2 },
        isa.Opcode{ .op = .ALU, .alu = .EQ, .t = .INTEGER },
        isa.Opcode{ .op = .JUMP, .cond = .FALSE },
        isa.Target{ .label_id = "second" },
    } ++ fal_se ++ .{
        isa.Label{ .id = "second" },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .ALU, .alu = .EQ, .t = .INTEGER },
        isa.Opcode{ .op = .JUMP, .cond = .FALSE },
        isa.Target{ .label_id = "end" },
    } ++ tr_ue ++ .{
        isa.Label{ .id = "end" },
    });

    try expectCompile(
        \\IF 1 = 2 THEN
        \\    PRINT "fal";
        \\    PRINT "se"
        \\ELSE
        \\    PRINT "tr";
        \\    PRINT "ue"
        \\END IF
    , .{
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 2 },
        isa.Opcode{ .op = .ALU, .alu = .EQ, .t = .INTEGER },
        isa.Opcode{ .op = .JUMP, .cond = .FALSE },
        isa.Target{ .label_id = "else" },
    } ++ fal_se ++ .{
        isa.Opcode{ .op = .JUMP, .cond = .UNCOND },
        isa.Target{ .label_id = "end" },
        isa.Label{ .id = "else" },
    } ++ tr_ue ++ .{
        isa.Label{ .id = "end" },
    });
}

test "nested if" {
    try expectCompile(
        \\IF 1 = 1 THEN
        \\    IF 1 = 2 THEN
        \\        IF 1 = 3 THEN
        \\            PRINT "fal";
        \\            PRINT "se"
        \\        END IF
        \\    END IF
        \\END IF
        \\
    , .{
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .ALU, .alu = .EQ, .t = .INTEGER },
        isa.Opcode{ .op = .JUMP, .cond = .FALSE },
        isa.Target{ .label_id = "end" },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 2 },
        isa.Opcode{ .op = .ALU, .alu = .EQ, .t = .INTEGER },
        isa.Opcode{ .op = .JUMP, .cond = .FALSE },
        isa.Target{ .label_id = "end" },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 3 },
        isa.Opcode{ .op = .ALU, .alu = .EQ, .t = .INTEGER },
        isa.Opcode{ .op = .JUMP, .cond = .FALSE },
        isa.Target{ .label_id = "end" },
    } ++ fal_se ++ .{
        isa.Label{ .id = "end" },
    });
}

test "while" {
    try expectCompile(
        \\i% = 0
        \\WHILE i% <> 2
        \\  i% = i% + 1
        \\WEND
    , .{
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 0 },
        isa.Opcode{ .op = .LET, .slot = 0 },
        isa.Label{ .id = "cond" },
        isa.Opcode{ .op = .PUSH, .slot = 0 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 2 },
        isa.Opcode{ .op = .ALU, .alu = .NEQ, .t = .INTEGER },
        isa.Opcode{ .op = .JUMP, .cond = .FALSE },
        isa.Target{ .label_id = "end" },
        isa.Opcode{ .op = .PUSH, .slot = 0 },
        isa.Opcode{ .op = .PUSH, .t = .INTEGER },
        isa.Value{ .integer = 1 },
        isa.Opcode{ .op = .ALU, .alu = .ADD, .t = .INTEGER },
        isa.Opcode{ .op = .LET, .slot = 0 },
        isa.Opcode{ .op = .JUMP, .cond = .UNCOND },
        isa.Target{ .label_id = "cond" },
        isa.Label{ .id = "end" },
    });
}
