#!/bin/bash
# The real-world corpora through JsonTester (docs/test-suites.md §7, §9.6).
# Usage: bash ./test-json-corpus.sh [DIR...]     (Debug binary; simdjson-data/jsonexamples by default)
#        BIN=./build/Release_Linux64/JsonTester/JsonTester bash ./test-json-corpus.sh
#
# For every .json file:
#   - the canonical form (§9.2) from the document, from the reader's tokens, from a document built
#     from 1-byte stream reads and from tokens read 16 bytes at a time all equal the oracle's
#     (tests/tools/json-canonical.py);
#   - written compact and indented, the document reads back to the same canonical form;
#   - the compact writer is a fixed point: writing what it wrote, read back, gives the same bytes.
# And across files: twitter.json and twitterescaped.json hold the same names and strings (-strings;
# their numbers differ: the escaped copy's ids went through a double); mesh.json and mesh.pretty.json
# (its members sorted) give the same RFC 8785 output (-jcs); and JSON Pointer lookups into the
# documents agree with the oracle's, missing values included: on the document (-pointer) and on
# demand with the reader's Find (-select), from memory and from 7-byte stream reads.

BIN="${BIN:-./build/Debug_Linux64/JsonTester/JsonTester}"
SUITES="${SUITES:-tests/suites}"
ORACLE="tests/tools/json-canonical.py"
LOGFILE="test-json-corpus.log"
EXAMPLES="$SUITES/simdjson-data/jsonexamples"

if [ ! -x "$BIN" ]; then
	echo "ERROR: $BIN not found or not executable. Build first with: beefbuild"
	exit 1
fi
dirs=("$@")
if [ ${#dirs[@]} -eq 0 ]; then
	if [ ! -d "$EXAMPLES" ]; then
		echo "ERROR: $EXAMPLES not found. Fetch the suites with: bash tests/fetch-suites.sh"
		exit 1
	fi
	dirs=("$EXAMPLES")
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
: > "$LOGFILE"

failed=0
files=0
fail() {
	echo "FAIL: $1" | tee -a "$LOGFILE"
	failed=1
}

for dir in "${dirs[@]}"; do
	for f in "$dir"/*.json; do
		files=$((files + 1))
		name=$(basename "$f")
		if ! python3 "$ORACLE" "$f" > "$tmpdir/want" 2> "$tmpdir/err"; then
			fail "$name: the oracle rejects it: $(cat "$tmpdir/err")"
			continue
		fi
		for flags in "" "-events" "-stream 1" "-events -stream 16" "-rewrite" "-rewrite-pretty"; do
			if ! timeout 60 "$BIN" $flags "$f" > "$tmpdir/got" 2> "$tmpdir/err"; then
				fail "$name [$flags]: exit $?: $(head -c 300 "$tmpdir/err")"
			elif ! cmp -s "$tmpdir/got" "$tmpdir/want"; then
				fail "$name [$flags]: canonical form differs from the oracle's"
			fi
		done
		# The compact writer is a fixed point
		timeout 60 "$BIN" -compact "$f" > "$tmpdir/compact1" 2> "$tmpdir/err" || fail "$name [-compact]: $(head -c 300 "$tmpdir/err")"
		timeout 60 "$BIN" -compact "$tmpdir/compact1" > "$tmpdir/compact2" 2> "$tmpdir/err" || fail "$name [-compact twice]: $(head -c 300 "$tmpdir/err")"
		cmp -s "$tmpdir/compact1" "$tmpdir/compact2" || fail "$name: the compact writer is not a fixed point"
	done
done
echo "$files files: canonical form in 6 modes, compact fixed point"

if [ ${#@} -eq 0 ]; then
	# Same strings after unescaping
	"$BIN" -strings "$EXAMPLES/twitter.json" > "$tmpdir/s1"
	"$BIN" -strings "$EXAMPLES/twitterescaped.json" > "$tmpdir/s2"
	if cmp -s "$tmpdir/s1" "$tmpdir/s2"; then
		echo "twitter.json and twitterescaped.json: same $(wc -l < "$tmpdir/s1") names and strings"
	else
		fail "twitter.json and twitterescaped.json: names and strings differ"
	fi
	# Same canonical (JCS) form, members sorted
	"$BIN" -jcs "$EXAMPLES/mesh.json" > "$tmpdir/j1"
	"$BIN" -jcs "$EXAMPLES/mesh.pretty.json" > "$tmpdir/j2"
	if cmp -s "$tmpdir/j1" "$tmpdir/j2"; then
		echo "mesh.json and mesh.pretty.json: same RFC 8785 output ($(wc -c < "$tmpdir/j1") bytes)"
	else
		fail "mesh.json and mesh.pretty.json: RFC 8785 outputs differ"
	fi
	# JSON Pointer lookups, found and missing
	pointers=0
	while IFS=$'\t' read -r file pointer; do
		pointers=$((pointers + 1))
		python3 "$ORACLE" -pointer "$pointer" "$EXAMPLES/$file" > "$tmpdir/pw" 2>/dev/null
		want=$?
		for mode in "-pointer" "-select" "-stream 7 -select"; do
			"$BIN" $mode "$pointer" "$EXAMPLES/$file" > "$tmpdir/pg" 2> "$tmpdir/err"
			got=$?
			if [ $want -ne $got ]; then
				fail "$file $mode $pointer: exit $got, the oracle's $want ($(head -c 200 "$tmpdir/err"))"
			elif [ $want -eq 0 ] && ! cmp -s "$tmpdir/pw" "$tmpdir/pg"; then
				fail "$file $mode $pointer: the value differs from the oracle's"
			fi
		done
	done <<'EOF'
twitter.json	/statuses/0/id_str
twitter.json	/statuses/0/id
twitter.json	/statuses/99/user/screen_name
twitter.json	/statuses/100
twitter.json	/search_metadata/count
twitter.json	/statuses/0/entities
twitter.json	/statuses/-
twitter.json	/statuses/01
twitter.json	/statuses/0/id_str/x
citm_catalog.json	/areaNames/205705993
citm_catalog.json	/events/138586341/name
citm_catalog.json	/performances/0/seatCategories/0/areas
citm_catalog.json	/topicNames/324846100
canada.json	/features/0/geometry/coordinates/0/0
canada.json	/features/0/geometry/coordinates/0/0/1
github_events.json	/0/actor/login
github_events.json	/29/payload
gsoc-2018.json	/0/title
gsoc-2018.json	/1288/author/name
instruments.json	/instruments/0/name
random.json	/result/0/friends
update-center.json	/plugins/git/url
marine_ik.json	/metadata/version
mesh.json	/positions/12
numbers.json	/10000
numbers.json	/10001
numbers.json
EOF
	echo "$pointers JSON Pointer lookups, each on the document, on demand and on demand from a stream"
fi

if [ $failed -ne 0 ]; then
	echo "FAIL: see $LOGFILE"
	exit 1
fi
echo "PASS"
