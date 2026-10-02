#!/usr/bin/env python3
"""Draws one chart per track from results.md (the Markdown tables run.sh prints; only the "MB/s" tables
are read) into the repository's docs/:

    docs/benchmark-dom.svg        DOM / untyped
    docs/benchmark-typed.svg      typed
    docs/benchmark-streaming.svg  streaming
    docs/benchmark-ondemand.svg   on-demand / selective
    docs/benchmark-table.svg      every MB/s cell of every track

    ./run.sh > results.md && ./plot.py            (or ./plot.py results-smoke.md)

Tracks are never mixed: every chart compares the implementations of one track with each other. Each
implementation's speed is the geometric mean, over the inputs both handled, of its MB/s divided by the
track's baseline's. Once results.md has columns named JsonBeef ... they are highlighted, and the first
JsonBeef column of a track becomes its baseline; until then the baseline is the track's fastest
implementation that handled every input (the highest geometric-mean MB/s). Plain SVG with its own
light/dark colors (prefers-color-scheme), so it renders crisply on GitHub in either theme. No
dependencies. Adapted from XmlBeef's and KdlBeef's bench/compare/plot.py.
"""
import math
import os
import re
import sys
import textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.environ.get("PLOT_DIR", os.path.join(HERE, "..", "..", "docs"))  # PLOT_DIR: draw elsewhere
TRACKS = (  # (heading in results.md, file suffix, chart title, what one operation is)
    ("DOM", "dom", "JSON into a generic value tree (DOM)", "parse into the library's value tree, then release it"),
    ("Typed", "typed", "JSON into typed structs", "decode into structs mirroring serde-rs/json-benchmark's"),
    ("Streaming", "streaming", "Streaming: every token, no tree", "one pass over every token, strings decoded, numbers converted"),
    ("On-demand", "ondemand", "On-demand: a few fields from a large document", "extract the queried fields, skipping the rest"),
)
REPO = {
    "yyjson": "ibireme/yyjson", "cJSON": "DaveGamble/cJSON", "json-c": "json-c/json-c", "Jansson": "akheron/jansson",
    "YAJL tree": "lloyd/yajl", "YAJL": "lloyd/yajl", "simdjson DOM": "simdjson/simdjson",
    "simdjson On-Demand": "simdjson/simdjson", "RapidJSON": "Tencent/rapidjson",
    "RapidJSON full-precision": "Tencent/rapidjson", "RapidJSON in-situ": "Tencent/rapidjson",
    "RapidJSON SAX": "Tencent/rapidjson", "RapidJSON SAX full-precision": "Tencent/rapidjson",
    "nlohmann/json": "nlohmann/json", "nlohmann/json SAX": "nlohmann/json", "glaze generic": "stephenberry/glaze",
    "glaze": "stephenberry/glaze", "glaze lazy_json": "stephenberry/glaze",
    "serde_json Value": "serde-rs/json", "serde_json": "serde-rs/json", "serde_json visitor": "serde-rs/json",
    "serde_json partial struct": "serde-rs/json", "sonic-rs Value": "cloudwego/sonic-rs", "sonic-rs": "cloudwego/sonic-rs",
    "sonic-rs get": "cloudwego/sonic-rs", "simd-json owned": "simd-lite/simd-json",
    "simd-json borrowed": "simd-lite/simd-json", "simd-json": "simd-lite/simd-json", "jiter JsonValue": "pydantic/jiter",
    "jiter": "pydantic/jiter", "encoding/json any": "Go standard library", "encoding/json": "Go standard library",
    "encoding/json Token": "Go standard library", "encoding/json partial struct": "Go standard library",
    "json/v2 any": "Go encoding/json/v2", "json/v2": "Go encoding/json/v2", "jsontext": "Go encoding/json/jsontext",
    "sonic any": "bytedance/sonic", "sonic": "bytedance/sonic", "sonic get": "bytedance/sonic",
    "go-json any": "goccy/go-json", "go-json": "goccy/go-json", "jsoniter any": "json-iterator/go",
    "jsoniter": "json-iterator/go", "jsoniter Iterator": "json-iterator/go", "segmentio any": "segmentio/encoding",
    "segmentio": "segmentio/encoding", "gjson": "tidwall/gjson", "jsonparser": "buger/jsonparser",
    "Jackson tree": "FasterXML/jackson", "Jackson databind": "FasterXML/jackson", "Jackson JsonParser": "FasterXML/jackson",
    "fastjson2 JSONObject": "alibaba/fastjson2", "fastjson2": "alibaba/fastjson2", "fastjson2 JSONReader": "alibaba/fastjson2",
    "fastjson2 JSONPath": "alibaba/fastjson2", "Gson tree": "google/gson", "Gson": "google/gson",
    "Gson JsonReader": "google/gson", "DSL-JSON Object": "ngs-doo/dsl-json", "DSL-JSON": "ngs-doo/dsl-json",
    "JsonDocument": ".NET 10 System.Text.Json", "JsonNode": ".NET 10 System.Text.Json",
    "Utf8JsonReader": ".NET 10 System.Text.Json", "System.Text.Json (source gen)": ".NET 10 System.Text.Json",
    "Newtonsoft JToken": "JamesNK/Newtonsoft.Json", "Newtonsoft.Json": "JamesNK/Newtonsoft.Json",
    "Newtonsoft JsonTextReader": "JamesNK/Newtonsoft.Json", "json (Python)": "Python 3.14 stdlib",
    "orjson": "ijl/orjson", "msgspec": "jcrist/msgspec", "msgspec Struct": "jcrist/msgspec",
    "msgspec partial Struct": "jcrist/msgspec", "python-rapidjson": "python-rapidjson/python-rapidjson",
    "pysimdjson": "TkTech/pysimdjson", "pysimdjson lazy": "TkTech/pysimdjson", "pydantic": "pydantic/pydantic",
    "ijson": "ICRAR/ijson", "JSON.parse (Node)": "Node 26 (V8)", "JSON.parse (Bun)": "Bun 1.4 (JavaScriptCore)",
    "JSON.parse (Deno)": "Deno 2.9 (V8)", "Cpanel::JSON::XS": "rurban/Cpanel-JSON-XS", "JSON::XS": "CPAN JSON::XS",
    "JSON::PP": "Perl 5.42 core", "lua-cjson (LuaJIT)": "openresty/lua-cjson", "lua-cjson (Lua 5.5)": "openresty/lua-cjson",
    "std.json Value": "Zig 0.16 std", "std.json": "Zig 0.16 std", "std.json Scanner": "Zig 0.16 std",
    "BJSON": "M0n7y5/BJSON", "BJSON JsonReader": "M0n7y5/BJSON", "StructuredData": "Beef's Beefy2D",
    "EinScott/json": "EinScott/json",
}
# Why an implementation fails some of the (valid) inputs, for its footnote; per track where it differs
FAIL_REASON = {
    "Jansson": "rejects integers above INT64_MAX",
    "RapidJSON": "default float conversion is not always correctly rounded",
    "RapidJSON in-situ": "default float conversion is not always correctly rounded",
    "RapidJSON SAX": "default float conversion is not always correctly rounded",
    "serde_json Value": "float conversion not correctly rounded without its float_roundtrip feature",
    "serde_json visitor": "float conversion not correctly rounded without its float_roundtrip feature",
    "serde_json": "float conversion not correctly rounded without its float_roundtrip feature",
    "serde_json partial struct": "float conversion not correctly rounded without its float_roundtrip feature",
    "DSL-JSON": "its typed double parsing is not correctly rounded",
    "ijson": "its yajl backend rejects integers above INT64_MAX",
    "JSON::XS": "float conversion not correctly rounded; one integer returned as a string",
    "JSON::PP": "drops characters after some \\u escape sequences",
    "lua-cjson (LuaJIT)": "integers above INT64_MAX saturate (strtoll)",
    "lua-cjson (Lua 5.5)": "integers above INT64_MAX saturate (strtoll)",
    "StructuredData": "fractions stored as 32-bit floats; top-level arrays of numbers are not read as JSON",
    "EinScott/json": "imprecise float parser; no \\/ escape",
}
SLOW_REASON = {}
NOTE = {
    "Typed:BJSON": "its List cannot hold Lists, so canada cannot be expressed (n/a)",
    "glaze lazy_json": "does not validate what it skips",
    "gjson": "does not validate what it skips",
    "jsonparser": "does not validate what it skips",
}
LIMIT = float(os.environ.get("LIMIT", "60"))
INPUTS = os.path.join(HERE, "inputs")
INPUT_LABELS = {
    "twitter": "twitter", "twitterescaped": "twitter (escaped)", "citm_catalog": "citm_catalog", "canada": "canada",
    "github_events": "github_events", "gsoc-2018": "gsoc-2018", "mesh": "mesh", "numbers": "numbers",
    "marine_ik": "marine_ik", "tiny": "tiny documents", "rest": "REST payloads", "records": "records array",
    "strings": "strings, Unicode", "integers": "integers", "floats": "hard floats", "events": "NDJSON log",
}
INPUT_HEAD = {
    "twitter": ("twitter", ""), "twitterescaped": ("twitter", "escaped"), "citm_catalog": ("citm", ""),
    "canada": ("canada", ""), "github_events": ("github", "events"), "gsoc-2018": ("gsoc", "2018"),
    "mesh": ("mesh", ""), "numbers": ("numbers", ""), "marine_ik": ("marine", "ik"), "tiny": ("tiny", "batch"),
    "rest": ("REST", "batch"), "records": ("records", ""), "strings": ("strings", ""), "integers": ("integers", ""),
    "floats": ("floats", ""), "events": ("NDJSON", "batch"),
}

