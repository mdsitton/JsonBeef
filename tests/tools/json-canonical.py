#!/usr/bin/env python3
"""The canonical-form oracle (docs/test-suites.md §9.2), independent of JsonBeef.

Usage:
  json-canonical.py FILE            print FILE's canonical form (exit 0) or the reason it is not
                                    JSON (stderr, exit 1)
  json-canonical.py -batch OUTDIR   read `id<TAB>path` lines on stdin; write OUTDIR/<id>.out with the
                                    canonical form, or OUTDIR/<id>.rej with the reason

Strict RFC 8259 with JsonBeef's default policies: one leading UTF-8 BOM skipped, invalid UTF-8 and
lone surrogate escapes rejected, numbers of any size accepted. Canonical form: UTF-8, no whitespace,
one final newline; members in document order with duplicates; strings with JCS escaping (lowercase
\\u00xx); integer tokens that fit int64 or uint64 exactly (`-0` stays `-0`); every other number as
its correctly rounded double in ECMAScript Number::toString layout, negative zero `-0`, overflow
`Infinity`/`-Infinity`.
"""
import json
import os
import sys

sys.setrecursionlimit(100000)


class Number:
    __slots__ = ("text", "is_int")

    def __init__(self, text, is_int):
        self.text = text
        self.is_int = is_int


class NotJson(Exception):
    pass


def reject_constant(name):
    raise NotJson(f"non-finite number {name}")


class Object:
    """An object's members in document order, duplicates kept."""
    __slots__ = ("pairs",)

    def __init__(self, pairs):
        self.pairs = pairs


def parse(data):
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    try:
        text = data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as e:
        raise NotJson(f"invalid UTF-8: {e}")
    try:
        return json.loads(
            text,
            parse_int=lambda s: Number(s, True),
            parse_float=lambda s: Number(s, False),
            parse_constant=reject_constant,
            object_pairs_hook=Object,
        )
    except (ValueError, RecursionError) as e:
        raise NotJson(str(e))


def ecmascript(value):
    """ECMAScript Number::toString of a finite double (spec-reference §9.5); -0 as `-0`."""
    if value == 0:
        return "-0" if str(value).startswith("-") else "0"
    sign = "-" if value < 0 else ""
    r = repr(abs(value))  # shortest round-trip digits
    if "e" in r:
        mantissa, exp = r.split("e")
        exp = int(exp)
    else:
        mantissa, exp = r, 0
    if "." in mantissa:
        int_part, frac = mantissa.split(".")
    else:
        int_part, frac = mantissa, ""
    digits = int_part + frac
    point = len(int_part) + exp
    stripped = digits.lstrip("0")
    point -= len(digits) - len(stripped)
    digits = stripped.rstrip("0")
    k, n = len(digits), point
    if k <= n <= 21:
        out = digits + "0" * (n - k)
    elif 0 < n <= 21:
        out = digits[:n] + "." + digits[n:]
    elif -6 < n <= 0:
        out = "0." + "0" * (-n) + digits
    else:
        e = n - 1
        es = ("+" if e >= 0 else "-") + str(abs(e))
        out = digits[0] + ("." + digits[1:] if k > 1 else "") + "e" + es
    return sign + out


def number(n):
    if n.is_int:
        if n.text == "-0":
            return "-0"
        v = int(n.text)
        if -(2**63) <= v < 2**64:
            return str(v)
    v = float(n.text)
    if v == float("inf"):
        return "Infinity"
    if v == float("-inf"):
        return "-Infinity"
    return ecmascript(v)


def string(s):
    out = ['"']
    for ch in s:
        c = ord(ch)
        if 0xD800 <= c <= 0xDFFF:
            raise NotJson("lone surrogate")
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\b":
            out.append("\\b")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\f":
            out.append("\\f")
        elif ch == "\r":
            out.append("\\r")
        elif c < 0x20:
            out.append("\\u%04x" % c)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def canonical(v):
    if v is None:
        return "null"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, Number):
        return number(v)
    if isinstance(v, str):
        return string(v)
    if isinstance(v, Object):
        return "{" + ",".join(string(k) + ":" + canonical(x) for k, x in v.pairs) + "}"
    return "[" + ",".join(canonical(x) for x in v) + "]"


def convert(path):
    with open(path, "rb") as f:
        data = f.read()
    return canonical(parse(data)) + "\n"


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "-batch":
        outdir = sys.argv[2]
        for line in sys.stdin:
            line = line.rstrip("\n")
            if not line:
                continue
            case_id, path = line.split("\t", 1)
            try:
                out = convert(path)
                with open(os.path.join(outdir, case_id + ".out"), "wb") as f:
                    f.write(out.encode("utf-8"))
            except NotJson as e:
                with open(os.path.join(outdir, case_id + ".rej"), "w") as f:
                    f.write(str(e) + "\n")
        return 0
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        out = convert(sys.argv[1])
    except NotJson as e:
        print(e, file=sys.stderr)
        return 1
    sys.stdout.buffer.write(out.encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
