const std = @import("std");
const Allocator = std.mem.Allocator;

const isa = @import("../isa/root.zig");
const PrintLoc = @import("../PrintLoc.zig");
const ErrorInfo = @import("../ErrorInfo.zig");
const opts = @import("./opts.zig");

const HandleRead = struct {
    const Self = @This();

    file: std.fs.File,
    br: std.io.BufferedReader(4096, std.fs.File.Reader),
    rd: std.io.BufferedReader(4096, std.fs.File.Reader).Reader,

    fn init(self: *Self, file: std.fs.File) void {
        self.file = file;
        self.br = std.io.bufferedReader(file.reader());
        self.rd = self.br.reader();
    }
};

const HandleWrite = struct {
    const Self = @This();

    file: std.fs.File,
    bw: std.io.BufferedWriter(4096, std.fs.File.Writer),
    wr: std.io.BufferedWriter(4096, std.fs.File.Writer).Writer,
    tc: std.io.tty.Config,

    fn init(self: *Self, file: std.fs.File) void {
        self.file = file;
        self.bw = std.io.bufferedWriter(file.writer());
        self.wr = self.bw.writer();
        self.tc = std.io.tty.detectConfig(file);
    }
};

pub var stdin: HandleRead = undefined;
pub var stdout: *HandleWrite = undefined;
pub var stderr: *HandleWrite = undefined;

var _stdout: HandleWrite = undefined;
var _stderr: HandleWrite = undefined;

pub fn handlesInit() void {
    stdin.init(std.io.getStdIn());
    stdout = &_stdout;
    stdout.init(std.io.getStdOut());
    stderr = &_stderr;
    stderr.init(std.io.getStdErr());
}

pub fn handlesInitErr() void {
    stdin.init(std.io.getStdIn());
    stderr = &_stderr;
    stderr.init(std.io.getStdErr());
    stdout = stderr;
}

pub fn handlesDeinit() !void {
    try stderr.bw.flush();
    try stdout.bw.flush();
}

const help_text =
    \\
    \\Global options:
    \\
    \\  -h, --help     Show command-specific usage
    \\
;

pub fn usageFor(status: u8, comptime command: []const u8, comptime argsPart: []const u8, comptime body: []const u8) noreturn {
    std.debug.print(
    //    12345678901234567890123456789012345678901234567890123456789012345678901234567890
        \\Usage: {?s} 
    ++ command ++ (if (argsPart.len > 0) " " else "") ++ argsPart ++ "\n\n" ++
        body ++ help_text, .{opts.global.executable_name});
    std.process.exit(status);
}

pub const RunMode = enum { bas, avc };

pub fn runModeFromFilename(filename: []const u8) ?RunMode {
    return if (std.ascii.endsWithIgnoreCase(filename, ".bas"))
        .bas
    else if (std.ascii.endsWithIgnoreCase(filename, ".avc"))
        .avc
    else
        null;
}

pub const Output = enum { stdout, stderr };
pub const LocKind = enum { caret, loc };

pub fn handleError(comptime what: []const u8, err: anyerror, errorinfo: ErrorInfo, output: Output, lockind: LocKind) !void {
    const bundle = switch (output) {
        .stdout => stdout,
        .stderr => stderr,
    };

    try bundle.tc.setColor(bundle.wr, .bright_red);

    if (errorinfo.loc) |errloc| {
        switch (lockind) {
            .caret => {
                try bundle.wr.writeByteNTimes(' ', errloc.col + 1);
                try bundle.wr.writeAll("^-- ");
            },
            .loc => try std.fmt.format(bundle.wr, "({d}:{d}) ", .{ errloc.row, errloc.col }),
        }
    }
    if (errorinfo.msg) |m| {
        try bundle.wr.writeAll(m);
        try bundle.wr.writeByte('\n');
    } else {
        try bundle.wr.writeAll("(no info)\n");
    }

    try std.fmt.format(bundle.wr, what ++ ": {s}\n\n", .{@errorName(err)});
    try bundle.tc.setColor(bundle.wr, .reset);
    try bundle.bw.flush();
}