W = 920
FONT = "system-ui, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"


def split(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def input_size(name):
    for ext in (".json", ".ndjson"):
        path = os.path.join(INPUTS, name + ext)
        if os.path.exists(path):
            return os.path.getsize(path)
    return 0


# (track, input, implementation) of the cells run.sh marked `~` (never settled)
UNSETTLED = set()


def read_results(path):
    """Returns {track: (members, languages, table, timeouts)}: table[input][impl] is MB/s or None (FAIL
    or DNF); an implementation with n/a (or ?) for an input has no key in that row; timeouts[(input,
    impl)] is the speed bound of a DNF cell, input size / LIMIT."""
    tracks, rows, heading = {}, None, None
    for line in open(path):
        if line.startswith("### "):
            heading = line[4:].strip()
            rows = [] if heading.endswith(": MB/s") else None
            if rows is not None:
                tracks[heading[:-len(": MB/s")]] = rows
        elif rows is not None and line.startswith("|") and not line.startswith("|---"):
            rows.append(split(line))
    out = {}
    for track, rows in tracks.items():
        if not rows:
            continue
        members = rows[0][1:]
        languages = {}
        table, timeouts = {}, {}
        for cells in rows[1:]:
            if cells[0] == "*language*":
                languages = dict(zip(members, cells[1:]))
                continue
            name = cells[0]
            row = table.setdefault(name, {})
            for p, v in zip(members, cells[1:]):
                if v in ("n/a", "?"):
                    continue
                if v.endswith("~"):  # run.sh: the cell never settled; plotted, with a footnote
                    v = v[:-1]
                    UNSETTLED.add((track, name, p))
                row[p] = float(v) if re.match(r"^[0-9.]+$", v) else None
                if v == "DNF":
                    timeouts[(name, p)] = input_size(name) / 1048576.0 / LIMIT
        out[track] = (members, languages, table, timeouts)
    return out


def ours(p):
    return p.startswith("JsonBeef")


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, s, cls, anchor="start"):
    return f'<text x="{x:.1f}" y="{y:.1f}" class="{cls}" text-anchor="{anchor}">{esc(s)}</text>'


