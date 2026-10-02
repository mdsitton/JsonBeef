#!/usr/bin/env python3
"""The canonical-form oracle for JSON5 1.0.0 (spec.json5.org), independent of JsonBeef.

Usage:
  json5-canonical.py FILE            print FILE's canonical form (docs/test-suites.md §9.2), or the
                                     reason it is not JSON5 (stderr, exit 1)
  json5-canonical.py -batch OUTDIR   read `id<TAB>path` lines on stdin; write OUTDIR/<id>.out or .rej

A recursive-descent reader written from the JSON5 specification (and ECMAScript 5.1 for identifiers,
escapes, numbers and whitespace), with JsonBeef's default policies for what JSON5 leaves to
JavaScript: the text must be UTF-8 (one leading BOM skipped), and lone surrogates are errors.
Numbers keep their kind: an integer token (decimal or hexadecimal) prints exactly when it fits 64
bits, every other number as its double; `NaN`, `Infinity` and `-Infinity` print as such. The output
functions are json-canonical.py's.
"""
import importlib.util
import os
import re
import sys
import unicodedata

sys.setrecursionlimit(100000)

_spec = importlib.util.spec_from_file_location("canonical", os.path.join(os.path.dirname(os.path.abspath(__file__)), "json-canonical.py"))
canonical_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(canonical_module)
Number = canonical_module.Number
Object = canonical_module.Object
NotJson = canonical_module.NotJson


class NonFinite:
    __slots__ = ("text",)

    def __init__(self, text):
        self.text = text


def canonical(v):
    if isinstance(v, NonFinite):
        return v.text
    if isinstance(v, Object):
        return "{" + ",".join(canonical_module.string(k) + ":" + canonical(x) for k, x in v.pairs) + "}"
    if isinstance(v, list):
        return "[" + ",".join(canonical(x) for x in v) + "]"
    return canonical_module.canonical(v)


LINE_TERMINATORS = "\n\r  "


def is_space(ch):
    return ch in "\t\n\x0b\x0c\r \xa0  ﻿" or unicodedata.category(ch) == "Zs"


def id_start(ch):
    return ch in "$_" or unicodedata.category(ch) in ("Lu", "Ll", "Lt", "Lm", "Lo", "Nl")


def id_part(ch):
    return id_start(ch) or ch in "‌‍" or unicodedata.category(ch) in ("Mn", "Mc", "Nd", "Pc")


DECIMAL = re.compile(r"(0|[1-9][0-9]*)?(\.[0-9]*)?([eE][+-]?[0-9]+)?")
HEX = re.compile(r"0[xX][0-9a-fA-F]+")