pub fn xxd(allocator: Allocator, code: []const u8) !void {
    const coloured = try colourify(allocator, code);
    defer allocator.free(coloured);

    var i: usize = 0;
    while (i < code.len) : (i += 16) {
        try stdout.tc.setColor(stdout.wr, .white);
        try std.fmt.format(stdout.wr, "{x:0>4}:", .{i});
        const c = @min(coloured.len - i, 16);
        for (0..c) |j| {
            const cch = coloured[i + j];
            if (j % 2 == 0)
                try stdout.wr.writeByte(' ');
            if (j == 0 or coloured[i + j - 1].colour != cch.colour)
                try stdout.tc.setColor(stdout.wr, cch.colour);
            try std.fmt.format(stdout.wr, "{x:0>2}", .{cch.ch});
        }

        for (c..16) |j| {
            if (j % 2 == 0)
                try stdout.wr.writeByte(' ');
            try stdout.wr.writeAll("  ");
        }

        try stdout.wr.writeAll("  ");
        for (0..c) |j| {
            const cch = coloured[i + j];
            if (j == 0 or coloured[i + j - 1].colour != cch.colour)
                try stdout.tc.setColor(stdout.wr, cch.colour);
            if (cch.ch < 32 or cch.ch > 126)
                try stdout.wr.writeByte('.')
            else
                try stdout.wr.writeByte(cch.ch);
        }

        try stdout.wr.writeByte('\n');
    }

    try stdout.tc.setColor(stdout.wr, .reset);
    try stdout.bw.flush();
}

const ColouredCh = struct { colour: std.io.tty.Color, ch: u8 };

fn colourify(allocator: Allocator, code: []const u8) ![]ColouredCh {
    const result = try allocator.alloc(ColouredCh, code.len);

    var i: usize = 0;
    while (i < code.len) {
        const da = isa.disasmAt(code, i);
        for (i..da.i) |j|
            result[j].colour = .reset;

        // ALU is two byte insn, rest are 1.
        result[i].colour = .bright_green;
        if (da.opcode.op == .ALU)
            result[i + 1].colour = .bright_cyan
        else if (da.opcode.op == .LET or (da.opcode.op == .PUSH and da.opcode.t == null))
            result[i + 1].colour = .bright_blue
        else if ((da.opcode.op == .PUSH and da.opcode.@"var" == null and da.opcode.t.? == .STRING) or
            da.opcode.op == .PRAGMA)
        {
            result[i + 1].colour = .bright_blue;
            result[i + 2].colour = .bright_blue;
            for (i + 3..da.i) |j|
                result[j].colour = .bright_yellow;
        }

        for (i..da.i) |j|
            result[j].ch = code[j];

        i = da.i;
    }

    return result;
}

pub fn disasm(allocator: Allocator, code_l: []const u8, code_ri: ?[]const u8) !void {
    const code_r = code_ri orelse "";

    const diff_mode = code_ri != null and !std.mem.eql(u8, code_l, code_r);

    if (diff_mode) {
        try stdout.tc.setColor(stdout.wr, .bright_red);
        try stdout.wr.writeAll("-expected\n");
        try stdout.tc.setColor(stdout.wr, .bright_green);
        try stdout.wr.writeAll("+actual\n");
        try stdout.tc.setColor(stdout.wr, .reset);
    }

    var i_l: usize = 0;
    var i_r: usize = 0;
    while (i_l < code_l.len or i_r < code_r.len) {
        const si_l = i_l;
        const si_r = i_r;

        var buffer_l = std.ArrayListUnmanaged(u8){};
        defer buffer_l.deinit(allocator);
        if (i_l < code_l.len)
            i_l = try disasmAt(buffer_l.writer(allocator), code_l, i_l);

        var buffer_r = std.ArrayListUnmanaged(u8){};
        defer buffer_r.deinit(allocator);
        if (i_r < code_r.len)
            i_r = try disasmAt(buffer_r.writer(allocator), code_r, i_r);

        const mismatch = diff_mode and
            (si_l != si_r or !std.mem.eql(u8, buffer_l.items, buffer_r.items));

        if (!(mismatch and si_l >= code_l.len)) {
            try stdout.tc.setColor(stdout.wr, .white);
            if (mismatch) {
                try stdout.tc.setColor(stdout.wr, .bright_red);
                try stdout.wr.writeByte('-');
            } else if (diff_mode)
                try stdout.wr.writeByte(' ');
            try std.fmt.format(stdout.wr, "{x:0>4}: ", .{si_l});
            try stdout.wr.writeAll(buffer_l.items);
            try stdout.wr.writeByte('\n');
        }

        if (mismatch and si_r < code_r.len) {
            try stdout.tc.setColor(stdout.wr, .bright_green);
            try std.fmt.format(stdout.wr, "+{x:0>4}: ", .{si_r});
            try stdout.wr.writeAll(buffer_r.items);
            try stdout.wr.writeByte('\n');
        }

        if (!diff_mode and (i_l / 0x10) != (si_l / 0x10))
            try stdout.wr.writeByte('\n');

        try stdout.bw.flush();
    }
}