def geomean(values):
    return math.exp(sum(math.log(v) for v in values) / len(values)) if values else 0.0


def baseline(members, table):
    """The first JsonBeef column, else the fastest implementation that handled every input"""
    for p in members:
        if ours(p):
            return p
    complete = [p for p in members if all(row.get(p) for row in table.values())]
    candidates = complete or members
    return max(candidates, key=lambda p: geomean([row[p] for row in table.values() if row.get(p)]))


def relative_speeds(members, table, timeouts, base):
    """Each implementation's speed relative to the baseline: the geometric mean over the inputs both
    handled of its MB/s divided by the baseline's. A timed-out input counts at its speed bound, which
    favors that implementation; failed inputs are left out. Returns {impl: (ratio, inputs)}."""
    speeds = {}
    for p in members:
        ratios = []
        for name, row in table.items():
            v = row.get(p) if row.get(p) is not None else timeouts.get((name, p))
            if v and row.get(base):
                ratios.append(v / row[base])
        if ratios:
            speeds[p] = (geomean(ratios), len(ratios))
    return speeds


def listing(items):
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def caveat(p, table, timeouts, track=""):
    """Footnote text for an implementation that failed or timed out on some inputs, or has a note"""
    failed = [INPUT_LABELS.get(i, i) for i, row in table.items() if p in row and row[p] is None and (i, p) not in timeouts]
    slow = [INPUT_LABELS.get(i, i) for i, row in table.items() if (i, p) in timeouts]
    parts = []
    if failed:
        reason = FAIL_REASON.get(p, "rejected valid input or a wrong check")
        passed = [INPUT_LABELS.get(i, i) for i, row in table.items() if row.get(p)]
        what = "every input" if not passed else "all but " + listing(passed) if len(failed) > len(passed) else listing(failed)
        parts.append(f"failed {what} ({reason})")
    if slow:
        why = f"{SLOW_REASON[p]}; " if p in SLOW_REASON else ""
        parts.append(f"did not finish {listing(slow)} within {LIMIT:.0f} s ({why}counted at that bound)")
    noisy = [INPUT_LABELS.get(i, i) for (t, i, q) in sorted(UNSETTLED) if q == p and (not track or t == track)]
    if noisy:
        parts.append(f"did not settle on {listing(noisy)} (noisy figures)")
    note = NOTE.get(f"{track}:{p}", NOTE.get(p))  # "Track:name" keys apply to one track only
    if note:
        parts.append(note)
    return f"{p} " + "; ".join(parts) + "." if parts else None


