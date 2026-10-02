"""Python JSON benchmark: bench.py <variant> <input> <min-samples>

DOM (into Python dicts, lists, str, int, float, bool, None):
  json            - the standard library's json.loads (its C accelerator), over bytes.
  orjson          - orjson.loads (Rust, yyjson-derived reader) over bytes.
  msgspec         - msgspec.json.decode with no type (untyped) over bytes.
  rapidjson       - python-rapidjson's rapidjson.loads (RapidJSON) over bytes, default modes.
  pysimdjson      - pysimdjson's simdjson.loads: simdjson's DOM converted into Python objects.
Typed (the json-benchmark schema of ../reference.py; twitter, citm_catalog and canada only):
  msgspec-typed   - msgspec.json.Decoder(type=<msgspec.Struct classes>).decode.
  pydantic-typed  - pydantic v2 BaseModel.model_validate_json (pydantic-core, Rust), default (lax) mode.
  Both use the same class definitions (SCHEMA below, executed once with each base class).
Streaming:
  ijson           - ijson.basic_parse over the bytes with the yajl2_c backend (ijson's C extension
                    over YAJL), use_float=True: every event read, keys and strings measured, every
                    number converted to float.
Query (the selective extraction of ../reference.py; twitter, citm_catalog and canada only):
  pysimdjson-lazy - simdjson.Parser().parse into simdjson's DOM, read through pysimdjson's lazy
                    Object/Array proxies: only the queried values become Python objects.
  msgspec-partial - msgspec Structs holding only the queried fields (msgspec skips the rest).

A .ndjson input is a batch: its lines are split before timing and each is parsed as its own document;
one operation parses every line once. Prints the check line (see ../reference.py) first; exits 1 on a
parse error, 3 (n/a) when a typed or query variant is given another input. Timings follow the shared
rule (see measure and ../run.sh).
"""
import os
import struct
import sys
import time
import types

MASK = (1 << 64) - 1


