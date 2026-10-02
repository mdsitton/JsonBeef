#!/bin/bash
# Runs every JSON implementation on every input of each track and prints results.md: per track a
# table of parsing speed (MB/s of input, higher is better), a table of peak RSS and, for the batch
# inputs, ns per document. Rows are inputs, columns implementations, grouped by language (the first
# row names each column's language). The four tracks are never mixed in one table:
#
#   dom     JSON into the library's generic value tree (parse, then release it)
#   typed   JSON into statically known structs/classes (twitter, citm_catalog, canada only)
#   stream  one pass over every token/event without building a tree: every key and string decoded,
#           every number converted to a double
#   query   on-demand / selective: a few fields extracted from a large document by an API that skips
#           the rest (twitter, citm_catalog, canada only; libraries without such an API are absent,
#           never emulated with a full tree)
#
# Measurement rule, shared by every harness (c/bench.h, cpp, rust, go, java, cs, python, js, perl, lua,
# zig, beef):
#   1. Warm up: run the operation for at least 1 s (at least once), for native code and JITs alike.
#   2. Sample: time single operations until at least N samples (default 5) were taken and at least
#      60% of them lie within ±10% of their median ("converged"), or 10 s of measuring or 1000
#      samples have passed ("capped"). Report the median sample.
#   3. Repeat: run each cell REPEATS times (default 3) in fresh processes and take the median, since
#      memory layout, hash seeds and CPU clocks differ between processes.
# Warm steady state only: cold start (process start-up, JIT warm-up, first-parse costs) is out of scope.
# One operation parses the input once; a batch input (.ndjson) is split into lines before timing and
# one operation parses every line as its own document. Every harness first prints a check line
# (defined in reference.py), compared with reference.py's (Python's json module). FAIL: the parser
# rejected the (valid) input, crashed, or its check line differs. DNF: a run did not finish within
# LIMIT seconds (default 60); it is not waited out. n/a: the implementation lacks the mode for that
# input (the harness exits 3).
# Peak RSS: every cell's process runs under bin/maxrss, which reports the ru_maxrss wait4 returns for
# it (the /usr/bin/time -f %M figure): the whole process at its peak, so it includes the runtime, the
# input held in memory and, for garbage-collected runtimes, whatever the collector let accumulate.
#
# Setup: ./fetch.sh && ./build.sh && ./gen-inputs.py
# Usage: run.sh [min-samples] [input names...]      (TRACKS='dom stream' limits the tracks)
# A full run prints results.md (save it: ./run.sh > results.md, then ./plot.py). With ONLY (merge.sh),
# for example ONLY='yyjson|simdjson.*' ./run.sh, only the matching implementations are measured and
# results.md (or the file RESULTS names) is updated in place; inputs not named keep their saved rows. JsonBeef's own columns go
# in the same way once it has a parser (ONLY='JsonBeef.*').
# Benchmarks need a quiet machine: run.sh refuses to start when the 1-minute load average is above 2
# (FORCE=1 runs anyway, for smoke tests; the output then says the figures are not comparable).
set -uo pipefail
C="$(cd "$(dirname "$0")" && pwd)"
B="$C/bin"
PY="$C/python/.venv/bin/python"
source "$C/merge.sh"

load=$(cut -d' ' -f1 /proc/loadavg)
loaded=$(awk -v l="$load" 'BEGIN { print (l > 2) ? 1 : 0 }')
if [ -z "${FORCE:-}" ] && [ -z "${MERGE_CHILD:-}" ] && [ "$loaded" = 1 ]; then
	echo "Load average is $load: close other work and rerun (or FORCE=1 to measure anyway)" >&2
	exit 1
fi
merge_into "${RESULTS:-$C/results.md}" "$@"
N="${1:-5}"
shift || true
REPEATS="${REPEATS:-3}"
LIMIT="${LIMIT:-60}"
TRACKS="${TRACKS:-dom typed stream query}"

all_inputs=(twitter twitterescaped citm_catalog canada github_events gsoc-2018 mesh numbers marine_ik
	tiny rest records strings integers floats events)
