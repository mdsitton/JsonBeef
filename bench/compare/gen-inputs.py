#!/usr/bin/env python3
"""Writes the comparison benchmark inputs into inputs/ (git-ignored). Deterministic (fixed seed).
Run ./fetch.sh first: the real-world files come from deps/corpus (pinned, sha256-checked).

Every input is UTF-8 without a BOM, LF line endings. Files ending in .ndjson are batches: one JSON
document per line, and every harness splits them into lines before timing (outside the timed region,
as a server receives separate requests) and parses each line as its own document; one operation
parses every line once. run.sh reports their MB/s like any other input and their ns per document
in a table of its own.

  input             kind       what                                                        size
  twitter           real       Twitter search API results (statuses with users, entities,  617 KB
                               retweets; CJK text, many \\u escapes; 64-bit ids)
  twitterescaped    real       twitter.json with all non-ASCII written as \\u escapes        549 KB
  citm_catalog      real       a ticketing catalog: maps keyed by numeric ids, many small   1.6 MB
                               integer arrays, nulls (the serde-rs/json-benchmark input)
  canada            real       Canada's border as GeoJSON: 111k [lon, lat] float pairs      2.1 MB
  github_events     real       GitHub events API page (URLs, nested objects)               64 KB
  gsoc-2018         real       Google Summer of Code 2018 projects (long text strings)     3.2 MB
  mesh              real       a 3D mesh (three.js): flat arrays of small floats and ints  707 KB
  numbers           real       one array of 10,001 random doubles                          147 KB
  marine_ik         real       a three.js skinned model: deep arrays of floats             2.8 MB
  tiny              generated  ~37k tiny documents (100-500 B: events, pings, key/values)  ~4 MB, batch
  rest              generated  ~2k REST API responses of 1-10 KB (users, orders, pages)    ~4 MB, batch
  records           generated  one array of 10k small objects (json-generator.com style)  ~5 MB
  strings           generated  string- and Unicode-heavy: escapes (\\n \\t \\" \\\\ \\/ \\uXXXX),  ~3 MB
                               raw UTF-8 of 1-4 bytes, surrogate-pair escapes for astral
                               characters, non-ASCII keys, long and short strings
  integers          generated  integer-heavy: small and 32-bit values, values near 2^53,   ~3 MB
                               2^63 and 2^64 (up to 18446744073709551615 and down to
                               -9223372036854775808; nothing beyond 64 bits)
  floats            generated  float-heavy beyond canada: shortest round-trip doubles, 20-  ~3 MB
                               to 40-digit mantissas, exact halfway points between adjacent
                               doubles, subnormals, the extremes of the range, exponent
                               forms, -0.0 (no value overflows to infinity)
  events            generated  NDJSON application log: ~13k events, one per line         ~5 MB, batch
                               (300 B-1.5 KB, nested request/user objects, tags, timings)

The real-world files are simdjson's jsonexamples (github.com/simdjson/simdjson-data, the commit
simdjson v5.0.1 pins), which have no license file of their own; twitter, citm_catalog and canada are
also redistributed by Milo Yip's nativejson-benchmark (MIT) and serde-rs/json-benchmark (MIT/Apache-2.0),
which say where they come from: twitter.json is a Twitter API search response, citm_catalog.json an
export of a ticketing catalog, canada.json Canada's outline from a public GeoJSON dataset. mesh and
marine_ik are three.js example models (MIT); github_events is a GitHub API response; gsoc-2018 is
Google Summer of Code data; numbers.json was generated for simdjson. They are used here only as
benchmark inputs and are not redistributed by this repository (fetch.sh downloads them).

The check lines every harness prints (and run.sh compares with reference.py's) are defined in
reference.py. U+0000 is never generated (NUL-terminated C APIs cannot return it; conformance is the
test suites' job, not this benchmark's), and no number exceeds the 64-bit integer range or the double
range.
"""
import json
import math
import os
import random
import shutil
import struct
from decimal import Decimal, getcontext

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "inputs")
CORPUS = os.path.join(HERE, "deps", "corpus")
REAL = ("twitter", "twitterescaped", "citm_catalog", "canada", "github_events", "gsoc-2018", "mesh",
        "numbers", "marine_ik")

WORDS = ("the of and to in is was that for it with as his on be at by had not are but from or have an "
         "they which one you were all her she there would their we him been has when who will more no "
         "if out so said what up its about into than them can only other new some could time these two "
         "may then do first any my now such like our over man me even most made after also did many "
         "before must through back years where much your way well down should because each just those "
         "people how too little state good very make world still own see men work long get here between "
         "both life being under never day same another know while last might us great old year off come "
         "since against go came right used take three").split()