def relative_panel(title, subtitle, members, languages, table, timeouts, base, top, footnotes, track):
    """Horizontal bars: average speed relative to the baseline, fastest first. Implementations with
    caveats get a footnote; those that failed every input are listed under the bars."""
    out = []
    name_x, bar_x, bar_w = 112, 500, 200
    row_h, bar_h = 24, 15
    y = top
    out.append(text(40, y, title, "title"))
    y += 22
    out.append(text(40, y, subtitle, "subtitle"))
    y += 16
    speeds = relative_speeds(members, table, timeouts, base)
    peak = max([1.0] + [r for r, _ in speeds.values()])
    y += 8
    for p in sorted(speeds, key=lambda p: -speeds[p][0]):
        ratio, _ = speeds[p]
        cy = y + row_h / 2
        name = p
        note_text = caveat(p, table, timeouts, track)
        if note_text:
            name += "*"
            footnotes.setdefault(note_text, "* " + note_text)
        highlight = ours(p) or p == base
        out.append(text(40, cy + 5, languages.get(p, ""), "lang"))
        out.append(f'<text x="{name_x}" y="{cy + 5:.1f}"><tspan class="{"label ours" if highlight else "label"}">{esc(name)}</tspan>'
                   f'<tspan class="repo" dx="8">{esc(REPO.get(p, ""))}</tspan></text>')
        w = max(2.0, bar_w * ratio / peak)
        out.append(f'<rect x="{bar_x}" y="{cy - bar_h / 2:.1f}" width="{w:.1f}" height="{bar_h}" rx="3" class="{"bar-ours" if highlight else "bar"}"/>')
        shown = f"{ratio:.2f}×" if ratio >= 0.1 else f"{ratio:.3f}×"
        if p == base:
            note = "baseline"
        elif ratio > 1:
            note = f"{ratio:.1f}× faster"
        else:
            note = f"{1 / ratio:.0f}× slower" if 1 / ratio >= 10 else f"{1 / ratio:.1f}× slower"
        out.append(f'<text x="{bar_x + w + 8:.1f}" y="{cy + 5:.1f}" class="small">'
                   f'<tspan class="{"value ours" if highlight else "value"}">{shown}</tspan>'
                   f'<tspan class="note-plain" dx="8">{esc(note)}</tspan></text>')
        y += row_h
    unmeasured = [p for p in members if p not in speeds]
    if unmeasured:
        y += 18
        out.append(text(40, y, f"No comparable figure (failed every input): {', '.join(unmeasured)}", "footnote"))
        y += 4
    return out, y