typed_inputs=(twitter citm_catalog canada)
batch_inputs=(tiny rest events)
if [ $# -gt 0 ]; then
	requested=" $* "
else
	requested=" ${all_inputs[*]} "
fi

input_path() { # name
	if [ -f "$C/inputs/$1.ndjson" ]; then echo "$C/inputs/$1.ndjson"; else echo "$C/inputs/$1.json"; fi
}

# The implementations of each track: name|language|command prefix (the harness takes <input>
# <min-samples> after it). Grouped by language, in this language order.
JS="$C/js/bench.mjs"
PL="$C/perl/bench.pl"
LUA="$C/lua/bench.lua"
DOM=(
	"yyjson|C|$B/yyjson dom"
	"cJSON|C|$B/cjson dom"
	"json-c|C|$B/json-c dom"
	"Jansson|C|$B/jansson dom"
	"YAJL tree|C|$B/yajl tree"
	"simdjson DOM|C++|$B/simdjson dom"
	"RapidJSON|C++|$B/rapidjson dom"
	"RapidJSON full-precision|C++|$B/rapidjson dom-full"
	"RapidJSON in-situ|C++|$B/rapidjson insitu"
	"nlohmann/json|C++|$B/nlohmann dom"
	"glaze generic|C++|$B/glaze dom"
	"serde_json Value|Rust|$B/rust-jsonbench serde_json-value"
	"serde_json Value float_roundtrip|Rust|$B/rust-jsonbench-float-roundtrip serde_json-value"
	"sonic-rs Value|Rust|$B/rust-jsonbench sonic-rs-value"
	"simd-json owned|Rust|$B/rust-jsonbench simd-json-owned"
	"simd-json borrowed|Rust|$B/rust-jsonbench simd-json-borrowed"
	"jiter JsonValue|Rust|$B/rust-jsonbench jiter-value"
	"encoding/json any|Go|$B/go-jsonbench json-any"
	"json/v2 any|Go|$B/go-jsonbench jsonv2-any"
	"sonic any|Go|$B/go-jsonbench sonic-any"
	"go-json any|Go|$B/go-jsonbench gojson-any"
	"jsoniter any|Go|$B/go-jsonbench jsoniter-any"
	"segmentio any|Go|$B/go-jsonbench segmentio-any"
	"Jackson tree|Java|$B/java/bin/jsonbench jackson-tree"
	"fastjson2 JSONObject|Java|$B/java/bin/jsonbench fastjson2-object"
	"Gson tree|Java|$B/java/bin/jsonbench gson-tree"
	"DSL-JSON Object|Java|$B/java/bin/jsonbench dsljson-object"
	"JsonDocument|C#|$B/jsonbench-cs/JsonBench jsondocument"
	"JsonNode|C#|$B/jsonbench-cs/JsonBench jsonnode"
	"Newtonsoft JToken|C#|$B/jsonbench-cs/JsonBench newtonsoft-jtoken"
	"json (Python)|Python|$PY $C/python/bench.py json"
	"orjson|Python|$PY $C/python/bench.py orjson"
	"msgspec|Python|$PY $C/python/bench.py msgspec"
	"python-rapidjson|Python|$PY $C/python/bench.py rapidjson"
	"pysimdjson|Python|$PY $C/python/bench.py pysimdjson"
	"JSON.parse (Node)|JavaScript|node $JS json-parse"
	"JSON.parse (Bun)|JavaScript|$C/deps/bun/bun $JS json-parse"
	"JSON.parse (Deno)|JavaScript|$C/deps/deno/deno run --allow-read $JS json-parse"
	"simdjson_nodejs|JavaScript|node $JS simdjson"
	"Cpanel::JSON::XS|Perl|perl $PL cpanel"
	"JSON::XS|Perl|perl $PL jsonxs"
	"JSON::PP|Perl|perl $PL jsonpp"
	"lua-cjson (LuaJIT)|Lua|luajit $LUA cjson"
	"lua-cjson (Lua 5.5)|Lua|lua5.5 $LUA cjson"
	"std.json Value|Zig|$B/zig-jsonbench value"
	"JsonBeef|Beef|$B/beef-jsonbench jsonbeef"
	"BJSON|Beef|$B/beef-jsonbench bjson"
	"StructuredData|Beef|$B/beef-jsonbench structureddata"
	"EinScott/json|Beef|$B/beef-jsonbench einscott-json"
)
TYPED=(
	"glaze|C++|$B/glaze typed"
	"serde_json|Rust|$B/rust-jsonbench serde_json-typed"
	"serde_json float_roundtrip|Rust|$B/rust-jsonbench-float-roundtrip serde_json-typed"
	"sonic-rs|Rust|$B/rust-jsonbench sonic-rs-typed"
	"simd-json|Rust|$B/rust-jsonbench simd-json-typed"
	"encoding/json|Go|$B/go-jsonbench json-typed"
	"json/v2|Go|$B/go-jsonbench jsonv2-typed"
	"sonic|Go|$B/go-jsonbench sonic-typed"
	"go-json|Go|$B/go-jsonbench gojson-typed"
	"jsoniter|Go|$B/go-jsonbench jsoniter-typed"
	"segmentio|Go|$B/go-jsonbench segmentio-typed"
	"Jackson databind|Java|$B/java/bin/jsonbench jackson-typed"
	"fastjson2|Java|$B/java/bin/jsonbench fastjson2-typed"
	"DSL-JSON|Java|$B/java/bin/jsonbench dsljson-typed"
	"Gson|Java|$B/java/bin/jsonbench gson-typed"
	"System.Text.Json (source gen)|C#|$B/jsonbench-cs/JsonBench stj-typed"
	"Newtonsoft.Json|C#|$B/jsonbench-cs/JsonBench newtonsoft-typed"
	"msgspec Struct|Python|$PY $C/python/bench.py msgspec-typed"
	"pydantic|Python|$PY $C/python/bench.py pydantic-typed"
	"std.json|Zig|$B/zig-jsonbench typed"
	"BJSON|Beef|$B/beef-jsonbench bjson-typed"
)
STREAM=(
	"YAJL|C|$B/yajl stream"
	"simdjson On-Demand|C++|$B/simdjson ondemand"
	"RapidJSON SAX|C++|$B/rapidjson sax"
	"RapidJSON SAX full-precision|C++|$B/rapidjson sax-full"
	"nlohmann/json SAX|C++|$B/nlohmann sax"
	"serde_json visitor|Rust|$B/rust-jsonbench serde_json-visitor"
	"serde_json visitor float_roundtrip|Rust|$B/rust-jsonbench-float-roundtrip serde_json-visitor"
	"jiter|Rust|$B/rust-jsonbench jiter-iter"
	"encoding/json Token|Go|$B/go-jsonbench json-token"
	"jsontext|Go|$B/go-jsonbench jsontext"
	"jsoniter Iterator|Go|$B/go-jsonbench jsoniter-iter"
	"Jackson JsonParser|Java|$B/java/bin/jsonbench jackson-stream"
	"Gson JsonReader|Java|$B/java/bin/jsonbench gson-stream"
	"fastjson2 JSONReader|Java|$B/java/bin/jsonbench fastjson2-stream"
	"Utf8JsonReader|C#|$B/jsonbench-cs/JsonBench utf8jsonreader"
	"Newtonsoft JsonTextReader|C#|$B/jsonbench-cs/JsonBench newtonsoft-reader"
	"ijson|Python|$PY $C/python/bench.py ijson"
	"std.json Scanner|Zig|$B/zig-jsonbench scanner"
	"JsonBeef JsonReader|Beef|$B/beef-jsonbench jsonbeef-stream"
	"BJSON JsonReader|Beef|$B/beef-jsonbench bjson-stream"
)
QUERY=(
	"simdjson On-Demand|C++|$B/simdjson query"
	"glaze lazy_json|C++|$B/glaze query"
	"sonic-rs get|Rust|$B/rust-jsonbench sonic-rs-get"
	"jiter|Rust|$B/rust-jsonbench jiter-query"
	"serde_json partial struct|Rust|$B/rust-jsonbench serde_json-partial"
	"serde_json partial float_roundtrip|Rust|$B/rust-jsonbench-float-roundtrip serde_json-partial"
	"gjson|Go|$B/go-jsonbench gjson"
	"jsonparser|Go|$B/go-jsonbench jsonparser"
	"sonic get|Go|$B/go-jsonbench sonic-get"
	"encoding/json partial struct|Go|$B/go-jsonbench json-partial"
	"fastjson2 JSONPath|Java|$B/java/bin/jsonbench fastjson2-path"
	"pysimdjson lazy|Python|$PY $C/python/bench.py pysimdjson-lazy"
	"msgspec partial Struct|Python|$PY $C/python/bench.py msgspec-partial"
)

# The reference check line of an input for a track (dom and stream share one)
declare -A reference
reference_line() { # track name
	local track=$1
	[ "$track" = stream ] && track=dom
	local key="$track $2"
	if [ -z "${reference[$key]:-}" ]; then
		reference[$key]=$(python3 "$C/reference.py" "$track" "$(input_path "$2")")
	fi
	echo "${reference[$key]}"
}

median() {
	sort -g | awk '{a[NR] = $1} END {print (NR % 2) ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2}'
}

# One cell: "<MB/s> <ms/op> <peak RSS KiB>", each the median over REPEATS runs, or FAIL / DNF / n/a
cell() { # reference-line path command...
	local ref="$1" path="$2" mbps=() ms=() rss=() out status
	shift 2
	for ((r = 0; r < REPEATS; r++)); do
		out=$("$B/maxrss" timeout "$LIMIT" "$@" "$path" "$N" 2>&1)
		status=$?
		if [ $status -eq 124 ]; then echo DNF; return; fi
		if [ $status -eq 3 ]; then echo "n/a"; return; fi
		if [ $status -ne 0 ] || [ "$(grep -m1 '^check:' <<< "$out")" != "$ref" ]; then echo FAIL; return; fi
		mbps+=("$(grep -oE '[0-9.]+ MB/s' <<< "$out" | head -1 | awk '{print $1}')")
		ms+=("$(grep -oE '[0-9.]+ ms/op' <<< "$out" | head -1 | awk '{print $1}')")
		rss+=("$(grep -oE '^maxrss: [0-9]+' <<< "$out" | tail -1 | awk '{print $2}')")
	done
	echo "$(printf '%s\n' "${mbps[@]}" | median) $(printf '%s\n' "${ms[@]}" | median) $(printf '%s\n' "${rss[@]}" | median)"
}

# Documents in an input (lines of a batch)
doc_count() { # name
	local path
	path=$(input_path "$1")
	if [[ "$path" == *.ndjson ]]; then grep -c . "$path"; else echo 1; fi
}

# The three tables of a track. Measured cells are formatted per table; cells not measured in a partial
# run come from the saved results.md.
track_tables() { # track title implementations...
	local track="$1" title="$2" header="| input |" rule="|---|" langs="| *language* |" impl name lib
	shift 2
	local inputs=("${all_inputs[@]}")
	if [ "$track" = typed ] || [ "$track" = query ]; then inputs=("${typed_inputs[@]}"); fi
	for impl in "$@"; do
		IFS='|' read -r name lib _ <<< "$impl"
		header+=" $name |"
		rule+="---:|"
		langs+=" $lib |"
	done
	declare -A results
	for input in "${inputs[@]}"; do
		for impl in "$@"; do
			IFS='|' read -r name lib cmd <<< "$impl"
			if selected "$name" && [[ "$requested" == *" $input "* ]]; then
				# Word splitting of the command prefix is intended
				# shellcheck disable=SC2086
				results["$input|$name"]=$(cell "$(reference_line "$track" "$input")" "$(input_path "$input")" $cmd)
			fi
		done
	done
	local kind
	for kind in speed rss perdoc; do
		local heading
		case $kind in
		speed) heading="$title: MB/s" ;;
		rss) heading="$title: peak RSS (MiB)" ;;
		perdoc) heading="$title: ns per document (batch inputs)" ;;
		esac
		if [ $kind = perdoc ] && [ "$track" != dom ] && [ "$track" != stream ]; then continue; fi
		echo "### $heading"
		echo
		echo "$header"
		echo "$rule"
		echo "$langs"
		for input in "${inputs[@]}"; do
			if [ $kind = perdoc ] && [[ " ${batch_inputs[*]} " != *" $input "* ]]; then continue; fi
			local line="| $input |" docs
			docs=$(doc_count "$input")
			for impl in "$@"; do
				IFS='|' read -r name lib _ <<< "$impl"
				local key="$input|$name"
				if [ -z "${results[$key]+set}" ]; then
					line+=" $(saved_cell "$heading" "$input" "$name") |"
					continue
				fi
				local v="${results[$key]}"
				if [[ "$v" != [0-9]* ]]; then
					line+=" $v |"
					continue
				fi
				read -r mbps ms rss <<< "$v"
				case $kind in
				speed) line+=" $mbps |" ;;
				rss) line+=" $(awk -v k="$rss" 'BEGIN { printf "%.1f", k / 1024 }') |" ;;
				perdoc) line+=" $(awk -v ms="$ms" -v d="$docs" 'BEGIN { printf "%.0f", ms * 1e6 / d }') |" ;;
				esac
			done
			echo "$line"
		done
		echo
	done
}

