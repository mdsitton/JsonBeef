#!/bin/bash
# The number corpora through JsonTester (docs/test-suites.md §3, §9.5).
# Usage: bash ./test-json-numbers.sh            (Debug binary)
#        BIN=./build/Release_Linux64/JsonTester/JsonTester bash ./test-json-numbers.sh
#
# -fxx: every line of parse-number-fxx-test-data (1,414,285 by default; 5.3 million with FXX_FULL=1 in
# tests/fetch-suites.sh) is read by JsonReader as a whole document. It must be accepted exactly when
# it matches RFC 8259's number grammar, and then give the f64 bits (TryGetDouble fails on the 30,700
# overflow lines; the double is +∞) and, parsed directly as a float, the f32 bits.
# -es6: the RFC 8785 number file: each double written in ECMAScript layout must equal the expected
# text, and the text read back must give the bits.
# Both run every line in Debug too (about 4 s); there is no expected-failure list: a mismatch is a bug.

BIN="${BIN:-./build/Debug_Linux64/JsonTester/JsonTester}"
SUITES="${SUITES:-tests/suites}"

if [ ! -x "$BIN" ]; then
	echo "ERROR: $BIN not found or not executable. Build first with: beefbuild"
	exit 1
fi
fxx=("$SUITES"/parse-number-fxx/*.txt)
es6=("$SUITES"/es6-numbers/es6testfile-*.txt)
if [ ! -e "${fxx[0]}" ] || [ ! -e "${es6[0]}" ]; then
	echo "ERROR: the number corpora are missing. Fetch the suites with: bash tests/fetch-suites.sh"
	exit 1
fi

failed=0
"$BIN" -fxx "${fxx[@]}" || failed=1
for f in "${es6[@]}"; do
	"$BIN" -es6 "$f" || failed=1
done
if [ $failed -ne 0 ]; then
	echo "FAIL"
	exit 1
fi
echo "PASS"