NAMES = ("Ada Grace Alan Edsger Barbara Donald Ken Dennis Linus Margaret Radia Frances Leslie John Niklaus "
         "Tony Bjarne Guido Yukihiro James Anders Brendan Rob Robert Sophie Mateo Zoë Søren Ægir José "
         "Łukasz Ðorđe Chloé François Jürgen Björk Иван Мария 太郎 花子 민준 서연 Αθηνά Νίκος").split()
UNICODE = ("café naïve résumé Zürich Straße façade jalapeño São Paulo Kraków Ærøskøbing smörgåsbord "
           "Ελληνικά русский язык українська עברית العربية हिन्दी বাংলা ไทย 日本語の文章 中文字符 "
           "한국어 문장 ∑∫√∞≠≤≥ ♠♣♥♦ ☃★☂ 😀😂🥰😎🤖👍🏽👨‍👩‍👧 🎉🚀🌍 𝄞𝔘𝔫𝔦𝔠𝔬𝔡𝔢 𐍈𐌰").split()


def write(name, text):
    path = os.path.join(OUT, name)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    json_check(path)
    print(f"{name:20} {os.path.getsize(path):>10} bytes")


def json_check(path):
    """Every input must be valid JSON (every line, for a batch)"""
    with open(path, encoding="utf-8") as f:
        if path.endswith(".ndjson"):
            for line in f:
                json.loads(line)
        else:
            json.load(f)


def sentence(rng, lo=4, hi=14):
    return " ".join(rng.choice(WORDS) for _ in range(rng.randint(lo, hi)))


