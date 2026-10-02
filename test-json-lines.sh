#!/bin/bash
# Sequences through JsonTester (JsonSequenceReader; docs/test-suites.md §4.3), against the oracle
# (tests/tools/json-canonical.py -lines and -concatenated):
#   - simdjson-data's amazon_cellphones.ndjson (793 records) and jsonchecker pass01, pass02 and fail01
#     .ndjson read as JSON Lines and as concatenated values;
#   - every nst parsing case read as JSON Lines and as concatenated values (both delimit differently
#     from a document: `1 2` is one bad line but two values);
#   - generated inputs: CRLF, no final newline, empty and blank lines, a BOM, ill-formed UTF-8 in one
#     line, values that touch (`{}{}`, `12`, `1"a"`).
# Each from memory and through 7-byte stream reads: the values printed (stdout) must equal the
# oracle's, and the exit status too (1 when a record had an error). RFC 7464 sequences are covered by
# the [Test]s (the oracle has no RS mode).
# Usage: bash ./test-json-lines.sh            (Debug binary)
#        BIN=./build/Release_Linux64/JsonTester/JsonTester bash ./test-json-lines.sh

BIN="${BIN:-./build/Debug_Linux64/JsonTester/JsonTester}"
SUITES="${SUITES:-tests/suites}"
ORACLE="tests/tools/json-canonical.py"
LOGFILE="test-json-lines.log"

if [ ! -x "$BIN" ]; then
	echo "ERROR: $BIN not found or not executable. Build first with: beefbuild"
	exit 1
fi
if [ ! -d "$SUITES/JSONTestSuite/test_parsing" ]; then
	echo "ERROR: the suites are missing. Fetch them with: bash tests/fetch-suites.sh"
	exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
: > "$LOGFILE"

# Generated inputs
gen="$tmpdir/gen"
mkdir -p "$gen"
printf '{"a":1}\r\n{"a":2}' > "$gen/crlf-no-final.jsonl"
printf '1\n\n2\n \t\n3\n' > "$gen/empty-lines.jsonl"
printf '\xef\xbb\xbf[1]\n[2]\n' > "$gen/bom.jsonl"
printf '"a"\n"\xff"\n"b"\n' > "$gen/bad-utf8.jsonl"
printf '{}{}[] 12 1"a"null\n' > "$gen/touching.txt"
printf '[1]\n[2,]\n[3]\n' > "$gen/bad-middle.jsonl"
printf '{"a":\n1}\n' > "$gen/spanning.jsonl"
printf '' > "$gen/empty.jsonl"

total=0
failed=0
check() { # mode file
	local mode=$1 file=$2
	python3 "$ORACLE" "-$mode" "$file" > "$tmpdir/want" 2> /dev/null
	local want=$?
	for flags in "" "-stream 7"; do
		total=$((total + 1))
		timeout 30 "$BIN" "-$mode" $flags "$file" > "$tmpdir/got" 2> "$tmpdir/err"
		local got=$?
		if [ $got -ne $want ] || ! cmp -s "$tmpdir/got" "$tmpdir/want"; then
			failed=$((failed + 1))
			{
				echo "--- $file -$mode $flags: exit $got, the oracle's $want"
				diff "$tmpdir/want" "$tmpdir/got" | head -10
				head -5 "$tmpdir/err"
			} >> "$LOGFILE"
		fi
	done
}

for f in "$SUITES"/simdjson-data/jsonexamples/amazon_cellphones.ndjson "$SUITES"/simdjson-data/jsonchecker/*.ndjson "$gen"/*; do
	check lines "$f"
	check concatenated "$f"
done
for f in "$SUITES"/JSONTestSuite/test_parsing/*.json; do
	check lines "$f"
	check concatenated "$f"
done

records=$("$BIN" -lines "$SUITES"/simdjson-data/jsonexamples/amazon_cellphones.ndjson | wc -l)
echo "amazon_cellphones.ndjson: $records records as JSON Lines"
echo "$total runs (JSON Lines and concatenated, from memory and 7-byte stream reads), $failed differ from the oracle"
if [ $failed -ne 0 ]; then
	echo "FAIL: see $LOGFILE"
	exit 1
fi
echo "PASS"
