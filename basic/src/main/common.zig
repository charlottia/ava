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

pub fn xxd(code: []const u8) !void {
    var i: usize = 0;

    while (i < code.len) : (i += 16) {
        try stdout.tc.setColor(stdout.wr, .white);
        try std.fmt.format(stdout.wr, "{x:0>4}:", .{i});
        const c = @min(code.len - i, 16);
        for (0..c) |j| {
            const ch = code[i + j];
            if (j % 2 == 0)
                try stdout.wr.writeByte(' ');
            if (ch == 0)
                try stdout.tc.setColor(stdout.wr, .reset)
            else if (ch < 32 or ch > 126)
                try stdout.tc.setColor(stdout.wr, .bright_yellow)
            else
                try stdout.tc.setColor(stdout.wr, .bright_green);
            try std.fmt.format(stdout.wr, "{x:0>2}", .{ch});
        }

        for (c..16) |j| {
            if (j % 2 == 0)
                try stdout.wr.writeByte(' ');
            try stdout.wr.writeAll("  ");
        }

        try stdout.wr.writeAll("  ");
        for (0..c) |j| {
            const ch = code[i + j];
            if (ch == 0) {
                try stdout.tc.setColor(stdout.wr, .reset);
                try stdout.wr.writeByte('.');
            } else if (ch < 32 or ch > 126) {
                try stdout.tc.setColor(stdout.wr, .bright_yellow);
                try stdout.wr.writeByte('.');
            } else {
                try stdout.tc.setColor(stdout.wr, .bright_green);
                try stdout.wr.writeByte(ch);
            }
        }

        try stdout.wr.writeByte('\n');
    }

    try stdout.tc.setColor(stdout.wr, .reset);
    try stdout.bw.flush();
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
            try disasmAt(buffer_l.writer(allocator), code_l, &i_l);

        var buffer_r = std.ArrayListUnmanaged(u8){};
        defer buffer_r.deinit(allocator);
        if (i_r < code_r.len)
            try disasmAt(buffer_r.writer(allocator), code_r, &i_r);

        const mismatch = diff_mode and
            (si_l != si_r or !std.mem.eql(u8, buffer_l.items, buffer_r.items));

        if (mismatch) {
            try stdout.tc.setColor(stdout.wr, .bright_red);
            try stdout.wr.writeByte('-');
        } else if (diff_mode)
            try stdout.wr.writeByte(' ');
        try std.fmt.format(stdout.wr, "{x:0>4}: ", .{si_l});
        try stdout.wr.writeAll(buffer_l.items);
        try stdout.wr.writeByte('\n');

        if (mismatch) {
            try stdout.tc.setColor(stdout.wr, .bright_green);
            try std.fmt.format(stdout.wr, "+{x:0>4}: ", .{si_r});
            try stdout.wr.writeAll(buffer_r.items);
            try stdout.wr.writeByte('\n');
        }

        try stdout.bw.flush();
    }
}

fn disasmAt(writer: anytype, code: []const u8, i: *usize) !void {
    const ix: isa.InsnX = @bitCast(code[i.*]);
    const it: isa.InsnT = @bitCast(code[i.*]);
    const itc: isa.InsnTC = @bitCast(code[i.*]);
    const ic: isa.InsnC = @bitCast(code[i.*]);
    i.* += 1;
    const op = ix.op;

    try stdout.tc.setColor(writer, .bright_green);
    try writer.writeAll(@tagName(op));
    try stdout.tc.setColor(writer, .reset);

    switch (op) {
        .PUSH => if (ix.rest == 0b1000) {
            const slot = code[i.*];
            i.* += 1;
            try std.fmt.format(writer, " slot {d}", .{slot});
        } else switch (it.t) {
            .INTEGER => {
                const n = std.mem.readInt(i16, code[i.*..][0..2], .little);
                i.* += 2;
                try reportType(writer, it.t);
                try std.fmt.format(writer, " {} (0x{x})", .{ n, n });
            },
            .LONG => {
                const n = std.mem.readInt(i32, code[i.*..][0..4], .little);
                i.* += 4;
                try reportType(writer, it.t);
                try std.fmt.format(writer, " {} (0x{x})", .{ n, n });
            },
            .SINGLE => {
                var r: [1]f32 = undefined;
                @memcpy(std.mem.sliceAsBytes(r[0..]), code[i.*..][0..4]);
                i.* += 4;
                try reportType(writer, it.t);
                try std.fmt.format(writer, " {}", .{r[0]});
            },
            .DOUBLE => {
                var r: [1]f64 = undefined;
                @memcpy(std.mem.sliceAsBytes(r[0..]), code[i.*..][0..8]);
                i.* += 8;
                try reportType(writer, it.t);
                try std.fmt.format(writer, " {}", .{r[0]});
            },
            .STRING => {
                const len = std.mem.readInt(u16, code[i.*..][0..2], .little);
                i.* += 2;
                const str = code[i.*..][0..len];
                i.* += len;
                try reportType(writer, it.t);
                try std.fmt.format(writer, " \"{s}\" (len {d})", .{ str, len });
            },
        },
        .CAST => {
            try reportType(writer, itc.tf);
            try reportType(writer, itc.tt);
        },
        .LET => {
            const slot = code[i.*];
            i.* += 1;
            try std.fmt.format(writer, " slot {d}", .{slot});
        },
        .PRINT => {
            try reportType(writer, it.t);
        },
        .PRINT_COMMA, .PRINT_LINEFEED => {},
        .ALU => {
            const ia: isa.InsnAlu = @bitCast(code[i.* - 1 ..][0..2].*);
            i.* += 1;
            try reportType(writer, ia.t);
            try std.fmt.format(writer, " {s}", .{@tagName(ia.alu)});
        },
        .JUMP => {
            const target = std.mem.readInt(u16, code[i.*..][0..2], .little);
            i.* += 2;
            try reportType(writer, ic.cond);
            try std.fmt.format(writer, " {} (0x{x})", .{ target, target });
        },
        .PRAGMA => {
            const len = std.mem.readInt(u16, code[i.*..][0..2], .little);
            i.* += 2;
            const str = code[i.*..][0..len];
            i.* += len;
            try reportType(writer, .printed);
            try std.fmt.format(writer, " \"{s}\" (len {d})", .{ str, len });
        },
    }
}

fn reportType(writer: anytype, t: anytype) !void {
    try stdout.tc.setColor(writer, .cyan);
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
