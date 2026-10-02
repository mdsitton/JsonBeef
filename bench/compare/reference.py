#!/usr/bin/env python3
"""The reference check lines run.sh compares every harness with, computed with Python's json module
(correctly rounded float conversion, arbitrary-precision integers), and the definitions every harness
implements:

    reference.py <dom|typed|stream|query> <input-file>

dom and stream (one line for both: a streaming pass sees the same values a tree holds):

    check: <objects> <arrays> <keys> <strings> <numbers> <true> <false> <null> <chars> <numsum>

  objects, arrays     containers, the root included
  keys                object member names (every occurrence)
  strings             string values (not keys)
  numbers, true, false, null   the other values
  chars               Unicode code points in every key and string value after unescaping (a
                      surrogate-pair escape is one code point)
  numsum              16 lowercase hex digits: the sum, wrapping modulo 2^64, of the IEEE-754 bit
                      patterns (as unsigned 64-bit integers) of every number converted to the nearest
                      double and then added to +0.0 (so -0 and 0 count alike). An integer a library
                      keeps as int64/uint64/bignum is converted with round-to-nearest (exactly what a
                      correctly rounded parse of its text gives); a float is the library's own parse.
                      Order-independent, so hash-ordered objects give the same sum, and exact, so
                      one wrongly rounded float changes it.

For a batch (.ndjson, one document per line) every count and sum runs over all the documents.

typed: the input decoded into statically typed structures mirroring serde-rs/json-benchmark's
(src/copy/twitter.rs, citm_catalog.rs, canada.rs), with these simplifications every language can
express: string enums, Color and *_id_str ids are plain strings; the always-null fields (geo,
coordinates, place, contributors; description, subjectCode, subtitle, name, seatMapImage) are
nullable strings; empty::Array fields (symbols, blockIds) are lists of strings; (u8, u8) indices are
lists of integers; Option<T> is a nullable or absent T; Box<Status> a nullable reference; maps keyed by
ids are string-keyed maps; canada's coordinates are doubles (json-benchmark uses f32), [lon, lat]
pairs as 2-element lists; search_metadata.completed_in is a double. Integer widths: u64 for LongId,
max_id, since_id, start (citm); u32 or wider for the rest (any signed 64-bit type is fine). Every
field is decoded; unknown fields would be ignored but there are none.

  twitter        check: <statuses> <sum of status.id> <sum of status.user.followers_count>
                        <statuses with a retweeted_status> <hashtags in status.entities>
                        <code points of status.text> <media in status.entities (absent = 0)>
                        <sum of status.user.entities.description.urls lengths>
  citm_catalog   check: <events> <sum of event.id> <performances> <sum of performance.id>
                        <sum of prices[*].amount> <seatCategories[*].areas> <code points of event names>
                        <sum of topicSubTopics list lengths>
  canada         check: <features> <rings> <points> <numsum of every coordinate> <code points of
                        every properties value>

  (all over top-level statuses only, not retweeted ones; sums of ids wrap modulo 2^64, decimal)

query (on-demand / selective extraction; only these values are read):

  twitter        check: <statuses> <sum of statuses[*].user.followers_count>
                        <count of statuses[*].entities.hashtags[*]>
  citm_catalog   check: <performances> <sum of performances[*].id>
  canada         check: <coordinate pairs in features[*].geometry.coordinates[*][*]>
                        <numsum of each pair's first value (the longitude)>
"""
import json
import struct
import sys

MASK = (1 << 64) - 1


def bits(value):
    """The bit pattern of the nearest double to a number, -0 counted as +0"""
    return struct.unpack("<Q", struct.pack("<d", float(value) + 0.0))[0]


class Tally:
    def __init__(self):
        self.objects = self.arrays = self.keys = self.strings = self.numbers = 0
        self.true = self.false = self.null = self.chars = self.numsum = 0

    def walk(self, v):
        if isinstance(v, dict):
            self.objects += 1
            for k, x in v.items():
                self.keys += 1
                self.chars += len(k)
                self.walk(x)
        elif isinstance(v, list):
            self.arrays += 1
            for x in v:
                self.walk(x)
        elif isinstance(v, str):
            self.strings += 1
            self.chars += len(v)
        elif v is True:
            self.true += 1
        elif v is False:
            self.false += 1
        elif v is None:
            self.null += 1
        else:
            self.numbers += 1
            self.numsum = (self.numsum + bits(v)) & MASK

    def line(self):
        return (f"check: {self.objects} {self.arrays} {self.keys} {self.strings} {self.numbers} {self.true} "
                f"{self.false} {self.null} {self.chars} {self.numsum:016x}")


def documents(path):
    with open(path, "rb") as f:
        data = f.read()
    if path.endswith(".ndjson"):
        return [json.loads(line) for line in data.split(b"\n") if line.strip()]
    return [json.loads(data)]


def kind(path):
    name = path.rsplit("/", 1)[-1].split(".")[0]
    return name if name in ("twitter", "citm_catalog", "canada") else None


def typed(doc, which):
    if which == "twitter":
        st = doc["statuses"]
        return "check: " + " ".join(str(x) for x in (
            len(st), sum(s["id"] for s in st) & MASK, sum(s["user"]["followers_count"] for s in st),
            sum(1 for s in st if s.get("retweeted_status") is not None),
            sum(len(s["entities"]["hashtags"]) for s in st), sum(len(s["text"]) for s in st),
            sum(len(s["entities"].get("media") or []) for s in st),
            sum(len(s["user"]["entities"]["description"]["urls"]) for s in st)))
    if which == "citm_catalog":
        ev, perf = doc["events"].values(), doc["performances"]
        return "check: " + " ".join(str(x) for x in (
            len(ev), sum(e["id"] for e in ev), len(perf), sum(p["id"] for p in perf),
            sum(pr["amount"] for p in perf for pr in p["prices"]),
            sum(len(sc["areas"]) for p in perf for sc in p["seatCategories"]),
            sum(len(e["name"]) for e in ev), sum(len(v) for v in doc["topicSubTopics"].values())))
    features = doc["features"]
    rings = [r for f in features for r in f["geometry"]["coordinates"]]
    total = 0
    for r in rings:
        for p in r:
            for x in p:
                total = (total + bits(x)) & MASK
    return "check: " + " ".join(str(x) for x in (
        len(features), len(rings), sum(len(r) for r in rings), f"{total:016x}",
        sum(len(v) for f in features for v in f["properties"].values())))


def query(doc, which):
    if which == "twitter":
        st = doc["statuses"]
        return (f"check: {len(st)} {sum(s['user']['followers_count'] for s in st)} "
                f"{sum(len(s['entities']['hashtags']) for s in st)}")
    if which == "citm_catalog":
        perf = doc["performances"]
        return f"check: {len(perf)} {sum(p['id'] for p in perf)}"
    pairs = [p for f in doc["features"] for r in f["geometry"]["coordinates"] for p in r]
    total = 0
    for p in pairs:
        total = (total + bits(p[0])) & MASK
    return f"check: {len(pairs)} {total:016x}"


def main():
    track, path = sys.argv[1], sys.argv[2]
    docs = documents(path)
    if track in ("dom", "stream"):
        t = Tally()
        for d in docs:
            t.walk(d)
        print(t.line())
    elif kind(path) is None:
        sys.exit(3)
    elif track == "typed":
        print(typed(docs[0], kind(path)))
    else:
        print(query(docs[0], kind(path)))


if __name__ == "__main__":
    main()
