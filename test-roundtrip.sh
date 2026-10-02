#!/bin/bash
# PreserveStyle round trips through JsonTester (docs/test-suites.md §9.6).
# Usage: bash ./test-roundtrip.sh            (Debug binary; SEEDS=3 by default)
#        BIN=./build/Release_Linux64/JsonTester/JsonTester bash ./test-roundtrip.sh
#
# Every accepted input: the nst y_ and accepted i_ cases, JSON_checker's and simdjson-data's accepted
# files, the nativejson round-trip files and json5-tests' .json files (strict), the json5-tests files
# JSONC accepts (with -jsonc: comments and trailing commas), the other JSON5 ones (with -json5), and
# the real-world corpora.
#   - read with PreserveStyle and written back (-preserve -echo), from memory and from a stream fed 16
#     bytes per read, it must equal the input byte for byte;
#   - edited at random (-mutate SEED, for each of SEEDS seeds: values set, members renamed, values
#     removed, added and inserted, containers replaced), the preserving writer's output must read back
#     into exactly the edited document.
# Details go to test-roundtrip.log.

BIN="${BIN:-./build/Debug_Linux64/JsonTester/JsonTester}"
SUITES="${SUITES:-tests/suites}"
SEEDS="${SEEDS:-3}"
LOGFILE="test-roundtrip.log"

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

# Inputs: path<TAB>dialect flag
inputs="$tmpdir/inputs"
: > "$inputs"
while read -r name; do
	[[ -z "$name" || "$name" == \#* ]] && continue
	printf '%s\t\n' "$SUITES/JSONTestSuite/test_parsing/$name.json" >> "$inputs"
done < tests/nst/i-accept.txt
for f in "$SUITES"/JSONTestSuite/test_parsing/y_*.json "$SUITES"/JSON_checker/pass*.json "$SUITES"/JSON_checker/fail1.json \
	"$SUITES"/JSON_checker/fail18.json "$SUITES"/simdjson-data/jsonchecker/pass*.json "$SUITES"/nativejson/data/roundtrip/*.json \
	"$SUITES"/simdjson-data/jsonexamples/*.json; do
	printf '%s\t\n' "$f" >> "$inputs"
done
for name in fail01_EXCLUDE fail18_EXCLUDE fail39_EXCLUDE fail41_toolarge fail60 fail73; do
	printf '%s\t\n' "$SUITES/simdjson-data/jsonchecker/$name.json" >> "$inputs"
done
while read -r rel; do
	[[ -z "$rel" || "$rel" == \#* ]] && continue
	printf '%s\t-jsonc\n' "$SUITES/json5-tests/$rel" >> "$inputs"
done < tests/json5/accept-jsonc.txt
# The JSON5-only ones, as JSON5 (single quotes, unquoted names, hex and the rest written back as they are)
while read -r rel; do
	[[ -z "$rel" || "$rel" == \#* ]] && continue
	grep -qxF "$rel" tests/json5/accept-jsonc.txt && continue
	printf '%s\t-json5\n' "$SUITES/json5-tests/$rel" >> "$inputs"
done < tests/json5/accept-json5.txt

total=0
echo_fail=0
stream_fail=0
mutate_runs=0
mutate_fail=0
while IFS=$'\t' read -r path dialect; do
	total=$((total + 1))
	if ! timeout 30 "$BIN" $dialect -preserve -echo "$path" > "$tmpdir/out" 2> "$tmpdir/err" || ! cmp -s "$tmpdir/out" "$path"; then
		echo_fail=$((echo_fail + 1))
		echo "--- ECHO DIFFERS: $path ($dialect) $(head -c 300 "$tmpdir/err")" >> "$LOGFILE"
	fi
	if ! timeout 30 "$BIN" $dialect -preserve -echo -stream 16 "$path" > "$tmpdir/out" 2> "$tmpdir/err" || ! cmp -s "$tmpdir/out" "$path"; then
		stream_fail=$((stream_fail + 1))
		echo "--- STREAM ECHO DIFFERS: $path ($dialect) $(head -c 300 "$tmpdir/err")" >> "$LOGFILE"
	fi
	for seed in $(seq 1 "$SEEDS"); do
		mutate_runs=$((mutate_runs + 1))
		if ! timeout 60 "$BIN" $dialect -mutate "$seed" "$path" > /dev/null 2> "$tmpdir/err"; then
			mutate_fail=$((mutate_fail + 1))
			{
				echo "--- MUTATION FAILED: $path ($dialect) seed $seed"
				head -c 3000 "$tmpdir/err"
				echo ""
			} >> "$LOGFILE"
		fi
	done
done < "$inputs"

echo "echo: $((total - echo_fail))/$total byte for byte; from a 16-byte stream: $((total - stream_fail))/$total"
echo "mutate: $((mutate_runs - mutate_fail))/$mutate_runs edited documents read back as edited"
if [ $echo_fail -ne 0 ] || [ $stream_fail -ne 0 ] || [ $mutate_fail -ne 0 ]; then
	echo "FAIL: see $LOGFILE"
	exit 1
fi
echo "PASS"