def dumps(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def hexid(rng, n):
    return "".join(rng.choice("0123456789abcdef") for _ in range(n))


def iso(rng):
    return (f"2026-{rng.randint(1, 12):02}-{rng.randint(1, 28):02}T{rng.randint(0, 23):02}:"
            f"{rng.randint(0, 59):02}:{rng.randint(0, 59):02}.{rng.randint(0, 999):03}Z")


# ---- tiny: 100-500 B documents ----

def tiny_doc(rng):
    kind = rng.randrange(4)
    if kind == 0:
        doc = {"type": "click", "id": rng.randrange(10**9), "x": rng.randrange(1920), "y": rng.randrange(1080),
               "button": rng.choice(["left", "right"]), "ts": rng.randrange(1_700_000_000_000, 1_800_000_000_000)}
    elif kind == 1:
        doc = {"ok": rng.random() < 0.9, "status": rng.choice([200, 201, 204, 400, 404, 500]),
               "error": None if rng.random() < 0.8 else sentence(rng, 2, 6), "requestId": hexid(rng, 16)}
    elif kind == 2:
        doc = {"key": f"user:{rng.randrange(10**6)}:{rng.choice(WORDS)}", "value": sentence(rng, 1, 8),
               "ttl": rng.randrange(3600), "tags": [rng.choice(WORDS) for _ in range(rng.randrange(4))]}
    else:
        doc = {"sensor": f"s-{rng.randrange(1000)}", "temp": round(rng.uniform(-30, 45), 2),
               "humidity": round(rng.uniform(0, 1), 3), "battery": rng.randrange(101),
               "location": {"lat": round(rng.uniform(-90, 90), 6), "lon": round(rng.uniform(-180, 180), 6)},
               "name": rng.choice(NAMES)}
    text = dumps(doc)
    while len(text.encode()) < 100:
        doc["note"] = doc.get("note", "") + sentence(rng, 2, 4) + " "
        text = dumps(doc)
    return text if len(text.encode()) <= 500 else tiny_doc(rng)


# ---- rest: 1-10 KB API responses ----

def user(rng):
    first, last = rng.choice(NAMES), rng.choice(NAMES)
    return {"id": rng.randrange(10**8), "login": f"{first.lower()}{rng.randrange(1000)}", "name": f"{first} {last}",
            "email": f"{first.lower()}.{rng.randrange(100)}@example.com", "verified": rng.random() < 0.5,
            "createdAt": iso(rng), "avatarUrl": f"https://cdn.example.com/a/{hexid(rng, 24)}.png",
            "followers": rng.randrange(100000), "bio": None if rng.random() < 0.3 else sentence(rng, 5, 25),
            "location": rng.choice([None, "Berlin", "São Paulo", "東京", "Kraków", "Montréal", "Seoul"])}


def order(rng):
    items = [{"sku": f"SKU-{rng.randrange(10**6):06}", "name": sentence(rng, 2, 5), "quantity": rng.randint(1, 5),
              "unitPrice": round(rng.uniform(1, 500), 2), "discount": rng.choice([0, 0, 0.05, 0.1, 0.15]),
              "attributes": {"color": rng.choice(["red", "black", "white", "blue"]),
                             "size": rng.choice(["S", "M", "L", "XL", None])}}
             for _ in range(rng.randint(1, 12))]
    return {"orderId": hexid(rng, 12), "status": rng.choice(["pending", "paid", "shipped", "delivered"]),
            "customer": user(rng), "items": items, "total": round(sum(i["unitPrice"] * i["quantity"] for i in items), 2),
            "currency": rng.choice(["EUR", "USD", "JPY"]), "placedAt": iso(rng),
            "shipping": {"method": rng.choice(["standard", "express"]), "address": {
                "street": f"{rng.randrange(1, 300)} {rng.choice(WORDS).title()} Street", "city": rng.choice(UNICODE),
                "postalCode": f"{rng.randrange(10**5):05}", "country": rng.choice(["DE", "BR", "JP", "PL", "CA", "KR"])}}}


def rest_doc(rng):
    kind = rng.randrange(3)
    if kind == 0:
        doc = order(rng)
    elif kind == 1:
        doc = {"data": [user(rng) for _ in range(rng.randint(2, 12))],
               "page": {"number": rng.randrange(100), "size": 20, "total": rng.randrange(10**5)},
               "links": {"self": f"/api/v2/users?page={rng.randrange(100)}", "next": None if rng.random() < 0.2 else "/api/v2/users?page=2"}}
    else:
        doc = {"id": hexid(rng, 20), "title": sentence(rng, 3, 9), "author": user(rng), "published": rng.random() < 0.8,
               "body": " ".join(sentence(rng, 8, 20) + "." for _ in range(rng.randint(3, 25))),
               "comments": [{"id": rng.randrange(10**9), "by": user(rng)["login"], "text": sentence(rng, 3, 30),
                             "score": rng.randint(-5, 500), "createdAt": iso(rng)} for _ in range(rng.randrange(8))],
               "metrics": {"views": rng.randrange(10**7), "readSeconds": round(rng.uniform(5, 900), 1)}}
    text = dumps(doc)
    size = len(text.encode())
    return text if 1024 <= size <= 10240 else rest_doc(rng)


# ---- records: one array of small objects ----

def records(rng, count):
    out = []
    for i in range(count):
        first, last = rng.choice(NAMES), rng.choice(NAMES)
        out.append({
            "_id": hexid(rng, 24), "index": i, "guid": f"{hexid(rng, 8)}-{hexid(rng, 4)}-{hexid(rng, 4)}-{hexid(rng, 4)}-{hexid(rng, 12)}",
            "isActive": rng.random() < 0.5, "balance": f"${rng.randrange(1000, 4000)},{rng.randrange(1000):03}.{rng.randrange(100):02}",
            "age": rng.randint(18, 90), "eyeColor": rng.choice(["blue", "brown", "green"]), "name": f"{first} {last}",
            "company": rng.choice(WORDS).upper(), "email": f"{first.lower()}@{rng.choice(WORDS)}.com",
            "registered": iso(rng), "latitude": round(rng.uniform(-90, 90), 6), "longitude": round(rng.uniform(-180, 180), 6),
            "tags": [rng.choice(WORDS) for _ in range(rng.randint(0, 7))],
            "friends": [{"id": j, "name": f"{rng.choice(NAMES)} {rng.choice(NAMES)}"} for j in range(rng.randint(0, 3))],
            "favoriteFruit": rng.choice(["apple", "banana", "strawberry"]), "score": rng.choice([None, rng.randrange(100)]),
        })
    return "[\n" + ",\n".join("  " + dumps(r) for r in out) + "\n]\n"


# ---- strings: escapes and Unicode ----

SHORT_ESCAPES = {'"': '\\"', "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t", "\b": "\\b", "\f": "\\f", "/": "\\/"}


def encode_string(rng, s, escape_rate):
    """A JSON string literal for s, each character written raw or escaped at random (quotes, backslashes
    and control characters always escaped): short escapes, \\uXXXX, surrogate pairs for astral characters"""
    out = ['"']
    for ch in s:
        code = ord(ch)
        must = ch in '"\\' or code < 0x20
        if not must and rng.random() >= escape_rate:
            out.append(ch)
        elif ch in SHORT_ESCAPES and rng.random() < 0.8:
            out.append(SHORT_ESCAPES[ch])
        elif code > 0xFFFF:
            code -= 0x10000
            hi, lo = 0xD800 + (code >> 10), 0xDC00 + (code & 0x3FF)
            out.append(f"\\u{hi:04x}\\u{lo:04X}" if rng.random() < 0.5 else f"\\u{hi:04X}\\u{lo:04x}")
        else:
            out.append(f"\\u{code:04x}" if rng.random() < 0.5 else f"\\u{code:04X}")
    out.append('"')
    return "".join(out)


def text_piece(rng):
    kind = rng.randrange(6)
    if kind == 0:
        return sentence(rng, 1, 12)
    if kind == 1:
        return " ".join(rng.choice(UNICODE) for _ in range(rng.randint(1, 10)))
    if kind == 2:
        return "".join(chr(rng.choice([rng.randint(0x20, 0x7E), rng.randint(0xA0, 0x7FF), rng.randint(0x800, 0xD7FF),
                                       rng.randint(0xE000, 0xFFFD), rng.randint(0x10000, 0x10FFFF)]))
                       for _ in range(rng.randint(1, 40)))
    if kind == 3:
        return f'path\\to\\file "{rng.choice(WORDS)}"\n\tline two\r\n/slash/ \x01\x1f'
    if kind == 4:
        return rng.choice(UNICODE) * rng.randint(1, 30)
    return " ".join(sentence(rng, 10, 20) for _ in range(rng.randint(5, 30)))  # long ASCII


def strings(rng, target):
    parts, size = [], 0
    while size < target:
        rate = rng.choice([0.0, 0.0, 0.05, 0.3, 1.0])
        if rng.random() < 0.5:
            item = encode_string(rng, text_piece(rng), rate)
        else:
            fields, keys = [], set()
            for _ in range(rng.randint(1, 6)):
                key = rng.choice([rng.choice(WORDS), rng.choice(UNICODE), rng.choice(NAMES) + "_" + rng.choice(WORDS)])
                if key in keys:  # no duplicate names: trees that keep the last one would count fewer
                    continue
                keys.add(key)
                fields.append(encode_string(rng, key, rate) + ":" + encode_string(rng, text_piece(rng), rate))
            item = "{" + ",".join(fields) + "}"
        parts.append(item)
        size += len(item.encode())
    return "[\n" + ",\n".join(parts) + "\n]\n"


# ---- integers ----

def integer(rng):
    kind = rng.randrange(10)
    if kind < 3:
        return rng.randrange(1000) * rng.choice([1, -1])
    if kind < 5:
        return rng.randrange(-2**31, 2**31)
    if kind == 5:
        return rng.randrange(-2**53, 2**53)
    if kind == 6:
        return rng.choice([1, -1]) * (2**53 + rng.randint(-50, 50))
    if kind == 7:
        return rng.choice([2**63 - 1 - rng.randrange(1000), -2**63 + rng.randrange(1000), rng.randrange(2**62, 2**63)])
    if kind == 8:
        return rng.choice([2**64 - 1 - rng.randrange(1000), rng.randrange(2**63, 2**64), 2**63 + rng.randrange(1000)])
    return rng.randrange(-2**63, 2**63)


def integers(rng, target):
    rows, size = [], 0
    while size < target:
        if rng.random() < 0.7:
            row = dumps([integer(rng) for _ in range(rng.randint(1, 40))])
        else:
            row = dumps({rng.choice(WORDS): integer(rng) for _ in range(rng.randint(1, 8))})
        rows.append(row)
        size += len(row) + 2
    return "[\n" + ",\n".join(rows) + "\n]\n"


# ---- floats ----

def exact(x):
    """The exact decimal value of a double"""
    return Decimal(x)


def float_literal(rng):
    kind = rng.randrange(10)
    if kind < 2:  # shortest round-trip form of a random double over a wide range
        x = rng.uniform(1, 10) * 10.0 ** rng.randint(-300, 300) * rng.choice([1, -1])
        return repr(x)
    if kind == 2:  # 20-40 significant digits
        digits = rng.randint(20, 40)
        mantissa = "".join(rng.choice("0123456789") for _ in range(digits))
        return f"{rng.choice(['', '-'])}{rng.randint(1, 9)}.{mantissa}e{rng.randint(-200, 200)}"
    if kind == 3:  # the exact halfway point between two adjacent doubles (rounds to even)
        x = rng.uniform(1, 2) * 2.0 ** rng.randint(-60, 60)
        halfway = (exact(x) + exact(math.nextafter(x, math.inf))) / 2
        return format(halfway, "f") if abs(halfway.adjusted()) < 25 else format(halfway, "e")
    if kind == 4:  # just above or below a halfway point
        x = rng.uniform(1, 2) * 2.0 ** rng.randint(-30, 30)
        halfway = (exact(x) + exact(math.nextafter(x, math.inf))) / 2
        nudge = Decimal(10) ** (halfway.adjusted() - 30) * rng.choice([1, -1])
        return format(halfway + nudge, "e")
    if kind == 5:  # subnormals and the smallest normals
        return rng.choice(["5e-324", "4.9406564584124654e-324", "2.2250738585072011e-308", "2.2250738585072014e-308",
                           "2.225073858507201136057409796709131975934819546351645648e-308",
                           repr(rng.uniform(0, 2.2250738585072014e-308))])
    if kind == 6:  # the top of the range
        return rng.choice(["1.7976931348623157e308", "1.7976931348623157E+308", "8.98846567431158e307",
                           repr(rng.uniform(1e307, 1.7e308)), "1e308"])
    if kind == 7:  # classic hard cases
        return rng.choice(["1e23", "8.589973e9", "9007199254740993.0", "0.1", "0.3", "2.5e-3", "1E-7", "123456789e-5",
                           "7.038531e-26", "0.0000000000000000000000000000000000000001", "1.00000000000000011102230246251565404236316680908203125",
                           "-0.0", "0.0", "1.0", "100.0e-2", "4.35185e-322"])
    if kind == 8:  # fixed notation with many fractional digits
        return f"{rng.uniform(-1000, 1000):.{rng.randint(10, 20)}f}"
    return f"{rng.randint(1, 9)}e{rng.randint(-307, 307)}"


def floats(rng, target):
    getcontext().prec = 1200
    rows, size = [], 0
    while size < target:
        row = "[" + ",".join(float_literal(rng) for _ in range(rng.randint(1, 30))) + "]"
        rows.append(row)
        size += len(row) + 2
    return "[\n" + ",\n".join(rows) + "\n]\n"


# ---- events: NDJSON application log ----

def event(rng):
    level = rng.choices(["debug", "info", "warn", "error"], [3, 10, 2, 1])[0]
    doc = {"ts": iso(rng), "level": level, "service": rng.choice(["api", "auth", "billing", "search", "worker"]),
           "host": f"node-{rng.randrange(64):02}.eu-west-1", "msg": sentence(rng, 3, 15),
           "request": {"id": hexid(rng, 32), "method": rng.choice(["GET", "POST", "PUT", "DELETE"]),
                       "path": "/" + "/".join(rng.choice(WORDS) for _ in range(rng.randint(1, 4))),
                       "status": rng.choice([200, 200, 200, 201, 204, 301, 400, 401, 404, 500, 503]),
                       "durationMs": round(rng.expovariate(1 / 40), 3), "bytes": rng.randrange(10**6)},
           "user": None if rng.random() < 0.3 else {"id": rng.randrange(10**7), "name": rng.choice(NAMES), "roles": rng.sample(["admin", "dev", "ops", "viewer"], rng.randint(1, 3))},
           "tags": [rng.choice(WORDS) for _ in range(rng.randrange(6))], "sampled": rng.random() < 0.1}
    if level == "error":
        doc["error"] = {"type": rng.choice(["TimeoutError", "ValueError", "IOError"]),
                        "stack": [f"at {rng.choice(WORDS)}.{rng.choice(WORDS)} (src/{rng.choice(WORDS)}.ts:{rng.randrange(900)})" for _ in range(rng.randint(3, 12))]}
    text = dumps(doc)
    return text if 300 <= len(text.encode()) <= 1536 else event(rng)


def batch(rng, make, target):
    lines, size = [], 0
    while size < target:
        line = make(rng)
        lines.append(line)
        size += len(line.encode()) + 1
    return "\n".join(lines) + "\n"


def main():
    os.makedirs(OUT, exist_ok=True)
    for name in REAL:
        shutil.copyfile(os.path.join(CORPUS, name + ".json"), os.path.join(OUT, name + ".json"))
        print(f"{name + '.json':20} {os.path.getsize(os.path.join(OUT, name + '.json')):>10} bytes")
    rng = random.Random(1)
    write("tiny.ndjson", batch(rng, tiny_doc, 4 * 2**20))
    write("rest.ndjson", batch(rng, rest_doc, 4 * 2**20))
    write("records.json", records(rng, 10000))
    write("strings.json", strings(rng, 3 * 2**20))
    write("integers.json", integers(rng, 3 * 2**20))
    write("floats.json", floats(rng, 3 * 2**20))
    write("events.ndjson", batch(rng, event, 5 * 2**20))


if __name__ == "__main__":
    main()
