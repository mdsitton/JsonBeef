// Shared by the Zig harness: the measurement rule, input loading and the check line.
const std = @import("std");

pub const Measurement = struct { median_ns: f64, samples: usize, converged: bool };

/// The shared rule (see ../run.sh): warm up for at least 1 s, then time single runs until at least
/// `min_samples` were taken and at least 60% lie within ±10% of their median, or 10 s / 1000 samples.
/// (From XmlBeef's bench/compare/zig/common.zig.)
pub fn measure(io: std.Io, gpa: std.mem.Allocator, min_samples: usize, context: anytype, comptime op: fn (@TypeOf(context)) void) !Measurement {
    const warm = std.Io.Timestamp.now(io, .awake);
    while (true) {
        op(context);
        if (warm.untilNow(io, .awake).nanoseconds >= std.time.ns_per_s) break;
    }
    var samples: std.ArrayList(f64) = .empty;
    defer samples.deinit(gpa);
    var sorted: std.ArrayList(f64) = .empty;
    defer sorted.deinit(gpa);
    const start = std.Io.Timestamp.now(io, .awake);
    while (true) {
        const t0 = std.Io.Timestamp.now(io, .awake);
        op(context);
        try samples.append(gpa, @floatFromInt(t0.untilNow(io, .awake).nanoseconds));
        sorted.clearRetainingCapacity();
        try sorted.appendSlice(gpa, samples.items);
        std.mem.sort(f64, sorted.items, {}, std.sort.asc(f64));
        const n = sorted.items.len;
        const median = if (n % 2 == 1) sorted.items[n / 2] else (sorted.items[n / 2 - 1] + sorted.items[n / 2]) / 2;
        if (n >= min_samples) {
            var within: usize = 0;
            for (samples.items) |s| {
                if (s >= median * 0.9 and s <= median * 1.1) within += 1;
            }
            if (@as(f64, @floatFromInt(within)) >= 0.6 * @as(f64, @floatFromInt(n)))
                return .{ .median_ns = median, .samples = n, .converged = true };
        }
        if (n >= 1000 or start.untilNow(io, .awake).nanoseconds >= 10 * std.time.ns_per_s)
            return .{ .median_ns = median, .samples = n, .converged = false };
    }
}

/// Prints a line to stdout (unbuffered: the check line must be out before a crash)
pub fn out(io: std.Io, comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, fmt, args) catch return;
    std.Io.File.stdout().writeStreamingAll(io, line) catch {};
}

pub fn report(io: std.Io, m: Measurement, total: usize) void {
    const ms = m.median_ns / 1e6;
    const mbps = @as(f64, @floatFromInt(total)) / 1048576.0 / (ms / 1000.0);
    out(io, "{d:.3} ms/op {d:.1} MB/s (n={d}, {s})\n", .{ ms, mbps, m.samples, if (m.converged) "converged" else "capped" });
}

/// The bit pattern of a double, -0 counted as +0
pub fn bits(d: f64) u64 {
    return @bitCast(d + 0.0);
}

/// The dom/stream check line (see ../reference.py)
pub const Check = struct {
    objects: u64 = 0,
    arrays: u64 = 0,
    keys: u64 = 0,
    strings: u64 = 0,
    numbers: u64 = 0,
    trues: u64 = 0,
    falses: u64 = 0,
    nulls: u64 = 0,
    chars: u64 = 0,
    numsum: u64 = 0,

    pub fn number(c: *Check, d: f64) void {
        c.numbers += 1;
        c.numsum +%= bits(d);
    }

    pub fn print(c: Check, io: std.Io) void {
        out(io, "check: {d} {d} {d} {d} {d} {d} {d} {d} {d} {x:0>16}\n", .{ c.objects, c.arrays, c.keys, c.strings, c.numbers, c.trues, c.falses, c.nulls, c.chars, c.numsum });
    }
};

/// Unicode code points in UTF-8 text
pub fn codePoints(s: []const u8) u64 {
    var n: u64 = 0;
    for (s) |b| n += @intFromBool(b & 0xC0 != 0x80);
    return n;
}

pub const Inputs = struct {
    docs: std.ArrayList([]const u8) = .empty,
    total: usize = 0,
};

/// The input's documents: the file, or each non-empty line of a .ndjson file
pub fn readInputs(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !Inputs {
    var in: Inputs = .{};
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    in.total = data.len;
    if (!std.mem.endsWith(u8, path, ".ndjson")) {
        try in.docs.append(gpa, data);
        return in;
    }
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        // Each line in its own allocation, as separately received documents would be
        try in.docs.append(gpa, try gpa.dupe(u8, line));
    }
    return in;
}