def fastest_panel(members, languages, table, top):
    """Per input: the three fastest implementations (and JsonBeef's, once it has columns) as labeled
    MB/s bars, each input's bars scaled to its own fastest."""
    out = []
    label_x, x, bar_w, bar_h, gap = 190, 210, 330, 12, 3
    y = top
    out.append(text(40, y, "The fastest per input", "title"))
    y += 22
    out.append(text(40, y, "MB/s · the three fastest implementations of this track on each input · bars scaled per input", "subtitle"))
    y += 22
    for name, results in table.items():
        valid = {p: v for p, v in results.items() if v and p in members}
        if not valid:
            continue
        picks = sorted(valid.items(), key=lambda kv: -kv[1])[:3]
        picks += [(p, v) for p, v in valid.items() if ours(p) and (p, v) not in picks]
        row_h = len(picks) * (bar_h + gap) + 12
        out.append(f'<line x1="40" y1="{y:.1f}" x2="{W - 40}" y2="{y:.1f}" class="rule"/>')
        out.append(text(label_x, y + row_h / 2 + 5, INPUT_LABELS.get(name, name), "label", "end"))
        peak = max(v for _, v in picks)
        by = y + 6
        for lib, v in picks:
            w = max(2.0, bar_w * v / peak)
            is_ours = ours(lib)
            out.append(f'<rect x="{x}" y="{by:.1f}" width="{w:.1f}" height="{bar_h}" rx="2" class="{"bar-ours" if is_ours else "bar"}"/>')
            value = f"{v:.1f}" if v < 100 else f"{v:.0f}"
            out.append(f'<text x="{x + w + 7:.1f}" y="{by + 10:.1f}" class="small">'
                       f'<tspan class="{"value ours" if is_ours else "value"}">{value}</tspan>'
                       f'<tspan class="{"libname ours" if is_ours else "libname"}" dx="6">{esc(lib)}</tspan>'
                       f'<tspan class="note-plain" dx="6">{esc(languages.get(lib, ""))}</tspan></text>')
            by += bar_h + gap
        y += row_h
    out.append(f'<line x1="40" y1="{y:.1f}" x2="{W - 40}" y2="{y:.1f}" class="rule"/>')
    return out, y + 8