def measure(min_samples, op):
    warm = time.perf_counter_ns()
    while True:
        op()
        if time.perf_counter_ns() - warm >= 1_000_000_000:
            break
    start = time.perf_counter_ns()
    samples = []
    while True:
        t0 = time.perf_counter_ns()
        op()
        samples.append(time.perf_counter_ns() - t0)
        ordered = sorted(samples)
        n = len(ordered)
        median = ordered[n // 2] if n % 2 else (ordered[n // 2 - 1] + ordered[n // 2]) / 2
        if n >= min_samples and sum(median * 0.9 <= s <= median * 1.1 for s in samples) >= 0.6 * n:
            return median, n, True
        if n >= 1000 or time.perf_counter_ns() - start >= 10_000_000_000:
            return median, n, False


def bits(value):
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


# ---- The typed schema (json-benchmark's, simplified as ../reference.py describes) ----

SCHEMA = '''
from typing import Optional

class Url(Base):
    url: str
    expanded_url: str
    display_url: str
    indices: list[int]

class UserUrl(Base):
    urls: list[Url]

class UserEntitiesDescription(Base):
    urls: list[Url]

class UserEntities(Base):
    description: UserEntitiesDescription
    url: Optional[UserUrl] = None

class User(Base):
    id: int
    id_str: str
    name: str
    screen_name: str
    location: str
    description: str
    entities: UserEntities
    protected: bool
    followers_count: int
    friends_count: int
    listed_count: int
    created_at: str
    favourites_count: int
    geo_enabled: bool
    verified: bool
    statuses_count: int
    lang: str
    contributors_enabled: bool
    is_translator: bool
    is_translation_enabled: bool
    profile_background_color: str
    profile_background_image_url: str
    profile_background_image_url_https: str
    profile_background_tile: bool
    profile_image_url: str
    profile_image_url_https: str
    profile_link_color: str
    profile_sidebar_border_color: str
    profile_sidebar_fill_color: str
    profile_text_color: str
    profile_use_background_image: bool
    default_profile: bool
    default_profile_image: bool
    following: bool
    follow_request_sent: bool
    notifications: bool
    url: Optional[str] = None
    utc_offset: Optional[int] = None
    time_zone: Optional[str] = None
    profile_banner_url: Optional[str] = None

class Hashtag(Base):
    text: str
    indices: list[int]

class UserMention(Base):
    screen_name: str
    name: str
    id: int
    id_str: str
    indices: list[int]

class Size(Base):
    w: int
    h: int
    resize: str

class Sizes(Base):
    medium: Size
    small: Size
    thumb: Size
    large: Size

class Media(Base):
    id: int
    id_str: str
    indices: list[int]
    media_url: str
    media_url_https: str
    url: str
    display_url: str
    expanded_url: str
    type: str
    sizes: Sizes
    source_status_id: Optional[int] = None
    source_status_id_str: Optional[str] = None

class StatusEntities(Base):
    hashtags: list[Hashtag]
    symbols: list[str]
    urls: list[Url]
    user_mentions: list[UserMention]
    media: Optional[list[Media]] = None

class Metadata(Base):
    result_type: str
    iso_language_code: str

class Status(Base):
    metadata: Metadata
    created_at: str
    id: int
    id_str: str
    text: str
    source: str
    truncated: bool
    user: User
    retweet_count: int
    favorite_count: int
    entities: StatusEntities
    favorited: bool
    retweeted: bool
    lang: str
    in_reply_to_status_id: Optional[int] = None
    in_reply_to_status_id_str: Optional[str] = None
    in_reply_to_user_id: Optional[int] = None
    in_reply_to_user_id_str: Optional[str] = None
    in_reply_to_screen_name: Optional[str] = None
    geo: Optional[str] = None
    coordinates: Optional[str] = None
    place: Optional[str] = None
    contributors: Optional[str] = None
    retweeted_status: Optional["Status"] = None
    possibly_sensitive: Optional[bool] = None

class SearchMetadata(Base):
    completed_in: float
    max_id: int
    max_id_str: str
    next_results: str
    query: str
    refresh_url: str
    count: int
    since_id: int
    since_id_str: str

class Twitter(Base):
    statuses: list[Status]
    search_metadata: SearchMetadata

class Event(Base):
    id: int
    name: str
    subTopicIds: list[int]
    topicIds: list[int]
    description: Optional[str] = None
    logo: Optional[str] = None
    subjectCode: Optional[str] = None
    subtitle: Optional[str] = None

class Price(Base):
    amount: int
    audienceSubCategoryId: int
    seatCategoryId: int

class Area(Base):
    areaId: int
    blockIds: list[str]

class SeatCategory(Base):
    areas: list[Area]
    seatCategoryId: int

class Performance(Base):
    eventId: int
    id: int
    prices: list[Price]
    seatCategories: list[SeatCategory]
    start: int
    venueCode: str
    logo: Optional[str] = None
    name: Optional[str] = None
    seatMapImage: Optional[str] = None

class CitmCatalog(Base):
    areaNames: dict[str, str]
    audienceSubCategoryNames: dict[str, str]
    blockNames: dict[str, str]
    events: dict[str, Event]
    performances: list[Performance]
    seatCategoryNames: dict[str, str]
    subTopicNames: dict[str, str]
    subjectNames: dict[str, str]
    topicNames: dict[str, str]
    topicSubTopics: dict[str, list[int]]
    venueNames: dict[str, str]

class Geometry(Base):
    type: str
    coordinates: list[list[list[float]]]

class Feature(Base):
    type: str
    properties: dict[str, str]
    geometry: Geometry

class Canada(Base):
    type: str
    features: list[Feature]
'''

# Only the fields the queries read
PARTIAL = '''
class PUser(Base):
    followers_count: int

class PEntities(Base):
    hashtags: list[dict]

class PStatus(Base):
    user: PUser
    entities: PEntities

class PTwitter(Base):
    statuses: list[PStatus]

class PPerformance(Base):
    id: int

class PCitm(Base):
    performances: list[PPerformance]

class PGeometry(Base):
    coordinates: list[list[list[float]]]

class PFeature(Base):
    geometry: PGeometry

class PCanada(Base):
    features: list[PFeature]
'''


def schema(name, source, base):
    """Runs a schema source with `Base` bound, as a module (so forward references resolve)"""
    module = types.ModuleType(name)
    module.Base = base
    sys.modules[name] = module
    exec(source, module.__dict__)
    return module


def typed_check(doc, which):
    if which == "twitter":
        st = doc.statuses
        return "check: " + " ".join(str(x) for x in (
            len(st), sum(s.id for s in st) & MASK, sum(s.user.followers_count for s in st),
            sum(1 for s in st if s.retweeted_status is not None), sum(len(s.entities.hashtags) for s in st),
            sum(len(s.text) for s in st), sum(len(s.entities.media or []) for s in st),
            sum(len(s.user.entities.description.urls) for s in st)))
    if which == "citm_catalog":
        ev, perf = doc.events.values(), doc.performances
        return "check: " + " ".join(str(x) for x in (
            len(ev), sum(e.id for e in ev), len(perf), sum(p.id for p in perf),
            sum(pr.amount for p in perf for pr in p.prices), sum(len(sc.areas) for p in perf for sc in p.seatCategories),
            sum(len(e.name) for e in ev), sum(len(v) for v in doc.topicSubTopics.values())))
    rings = [r for f in doc.features for r in f.geometry.coordinates]
    total = 0
    for r in rings:
        for p in r:
            for x in p:
                total = (total + bits(x)) & MASK
    return "check: " + " ".join(str(x) for x in (
        len(doc.features), len(rings), sum(len(r) for r in rings), f"{total:016x}",
        sum(len(v) for f in doc.features for v in f.properties.values())))


# ---- Streaming ----

def ijson_pass(ijson, data, exact):
    """[objects, arrays, keys, strings, numbers, true, false, null, chars, numsum]: numsum is the
    bit-pattern sum when exact, else a plain float sum (the number is still converted)"""
    objects = arrays = keys = strings = numbers = t = f = null = chars = 0
    numsum = 0
    for event, value in ijson.basic_parse(data, use_float=True):
        if event == "map_key":
            keys += 1
            chars += len(value)
        elif event == "string":
            strings += 1
            chars += len(value)
        elif event == "number":
            numbers += 1
            numsum = (numsum + bits(value)) & MASK if exact else numsum + float(value)
        elif event == "start_map":
            objects += 1
        elif event == "start_array":
            arrays += 1
        elif event == "boolean":
            if value:
                t += 1
            else:
                f += 1
        elif event == "null":
            null += 1
    return [objects, arrays, keys, strings, numbers, t, f, null, chars, numsum]


# ---- Queries ----

def lazy_query(parser, data, which):
    doc = parser.parse(data)
    if which == "twitter":
        st = doc["statuses"]
        followers = hashtags = 0
        for s in st:
            followers += s.at_pointer("/user/followers_count")
            hashtags += len(s.at_pointer("/entities/hashtags"))
        return f"check: {len(st)} {followers} {hashtags}"
    if which == "citm_catalog":
        perf = doc["performances"]
        return f"check: {len(perf)} {sum(p['id'] for p in perf)}"
    pairs = total = 0
    for f in doc["features"]:
        for ring in f.at_pointer("/geometry/coordinates"):
            for pair in ring:
                pairs += 1
                total = (total + bits(pair[0])) & MASK
    return f"check: {pairs} {total:016x}"


def partial_check(doc, which):
    if which == "twitter":
        st = doc.statuses
        return (f"check: {len(st)} {sum(s.user.followers_count for s in st)} "
                f"{sum(len(s.entities.hashtags) for s in st)}")
    if which == "citm_catalog":
        return f"check: {len(doc.performances)} {sum(p.id for p in doc.performances)}"
    pairs = total = 0
    for f in doc.features:
        for ring in f.geometry.coordinates:
            for pair in ring:
                pairs += 1
                total = (total + bits(pair[0])) & MASK
    return f"check: {pairs} {total:016x}"


def main():
    if len(sys.argv) < 4:
        print("usage: bench.py <json|orjson|msgspec|rapidjson|pysimdjson|msgspec-typed|pydantic-typed|ijson|"
              "pysimdjson-lazy|msgspec-partial> <input> <min-samples>", file=sys.stderr)
        sys.exit(2)
    variant, path, min_samples = sys.argv[1], sys.argv[2], int(sys.argv[3])
    with open(path, "rb") as fh:
        data = fh.read()
    total = len(data)
    docs = [line for line in data.split(b"\n") if line.strip()] if path.endswith(".ndjson") else [data]
    base = os.path.basename(path)
    which = {"twitter.json": "twitter", "citm_catalog.json": "citm_catalog", "canada.json": "canada"}.get(base)

    try:
        if variant in ("json", "orjson", "msgspec", "rapidjson", "pysimdjson"):
            if variant == "json":
                import json
                parse = json.loads
            elif variant == "orjson":
                import orjson
                parse = orjson.loads
            elif variant == "msgspec":
                import msgspec
                parse = msgspec.json.Decoder().decode
            elif variant == "rapidjson":
                import rapidjson
                parse = rapidjson.loads
            else:
                import simdjson
                parse = simdjson.loads
            t = Tally()
            for d in docs:
                t.walk(parse(d))
            check = t.line()

            def op():
                for d in docs:
                    parse(d)
        elif variant in ("msgspec-typed", "pydantic-typed", "msgspec-partial"):
            if which is None:
                sys.exit(3)
            if variant == "pydantic-typed":
                import pydantic
                m = schema("schema_pydantic", SCHEMA, pydantic.BaseModel)
                model = {"twitter": m.Twitter, "citm_catalog": m.CitmCatalog, "canada": m.Canada}[which]
                decode = model.model_validate_json
            else:
                import msgspec
                if variant == "msgspec-typed":
                    m = schema("schema_msgspec", SCHEMA, msgspec.Struct)
                    model = {"twitter": m.Twitter, "citm_catalog": m.CitmCatalog, "canada": m.Canada}[which]
                else:
                    m = schema("schema_partial", PARTIAL, msgspec.Struct)
                    model = {"twitter": m.PTwitter, "citm_catalog": m.PCitm, "canada": m.PCanada}[which]
                decode = msgspec.json.Decoder(type=model).decode
            result = decode(data)
            check = partial_check(result, which) if variant == "msgspec-partial" else typed_check(result, which)
            del result

            def op():
                decode(data)
        elif variant == "ijson":
            import ijson
            if ijson.backend != "yajl2_c":
                print(f"ijson backend is {ijson.backend}, not yajl2_c", file=sys.stderr)
                sys.exit(1)
            c = [0] * 10
            for d in docs:
                for i, v in enumerate(ijson_pass(ijson, d, True)):
                    c[i] += v
            c[9] &= MASK
            check = "check: " + " ".join(str(v) for v in c[:9]) + f" {c[9]:016x}"

            def op():
                for d in docs:
                    ijson_pass(ijson, d, False)
        elif variant == "pysimdjson-lazy":
            if which is None:
                sys.exit(3)
            import simdjson
            parser = simdjson.Parser()
            check = lazy_query(parser, data, which)

            def op():
                lazy_query(parser, data, which)
        else:
            print("unknown variant", variant, file=sys.stderr)
            sys.exit(2)
    except Exception as e:  # every library's decode error (ijson's JSONError is not a ValueError)
        print("parse error:", e, file=sys.stderr)
        sys.exit(1)

    print(check, flush=True)
    median, n, converged = measure(min_samples, op)
    ms = median / 1e6
    print(f"{ms:.3f} ms/op {total / 1048576 / (ms / 1000):.1f} MB/s (n={n}, {'converged' if converged else 'capped'})")


if __name__ == "__main__":
    main()