fn disasmAt(writer: anytype, code: []const u8, i: usize) !usize {
    const da = isa.disasmAt(code, i);

    try stdout.tc.setColor(writer, .bright_green);
    try writer.writeAll(@tagName(da.opcode.op));
    try stdout.tc.setColor(writer, .reset);

    switch (da.opcode.op) {
        .PUSH => if (da.opcode.t == null) {
            try stdout.tc.setColor(writer, .bright_red);
            try std.fmt.format(writer, " {s}", .{da.opcode.@"var".?});
            try stdout.tc.setColor(writer, .reset);
            try writer.writeAll(" (len ");
            try stdout.tc.setColor(writer, .bright_blue);
            try std.fmt.format(writer, "{d}", .{da.opcode.@"var".?.len});
            try stdout.tc.setColor(writer, .reset);
            try writer.writeAll(")");
        } else {
            try reportType(writer, da.opcode.t.?);
            switch (da.opcode.t.?) {
                .INTEGER => try std.fmt.format(writer, " {} (0x{x})", .{ da.value.?.integer, da.value.?.integer }),
                .LONG => try std.fmt.format(writer, " {} (0x{x})", .{ da.value.?.long, da.value.?.long }),
                .SINGLE => try std.fmt.format(writer, " {}", .{da.value.?.single}),
                .DOUBLE => try std.fmt.format(writer, " {}", .{da.value.?.double}),
                .STRING => {
                    try stdout.tc.setColor(writer, .bright_yellow);
                    try std.fmt.format(writer, " \"{s}\"", .{da.value.?.string});
                    try stdout.tc.setColor(writer, .reset);
                    try writer.writeAll(" (len ");
                    try stdout.tc.setColor(writer, .bright_blue);
                    try std.fmt.format(writer, "{d}", .{da.value.?.string.len});
                    try stdout.tc.setColor(writer, .reset);
                    try writer.writeAll(")");
                },
            }
        },
        .CAST => {
            try reportType(writer, da.opcode.tc.?.from);
            try reportType(writer, da.opcode.tc.?.to);
        },
        .LET => {
            try stdout.tc.setColor(writer, .bright_red);
            try std.fmt.format(writer, " {s}", .{da.opcode.@"var".?});
            try stdout.tc.setColor(writer, .reset);
            try writer.writeAll(" (len ");
            try stdout.tc.setColor(writer, .bright_blue);
            try std.fmt.format(writer, "{d}", .{da.opcode.@"var".?.len});
            try stdout.tc.setColor(writer, .reset);
            try writer.writeAll(")");
        },
        .PRINT => {
            try reportType(writer, da.opcode.t.?);
        },
        .PRINT_COMMA, .PRINT_LINEFEED => {},
        .ALU => {
            try reportType(writer, da.opcode.t.?);
            try stdout.tc.setColor(writer, .bright_cyan);
            try std.fmt.format(writer, " {s}", .{@tagName(da.opcode.alu.?)});
            try stdout.tc.setColor(writer, .reset);
        },
        .JUMP => {
            try reportType(writer, da.opcode.cond.?);
            try std.fmt.format(writer, " {} (0x{x})", .{ da.target.?.absolute, da.target.?.absolute });
        },
        .PRAGMA => {
            try reportType(writer, .printed);
            try stdout.tc.setColor(writer, .bright_yellow);
            try std.fmt.format(writer, " \"{s}\"", .{da.value.?.string});
            try stdout.tc.setColor(writer, .reset);
            try writer.writeAll(" (len ");
            try stdout.tc.setColor(writer, .bright_blue);
            try std.fmt.format(writer, "{d}", .{da.value.?.string.len});
            try stdout.tc.setColor(writer, .reset);
            try writer.writeAll(")");
        },
    }

    return da.i;
}

fn reportType(writer: anytype, t: anytype) !void {
    try stdout.tc.setColor(writer, .bright_green);
    try writer.writeByte(' ');
    for (@tagName(t)) |c|
        try writer.writeByte(std.ascii.toLower(c));
    try stdout.tc.setColor(writer, .reset);
}

pub const RunEffects = struct {
    const Self = @This();
    pub const Error = std.fs.File.WriteError;
    const Writer = std.io.GenericWriter(*Self, std.fs.File.WriteError, writerFn);

    allocator: Allocator,
    writer: Writer,
    printloc: PrintLoc = .{},

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .writer = Writer{ .context = self },
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    fn writerFn(self: *Self, m: []const u8) std.fs.File.WriteError!usize {
        self.printloc.write(m);
        try stdout.wr.writeAll(m);
        try stdout.bw.flush();
        return m.len;
    }

    pub fn print(self: *Self, v: isa.Value) !void {
        try isa.fmt.print(self.allocator, self.writer, v);
    }

    pub fn printComma(self: *Self) !void {
        switch (self.printloc.comma()) {
            .newline => try self.writer.writeByte('\n'),
            .spaces => |s| try self.writer.writeByteNTimes(' ', s),
        }
    }

    pub fn printLinefeed(self: *Self) !void {
        try self.writer.writeByte('\n');
    }

    pub fn pragmaPrinted(self: *Self, s: []const u8) !void {
        _ = self;
        std.log.debug("ignoring PRAGMA PRINTED: {}", .{std.zig.fmtEscapes(s)});
    }
};