def table_panel(results, top):
    """Every MB/s cell: one section per track, one row per implementation (ordered by its speed
    relative to the track's baseline), one column per input. The fastest cell of each column within its
    track is bold, and every cell is shaded by its speed relative to that best (log scale)."""
    out = []
    name_x, first_col, col_w, row_h = 40, 470, 58, 26
    inputs = []
    for _, _, table, _ in results.values():
        inputs += [i for i in table if i not in inputs]
    width = first_col + len(inputs) * col_w + 40
    y = top
    out.append(text(40, y, "Full results", "title"))
    y += 22
    out.append(text(40, y, "MB/s of input, higher is better · bold = best of its track on that input · shading = relative to "
                    "that best (log scale) · blank = not in that track", "subtitle"))
    y += 34
    for c, name in enumerate(inputs):
        top_line, bottom_line = INPUT_HEAD.get(name, (name, ""))
        cx = first_col + c * col_w + col_w / 2
        if bottom_line:
            out.append(text(cx, y, top_line, "colhead", "middle"))
            out.append(text(cx, y + 14, bottom_line, "colhead", "middle"))
        else:
            out.append(text(cx, y + 14, top_line, "colhead", "middle"))
    y += 20
    for heading, _, title, _ in TRACKS:
        if heading not in results:
            continue
        members, languages, table, timeouts = results[heading]
        base = baseline(members, table)
        speeds = relative_speeds(members, table, timeouts, base)
        y += 20
        out.append(text(name_x, y, title.upper(), "group"))
        y += 6
        best = {i: max((table[i].get(p) or 0 for p in members), default=0) for i in table}
        for p in sorted(members, key=lambda p: -speeds.get(p, (0, 0))[0]):
            highlight = ours(p)
            out.append(f'<line x1="40" y1="{y:.1f}" x2="{width - 40}" y2="{y:.1f}" class="rule"/>')
            if highlight:
                out.append(f'<rect x="40" y="{y:.1f}" width="{width - 80}" height="{row_h}" class="row-ours"/>')
            mid = y + row_h / 2
            star = "*" if caveat(p, table, timeouts, heading) else ""
            out.append(f'<text x="{name_x}" y="{mid + 4.5:.1f}"><tspan class="lang">{esc(languages.get(p, ""))}</tspan>'
                       f'<tspan x="{name_x + 72}" class="{"label ours" if highlight else "label"}">{esc(p + star)}</tspan>'
                       f'<tspan class="repo" dx="7">{esc(REPO.get(p, ""))}</tspan></text>')
            for c, name in enumerate(inputs):
                x = first_col + c * col_w
                if name not in table:
                    continue
                if p not in table[name]:
                    out.append(text(x + col_w - 7, mid + 4, "n/a", "cell-missing", "end"))
                    continue
                v = table[name][p]
                if v is None:
                    label = "DNF" if (name, p) in timeouts else "FAIL"
                    out.append(text(x + col_w - 6, mid + 4, label, "cell-missing", "end"))
                    continue
                level = max(0.0, 1.0 + math.log10(v / best[name]) / 2.0)
                out.append(f'<rect x="{x + 2}" y="{y + 3:.1f}" width="{col_w - 4}" height="{row_h - 6}" rx="3" '
                           f'class="heat" fill-opacity="{0.06 + 0.34 * level:.2f}"/>')
                cls = "cell" + (" best" if v == best[name] else "") + (" ours" if highlight else "")
                out.append(text(x + col_w - 7, mid + 4.5, f"{v:.1f}" if v < 100 else f"{v:.0f}", cls, "end"))
            y += row_h
        out.append(f'<line x1="40" y1="{y:.1f}" x2="{width - 40}" y2="{y:.1f}" class="rule"/>')
    y += 22
    out.append(text(40, y, f"FAIL = rejected valid input, crashed or a wrong check · DNF = over {LIMIT:.0f} s · "
                    "n/a = no such mode · * see the notes in results.md", "footnote"))
    return out, y + 8, width