class Reader:
    def __init__(self, text):
        self.s = text
        self.i = 0

    def fail(self, why):
        raise NotJson(f"{why} at {self.i}")

    def peek(self):
        return self.s[self.i] if self.i < len(self.s) else ""

    def skip(self):
        while self.i < len(self.s):
            ch = self.s[self.i]
            if is_space(ch):
                self.i += 1
            elif self.s.startswith("//", self.i):
                self.i += 2
                while self.i < len(self.s) and self.s[self.i] not in LINE_TERMINATORS:
                    self.i += 1
            elif self.s.startswith("/*", self.i):
                end = self.s.find("*/", self.i + 2)
                if end < 0:
                    self.fail("unterminated comment")
                self.i = end + 2
            else:
                return

    def document(self):
        self.skip()
        if self.i >= len(self.s):
            self.fail("no value")
        v = self.value()
        self.skip()
        if self.i < len(self.s):
            self.fail("content after the value")
        return v

    def value(self):
        ch = self.peek()
        if ch == "{":
            return self.object()
        if ch == "[":
            return self.array()
        if ch and ch in "\"'":
            return self.string()
        for word, v in (("null", None), ("true", True), ("false", False)):
            if self.s.startswith(word, self.i):
                after = self.s[self.i + len(word):self.i + len(word) + 1]
                if after and id_part(after):
                    self.fail("bad literal")
                self.i += len(word)
                return v
        if ch and ch in "+-.0123456789IN":
            return self.number()
        self.fail("expected a value")

    def number(self):
        start = self.i
        sign = ""
        if self.peek() in "+-":
            sign = self.peek()
            self.i += 1
        rest = self.s[self.i:]
        for word in ("Infinity", "NaN"):
            if rest.startswith(word):
                self.i += len(word)
                self.check_end()
                if word == "NaN":
                    return NonFinite("NaN")
                return NonFinite("-Infinity" if sign == "-" else "Infinity")
        m = HEX.match(rest)
        if m:
            self.i += m.end()
            self.check_end()
            value = int(m.group(0), 16)
            if sign == "-" and value == 0:
                return Number("-0", True)
            return Number(("-" if sign == "-" else "") + str(value), True)
        m = DECIMAL.match(rest)
        text = m.group(0) if m else ""
        int_part, frac, exp = (m.group(1), m.group(2), m.group(3)) if m else (None, None, None)
        digits = (int_part or "") + (frac[1:] if frac else "")
        if not digits:
            self.fail("bad number")
        if rest[len(text):len(text) + 1].isdigit():
            self.fail("leading zero")
        self.i += len(text)
        self.check_end()
        is_int = frac is None and exp is None
        literal = ("-" if sign == "-" else "") + text
        if is_int:
            return Number(literal, True)
        return Number(literal, False)

    def check_end(self):
        ch = self.peek()
        if ch and (ch.isalnum() or ch in "._$+-" or (ord(ch) >= 0x80 and id_part(ch))):
            self.fail("number runs into text")

    def string(self):
        quote = self.s[self.i]
        self.i += 1
        out = []
        while True:
            if self.i >= len(self.s):
                self.fail("unterminated string")
            ch = self.s[self.i]
            if ch == quote:
                self.i += 1
                return "".join(out)
            if ch in "\n\r":
                self.fail("line break in string")
            if ch != "\\":
                out.append(ch)
                self.i += 1
                continue
            self.i += 1
            if self.i >= len(self.s):
                self.fail("unterminated string")
            e = self.s[self.i]
            simple = {"b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v"}
            if e in simple:
                out.append(simple[e])
                self.i += 1
            elif e == "0":
                if self.s[self.i + 1:self.i + 2].isdigit():
                    self.fail("\\0 before a digit")
                out.append("\0")
                self.i += 1
            elif e in "123456789":
                self.fail("octal escape")
            elif e == "x":
                hx = self.s[self.i + 1:self.i + 3]
                if not re.fullmatch(r"[0-9a-fA-F]{2}", hx):
                    self.fail("bad \\x")
                out.append(chr(int(hx, 16)))
                self.i += 3
            elif e == "u":
                out.append(self.unicode_escape())
            elif e == "\r":
                self.i += 1
                if self.peek() == "\n":
                    self.i += 1
            elif e in "\n  ":
                self.i += 1
            else:
                out.append(e)
                self.i += 1

    def unicode_escape(self):
        """At the `u` of `\\uXXXX` (and a following low surrogate's escape after a high one)."""
        hx = self.s[self.i + 1:self.i + 5]
        if not re.fullmatch(r"[0-9a-fA-F]{4}", hx):
            self.fail("bad \\u")
        cp = int(hx, 16)
        self.i += 5
        if 0xD800 <= cp <= 0xDBFF and self.s.startswith("\\u", self.i):
            low = self.s[self.i + 2:self.i + 6]
            if re.fullmatch(r"[0-9a-fA-F]{4}", low) and 0xDC00 <= int(low, 16) <= 0xDFFF:
                self.i += 6
                return chr(0x10000 + ((cp - 0xD800) << 10) + (int(low, 16) - 0xDC00))
        return chr(cp)

    def name(self):
        ch = self.peek()
        if ch and ch in "\"'":
            return self.string()
        out = []
        while self.i < len(self.s):
            ch = self.s[self.i]
            if ch == "\\":
                if not self.s.startswith("\\u", self.i):
                    self.fail("bad escape in a name")
                self.i += 1
                c = self.unicode_escape()
            else:
                c = ch
            ok = id_start(c) if not out else id_part(c)
            if not ok:
                if ch == "\\":
                    self.fail("escape of a non-identifier character")
                break
            out.append(c)
            if ch != "\\":
                self.i += 1
        if not out:
            self.fail("expected a name")
        return "".join(out)

    def object(self):
        self.i += 1
        pairs = []
        while True:
            self.skip()
            if self.peek() == "}":
                self.i += 1
                return Object(pairs)
            key = self.name()
            self.skip()
            if self.peek() != ":":
                self.fail("expected :")
            self.i += 1
            self.skip()
            pairs.append((key, self.value()))
            self.skip()
            if self.peek() == ",":
                self.i += 1
            elif self.peek() == "}":
                self.i += 1
                return Object(pairs)
            else:
                self.fail("expected , or }")

    def array(self):
        self.i += 1
        items = []
        while True:
            self.skip()
            if self.peek() == "]":
                self.i += 1
                return items
            items.append(self.value())
            self.skip()
            if self.peek() == ",":
                self.i += 1
            elif self.peek() == "]":
                self.i += 1
                return items
            else:
                self.fail("expected , or ]")


def convert(path):
    with open(path, "rb") as f:
        data = f.read()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    try:
        text = data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as e:
        raise NotJson(f"invalid UTF-8: {e}")
    try:
        return canonical(Reader(text).document()) + "\n"
    except RecursionError:
        # Nesting beyond Python's stack (JsonBeef's MaxDepth, 1024, rejects it too)
        raise NotJson("nested too deep")


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "-batch":
        for line in sys.stdin:
            line = line.rstrip("\n")
            if not line:
                continue
            case_id, path = line.split("\t", 1)
            try:
                out = convert(path)
                with open(os.path.join(sys.argv[2], case_id + ".out"), "wb") as f:
                    f.write(out.encode("utf-8"))
            except NotJson as e:
                with open(os.path.join(sys.argv[2], case_id + ".rej"), "w") as f:
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