# What each column is and why cells fail, printed under the tables
notes() {
	cat << 'EOF'
## Notes

Inputs (gen-inputs.py has the details and the origins): real-world files from simdjson's jsonexamples,
**twitter** 617 KB, **twitterescaped** 549 KB (all non-ASCII as \u escapes), **citm_catalog** 1.6 MB,
**canada** 2.1 MB (GeoJSON floats), **github_events** 64 KB, **gsoc-2018** 3.2 MB (long strings),
**mesh** 707 KB, **numbers** 147 KB, **marine_ik** 2.8 MB; generated, **tiny** 4.0 MB in 37,032
documents of 100-500 B, **rest** 4.0 MB in 1,972 documents of 1-10 KB, **events** 5.0 MB of NDJSON in
13,376 lines (those three are batches: one document per line, split before timing), **records** 4.3 MB
(one array of 10,000 objects), **strings** 3.0 MB (escapes, raw UTF-8, surrogate pairs), **integers**
3.0 MB (up to 2^64 - 1 and down to -2^63), **floats** 3.0 MB (long mantissas, halfway cases,
subnormals, the range's extremes). The typed and on-demand tracks use twitter, citm_catalog and canada.

Implementations (pinned in fetch.sh and the harness manifests; each harness's header comment says
exactly what its columns time):

- C (from source, -O3, generic x86-64): yyjson 0.13.0, cJSON 1.7.19, json-c 0.19, Jansson 2.15.1, YAJL
  2.1.0 (`YAJL tree` = yajl_tree; `YAJL` = its callback parser, numbers read as text and strtod'd).
- C++: simdjson 5.0.1 (`simdjson DOM` reuses one parser, its documented usage; `On-Demand` walks every
  value in the streaming track and reads only the queried fields in the on-demand track), RapidJSON
  master 24b5e7a (default flags; `full-precision` = kParseFullPrecisionFlag; `in-situ` copies the input
  into a reused buffer inside the timing first), nlohmann/json 3.12.0 (DOM and SAX), glaze 9.0.0
  (`generic` = glz::generic, numbers as double; typed via pure reflection; `lazy_json` on-demand).
- Rust 1.98.1: serde_json 1.0.151 (default features; `float_roundtrip` columns are a second build
  with that feature), sonic-rs 0.5.10, simd-json 0.18.1 (copies each document into a reused buffer
  inside the timing: it parses in place), jiter 0.17.0.
- Go 1.27.1: encoding/json, encoding/json/v2 and jsontext (standard library, no GOEXPERIMENT needed),
  bytedance/sonic 1.15.4, goccy/go-json 0.11.2, json-iterator 1.1.12, segmentio/encoding 0.5.4, gjson
  1.19.0, buger/jsonparser 1.6.1. `any` = Unmarshal into interface{} (numbers as float64);
  `partial struct` = structs holding only the queried fields. gjson, jsonparser and glaze lazy_json do
  not validate what they skip.
- Java (OpenJDK 27): Jackson 3.2.3, fastjson2 2.0.65 (floats as BigDecimal in its tree; JSONPath extract
  from the bytes), DSL-JSON 2.0.2 (typed through its annotation processor's generated converters),
  Gson 2.14.0 (its tree keeps numbers as text until read).
- C# (.NET 10.0.10): System.Text.Json (JsonDocument; JsonNode, whose children are materialized by a
  walk inside the timing because JsonNode.Parse creates them lazily; Utf8JsonReader; JsonSerializer
  with a source-generated context), Newtonsoft.Json 13.0.4 (DateParseHandling.None, otherwise date-like
  strings are rewritten; its readers decode UTF-8 inside the timing).
- Python 3.14: json, orjson 3.12.0, msgspec 0.22.0, python-rapidjson 1.25, pysimdjson 7.0.2 (`lazy` =
  Parser.parse proxies, a full simdjson tape converted only where read), ijson 3.5.1 (yajl2_c backend),
  pydantic 2.13.5 (model_validate_json, lax mode).
- JavaScript: JSON.parse on Node 26.10.0, Bun 1.4.2 and Deno 2.9.7 (the UTF-8 file is decoded to a
  string outside the timing); simdjson_nodejs 0.9.2 (Node, its parse into JavaScript objects; a 2022
  release over an old simdjson).
- Perl 5.42: Cpanel::JSON::XS 4.53, JSON::XS 4.04, JSON::PP 4.16 (the core one). Lua: lua-cjson 2.1.0.16
  on LuaJIT 2.1 and Lua 5.5.1. Zig 0.16.0: std.json (Value, typed parseFromSlice, Scanner).
- Beef (BeefBuild 0.43.6, Release): BJSON a1396c8 (tree, typed `[JsonObject]` classes, which build the
  tree first, and its JsonReader), Beef's own Beefy.utils.StructuredData, EinScott/json ab9ace5.

Why cells fail (every input is valid JSON; FAIL = rejected, crashed, or a check line that differs):

- Float conversion not correctly rounded by default (canada and floats, a last-bit difference in the
  number checksum): RapidJSON (all three default-flag columns; kParseFullPrecisionFlag fixes it),
  serde_json (without its float_roundtrip feature), DSL-JSON's typed path (canada), JSON::XS (most
  inputs with fractions; it also returns -9223372036854775808 as a string), EinScott/json (imprecise
  parser), StructuredData (fractions stored as 32-bit floats).
- Integers above INT64_MAX (integers): Jansson and ijson's yajl backend reject them; lua-cjson
  saturates them to INT64_MAX (strtoll).
- JSON::PP drops characters after some \u escape sequences (strings).
- StructuredData reads input as JSON only when it starts with `{`, or `[` followed by `{` or `"`, so it
  rejects top-level arrays of numbers. EinScott/json does not accept the `\/` escape (strings).
- n/a: BJSON's typed mapping cannot express canada's lists of lists of pairs.

Not included: Boost.JSON (needs the Boost headers, not installed, about 1 GB for the tree: over the
disk budget), DAW JSON Link (needs a hand-written mapping for each of the ~150 schema members),
zimdjson (targets Zig 0.14; does not compile with Zig 0.16: `@Type` is gone, ArrayList alignment
types changed), lua-rapidjson / lua-simdjson (not attempted), Zorbn/Json and Atma.Json (Beef: crash on
any \u escape / tokenizer only), RogueMacro json and JSON_Beef (Beef: do not build). Languages without
a toolchain here: Ruby, PHP, Swift, Dart, Nim, Crystal, Julia, R, Haskell, OCaml, Elixir/Erlang, D,
Kotlin, Scala.

Peak RSS is the whole process (runtime, the input, garbage the collector has not yet reclaimed), so
for the JVM and .NET it mostly reflects heap sizing. json-c 0.19's heap grows by about three times the
input per parse even though json_object_put reports the tree freed, so its RSS grows with the number
of runs.
EOF
}

cpu=$(grep -m1 'model name' /proc/cpuinfo | sed 's/.*: //')
if [ -n "${ONLY:-}" ]; then
	saved_preamble
	echo
	echo "Partial rerun on $(date +%F) (ONLY='$ONLY', inputs: $(echo $requested); tracks: $TRACKS; load average $load at"
	echo "the start; N=$N, REPEATS=$REPEATS, LIMIT=$LIMIT s)."
else
	echo "# JSON implementations compared"
	echo
	echo "Produced by run.sh on $(date +%F) ($cpu, Linux x86-64, single thread; load average $load at the start;"
	echo "N=$N samples minimum, REPEATS=$REPEATS processes per cell, LIMIT=$LIMIT s). Pinned versions in fetch.sh and"
	echo "the harness manifests; inputs from gen-inputs.py; check lines from reference.py. MB/s of input, higher is"
	echo "better; peak RSS of the whole process (bin/maxrss); ns per document for the batch inputs. FAIL = rejected"
	echo "valid input, crashed, or a check line that differs from reference.py's; DNF = past the time limit; n/a ="
	echo "the implementation has no such mode. Warm steady state only (cold start is out of scope)."
	if [ "$loaded" = 1 ]; then
		echo
		echo "**Measured on a loaded machine (load average $load, FORCE=1): these figures are not comparable.**"
	fi
fi
echo
for track in $TRACKS; do
	case $track in
	dom)
		echo "## DOM / untyped: JSON into the library's generic value tree"
		echo
		track_tables dom "DOM" "${DOM[@]}"
		;;
	typed)
		echo "## Typed: JSON into statically known structs"
		echo
		track_tables typed "Typed" "${TYPED[@]}"
		;;
	stream)
		echo "## Streaming: every token, no tree"
		echo
		track_tables stream "Streaming" "${STREAM[@]}"
		;;
	query)
		echo "## On-demand: a few fields from a large document"
		echo
		track_tables query "On-demand" "${QUERY[@]}"
		;;
	esac
done
notes
exit 0