def style():
    return f"""
  <style>
    svg {{ font-family: {FONT}; }}
    .bg {{ fill: #ffffff; }}
    .title {{ font-size: 19px; font-weight: 650; fill: #1f2328; }}
    .subtitle, .footer, .axis {{ font-size: 12.5px; fill: #656d76; }}
    .group {{ font-size: 11px; font-weight: 650; letter-spacing: 0.08em; fill: #656d76; }}
    .label {{ font-size: 13.5px; fill: #1f2328; }}
    .lang {{ font-size: 11px; fill: #8c959f; }}
    .ours {{ font-weight: 700; }}
    .value {{ font-size: 12.5px; fill: #424a53; font-variant-numeric: tabular-nums; }}
    .value.ours {{ fill: #c2410c; }}
    .small {{ font-size: 12px; fill: #424a53; }}
    .note-plain {{ fill: #8c959f; }}
    .footnote {{ font-size: 12px; fill: #656d76; }}
    .repo {{ font-size: 11.5px; fill: #8c959f; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
    .bar {{ fill: #afb8c1; }}
    .bar-ours {{ fill: #ea580c; }}
    .rule {{ stroke: #d8dee4; stroke-width: 1; }}
    .libname {{ fill: #656d76; }}
    .libname.ours {{ fill: #c2410c; font-weight: 650; }}
    .colhead {{ font-size: 11px; font-weight: 600; fill: #424a53; }}
    .cell {{ font-size: 11.5px; fill: #424a53; font-variant-numeric: tabular-nums; }}
    .cell.best {{ font-weight: 700; fill: #1f2328; }}
    .cell.ours {{ fill: #c2410c; }}
    .cell-missing {{ font-size: 10px; fill: #8c959f; }}
    .heat {{ fill: #2da44e; }}
    .row-ours {{ fill: #ea580c; fill-opacity: 0.07; }}
    @media (prefers-color-scheme: dark) {{
      .bg {{ fill: #0d1117; }}
      .title, .label {{ fill: #e6edf3; }}
      .subtitle, .footer, .axis, .group {{ fill: #8d96a0; }}
      .lang, .note-plain {{ fill: #6e7681; }}
      .footnote {{ fill: #8d96a0; }}
      .repo {{ fill: #6e7681; }}
      .value, .small {{ fill: #c9d1d9; }}
      .value.ours {{ fill: #fb923c; }}
      .bar {{ fill: #3d444d; }}
      .bar-ours {{ fill: #f97316; }}
      .rule {{ stroke: #262c36; }}
      .libname {{ fill: #8d96a0; }}
      .libname.ours {{ fill: #fb923c; }}
      .colhead {{ fill: #c9d1d9; }}
      .cell {{ fill: #c9d1d9; }}
      .cell.best {{ fill: #f0f6fc; }}
      .cell.ours {{ fill: #fb923c; }}
      .cell-missing {{ fill: #6e7681; }}
      .heat {{ fill: #3fb950; }}
      .row-ours {{ fill: #f97316; fill-opacity: 0.10; }}
    }}
  </style>"""


def write_svg(path, width, height, body, label):
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" '
           f'aria-label="{esc(label)}">', style(),
           f'<rect class="bg" x="0" y="0" width="{width}" height="{height}" rx="10"/>']
    svg += body + ["</svg>"]
    with open(path, "w") as f:
        f.write("\n".join(svg) + "\n")
    print(f"wrote {os.path.relpath(path)}")


FOOTER = ("Linux x86-64, single thread, warm · 1 s warm-up, then samples until 60% are within ±10% of their median · "
          "median of 3 processes · bench/compare")


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "results.md")
    results = read_results(source)
    os.makedirs(DOCS, exist_ok=True)
    for heading, suffix, title, operation in TRACKS:
        if heading not in results:
            continue
        members, languages, table, timeouts = results[heading]
        base = baseline(members, table)
        footnotes = {}
        body, y = relative_panel(
            f"{title}: speed relative to {base}",
            f"one operation: {operation} · geometric mean over the inputs both handled of MB/s ÷ {base}'s · higher is better",
            members, languages, table, timeouts, base, 44, footnotes, heading)
        panel, y = fastest_panel(members, languages, table, y + 50)
        body += panel
        for note in footnotes.values():
            for i, line in enumerate(textwrap.wrap(note, 135)):
                y += 20 if i == 0 else 16
                body.append(text(40 if i == 0 else 50, y, line, "footnote"))
        height = y + 44
        body.append(text(40, height - 16, FOOTER, "footer"))
        write_svg(os.path.join(DOCS, f"benchmark-{suffix}.svg"), W, height, body,
                  f"JSON {title}: throughput of existing implementations")
    body, y, width = table_panel(results, 44)
    write_svg(os.path.join(DOCS, "benchmark-table.svg"), width, y + 24, body,
              "Full JSON benchmark results: MB/s per implementation, input and track")


if __name__ == "__main__":
    main()
