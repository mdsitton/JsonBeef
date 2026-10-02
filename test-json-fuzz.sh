#!/bin/bash
# Differential fuzzing through JsonTester -fuzz: every suite input and real-world file, mutated at
# random (bytes replaced, inserted, deleted, duplicated), is read three ways: the document's fast build
# from memory, JsonReader's tokens from memory, and a document built through 1-byte stream reads. All
# three must give the same canonical form, or the same error (kind, line, column, offset). A
# disagreement is a bug in one of the paths (the fast build duplicates the reader's checks).
# Usage: bash ./test-json-fuzz.sh            (Debug binary; SEEDS=3 ROUNDS=200 for a longer run)
#        BIN=./build/Release_Linux64/JsonTester/JsonTester bash ./test-json-fuzz.sh

BIN="${BIN:-./build/Debug_Linux64/JsonTester/JsonTester}"
SUITES="${SUITES:-tests/suites}"
SEEDS="${SEEDS:-2}"
ROUNDS="${ROUNDS:-50}"

if [ ! -x "$BIN" ]; then
	echo "ERROR: $BIN not found or not executable. Build first with: beefbuild"
	exit 1
fi
if [ ! -d "$SUITES/JSONTestSuite/test_parsing" ]; then
	echo "ERROR: the suites are missing. Fetch them with: bash tests/fetch-suites.sh"
	exit 1
fi

failed=0
for seed in $(seq 1 "$SEEDS"); do
	"$BIN" -fuzz "$seed" "$ROUNDS" "$SUITES"/JSONTestSuite/test_parsing/*.json "$SUITES"/JSON_checker/*.json \
		"$SUITES"/simdjson-data/jsonchecker/*.json "$SUITES"/nativejson/data/roundtrip/*.json \
		"$SUITES"/json5-tests/*/*.json* || failed=1
	# The real-world files: fewer rounds (each run reads a few hundred KB three times)
	"$BIN" -fuzz "$seed" 3 "$SUITES"/simdjson-data/jsonexamples/*.json || failed=1
done
if [ $failed -ne 0 ]; then
	echo "FAIL"
	exit 1
fi
echo "PASS"
