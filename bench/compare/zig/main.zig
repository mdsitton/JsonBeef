// Zig std.json benchmark: zig-jsonbench <value|typed|scanner> <input> <min-samples>
//   value   - DOM: std.json.parseFromSlice(std.json.Value, ...) per document, with its defaults
//             (strings copied, numbers parsed: i64 when the text looks like an integer and fits,
//             else f64, else the raw text as .number_string); the Parsed arena is freed after each
//             document.
//   typed   - typed: std.json.parseFromSlice into the structures in typed.zig (json-benchmark's
//             schema, see ../reference.py), with its defaults (unknown and duplicate fields are
//             errors; strings borrowed from the input where they need no unescaping), then freed.
//             twitter, citm_catalog and canada only (exit 3 on other inputs).
//   scanner - streaming: std.json.Scanner.initCompleteInput over each document, one pass over every
//             token with nextAlloc(.alloc_if_needed) (escaped strings are unescaped into an
//             allocation, freed at once); every string's length is added and every number is
//             converted to f64 (std.fmt.parseFloat) and its bits added. No tree.
// A .ndjson input is split into lines before timing (one document each; one run parses them all).
// Built with -O ReleaseFast (the default allocator there is std.heap.smp_allocator). Prints the check
// line (see ../reference.py) first, to stdout, then the timing.
const std = @import("std");
const common = @import("common.zig");
const typed = @import("typed.zig");

const Mode = enum { value, typed, scanner };

const Context = struct {
    gpa: std.mem.Allocator,
    docs: []const []const u8,
    kind: typed.Kind = .twitter,
    failed: bool = false,
    sink: u64 = 0,
};

// ---- value ----

fn walkValue(v: std.json.Value, c: *common.Check) void {
    switch (v) {
        .null => c.nulls += 1,
        .bool => |b| if (b) {
            c.trues += 1;
        } else {
            c.falses += 1;
        },
        .integer => |i| c.number(@floatFromInt(i)),
        .float => |f| c.number(f),
        .number_string => |s| c.number(std.fmt.parseFloat(f64, s) catch std.math.nan(f64)),
        .string => |s| {
            c.strings += 1;
            c.chars += common.codePoints(s);
        },
        .array => |a| {
            c.arrays += 1;
            for (a.items) |x| walkValue(x, c);
        },
        .object => |o| {
            c.objects += 1;
            var it = o.iterator();
            while (it.next()) |e| {
                c.keys += 1;
                c.chars += common.codePoints(e.key_ptr.*);
                walkValue(e.value_ptr.*, c);
            }
        },
    }
}

fn runValue(ctx: *Context) void {
    for (ctx.docs) |d| {
        const parsed = std.json.parseFromSlice(std.json.Value, ctx.gpa, d, .{}) catch {
            ctx.failed = true;
            return;
        };
        parsed.deinit();
    }
}

// ---- scanner ----

fn scanOne(gpa: std.mem.Allocator, doc: []const u8, c: *common.Check, exact: bool) !void {
    var scanner = std.json.Scanner.initCompleteInput(gpa, doc);
    defer scanner.deinit();
    // Whether each open container is an object, and whether the next string in an object is a key
    var stack: [1024]bool = undefined;
    var depth: usize = 0;
    var expect_key = false;
    while (true) {
        const token = try scanner.nextAlloc(gpa, .alloc_if_needed);
        switch (token) {
            .end_of_document => break,
            .object_begin => {
                c.objects += 1;
                stack[depth] = true;
                depth += 1;
                expect_key = true;
                continue;
            },
            .array_begin => {
                c.arrays += 1;
                stack[depth] = false;
                depth += 1;
                expect_key = false;
                continue;
            },
            .object_end, .array_end => depth -= 1,
            .string, .allocated_string => |s| {
                if (expect_key) {
                    c.keys += 1;
                } else {
                    c.strings += 1;
                }
                c.chars += if (exact) common.codePoints(s) else s.len;
                if (token == .allocated_string) gpa.free(s);
                if (expect_key) {
                    expect_key = false;
                    continue;
                }
            },
            .number, .allocated_number => |s| {
                c.number(try std.fmt.parseFloat(f64, s));
                if (token == .allocated_number) gpa.free(s);
            },
            .true => c.trues += 1,
            .false => c.falses += 1,
            .null => c.nulls += 1,
            else => unreachable,
        }
        // A value (or a container) ended: inside an object, a key comes next
        expect_key = depth > 0 and stack[depth - 1];
    }
}

fn runScanner(ctx: *Context) void {
    var c: common.Check = .{};
    for (ctx.docs) |d| {
        scanOne(ctx.gpa, d, &c, false) catch {
            ctx.failed = true;
            return;
        };
    }
    ctx.sink +%= c.numsum +% @as(u64, @intCast(c.chars));
}

// ---- typed ----

fn runTyped(ctx: *Context) void {
    typed.parseAndFree(ctx.gpa, ctx.kind, ctx.docs[0]) catch {
        ctx.failed = true;
    };
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 4) {
        std.debug.print("usage: zig-jsonbench <value|typed|scanner> <input> <min-samples>\n", .{});
        std.process.exit(2);
    }
    const io = init.io;
    const gpa = init.gpa;
    const mode = std.meta.stringToEnum(Mode, args[1]) orelse {
        std.debug.print("unknown variant {s}\n", .{args[1]});
        std.process.exit(2);
    };
    const in = try common.readInputs(io, gpa, args[2]);
    const min_samples = try std.fmt.parseInt(usize, args[3], 10);
    var ctx: Context = .{ .gpa = gpa, .docs = in.docs.items };

    var m: common.Measurement = undefined;
    switch (mode) {
        .value => {
            var check: common.Check = .{};
            for (in.docs.items) |d| {
                const parsed = std.json.parseFromSlice(std.json.Value, gpa, d, .{}) catch |err| {
                    std.debug.print("parse error: {t}\n", .{err});
                    std.process.exit(1);
                };
                walkValue(parsed.value, &check);
                parsed.deinit();
            }
            check.print(io);
            m = try common.measure(io, gpa, min_samples, &ctx, runValue);
        },
        .scanner => {
            var check: common.Check = .{};
            for (in.docs.items) |d| {
                scanOne(gpa, d, &check, true) catch |err| {
                    std.debug.print("parse error: {t}\n", .{err});
                    std.process.exit(1);
                };
            }
            check.print(io);
            m = try common.measure(io, gpa, min_samples, &ctx, runScanner);
        },
        .typed => {
            ctx.kind = typed.kindOf(args[2]) orelse std.process.exit(3);
            typed.printCheck(io, gpa, ctx.kind, in.docs.items[0]) catch |err| {
                std.debug.print("parse error: {t}\n", .{err});
                std.process.exit(1);
            };
            m = try common.measure(io, gpa, min_samples, &ctx, runTyped);
        },
    }
    if (ctx.failed) std.process.exit(1);
    common.report(io, m, in.total);
}
