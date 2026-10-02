#!/bin/bash
# The JSON conformance suites through JsonTester (docs/test-suites.md §9.3, §9.4).
# Usage: bash ./test-json-suite.sh            (Debug binary)
#        BIN=./build/Release_Linux64/JsonTester/JsonTester bash ./test-json-suite.sh
#
# Cases and what each must do (default configuration):
#   nst              test_parsing: y_ accepted, n_ rejected, i_ accepted when listed in
#                    tests/nst/i-accept.txt (§1.2), else rejected
#   nst-transform    test_transform: accepted with the committed tests/nst/transform/<name>.out, or
#                    rejected when there is none (the six invalid-string cases)
#   checker          json.org JSON_checker: pass1-3, fail1 and fail18 accepted (RFC 8259), the rest rejected
#   simdjson         simdjson-data jsonchecker: pass*, and the six valid fail* files accepted (§2.2)
#   adversarial      simdjson-data jsonchecker/adversarial/issue150: all rejected, no crash or timeout
#   nativejson       nativejson-benchmark roundtrip: all accepted
#   json5            json5-tests in strict mode: the .json files accepted (but
#                    comments/irregular-block-comment.json, which has a comment), the rest rejected
# An accepted case's stdout must equal its canonical form (§9.2), computed by the independent oracle
# tests/tools/json-canonical.py (or the committed .out for transform cases). A rejected case must exit 1
# with the first stderr line equal to tests/errors/<id>.err (golden `line:column: Kind: message`, the
# same in every mode; UPDATE_GOLDEN=1 writes them from the first mode's output: review the diff).
# Adversarial cases need no golden message. Any other exit status (a crash) or a timeout is a failure.
#
# Every case runs in each of MODES (default "events stream1 stream16"): events reads with JsonReader;
# stream1 and stream16 read the file as a Stream in 1-byte and 16-byte reads through a 16-byte buffer,
# so refills land inside numbers, literals, escapes, surrogate pairs and UTF-8 sequences.
#
# Failures are compared with tests/expected-failures.txt (`id<TAB>mode<TAB>reason`, mode `*` for all):
# an unlisted failure fails the run, and so does a listed case that passes. tests/suites-skip.txt
# (`id<TAB>reason`) skips cases. Both are expected to stay empty. Details go to test-json-suite.log.
#
# Fetch the suites first with tests/fetch-suites.sh. Needs python3 (the oracle).

BIN="${BIN:-./build/Debug_Linux64/JsonTester/JsonTester}"
SUITES="${SUITES:-tests/suites}"
MODES="${MODES:-events stream1 stream16}"
EXPECTED="tests/expected-failures.txt"
SKIP="tests/suites-skip.txt"
LOGFILE="test-json-suite.log"
ORACLE="tests/tools/json-canonical.py"

if [ ! -x "$BIN" ]; then
	echo "ERROR: $BIN not found or not executable. Build first with: beefbuild"
	exit 1
fi
if [ ! -d "$SUITES/JSONTestSuite/test_parsing" ]; then
	echo "ERROR: $SUITES/JSONTestSuite not found. Fetch the suites with: bash tests/fetch-suites.sh"
	exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cases="$tmpdir/cases"
: > "$cases"
add() {
	printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$cases"
}

declare -A iaccept
while read -r name; do
	[[ -z "$name" || "$name" == \#* ]] && continue
	iaccept[$name]=1
done < tests/nst/i-accept.txt

for f in "$SUITES"/JSONTestSuite/test_parsing/*.json; do
	name=$(basename "$f" .json)
	case "$name" in
	y_*) add "nst/$name" nst "$f" accept ;;
	n_*) add "nst/$name" nst "$f" reject ;;
	i_*)
		if [ -n "${iaccept[$name]+x}" ]; then
			add "nst/$name" nst "$f" accept
		else
			add "nst/$name" nst "$f" reject
		fi
		;;
	esac
done
for f in "$SUITES"/JSONTestSuite/test_transform/*.json; do
	name=$(basename "$f" .json)
	if [ -f "tests/nst/transform/$name.out" ]; then
		add "nst-transform/$name" nst-transform "$f" accept
	else
		add "nst-transform/$name" nst-transform "$f" reject
	fi
done
for f in "$SUITES"/JSON_checker/*.json; do
	name=$(basename "$f" .json)
	case "$name" in
	pass*|fail1|fail18) add "checker/$name" checker "$f" accept ;;
	*) add "checker/$name" checker "$f" reject ;;
	esac
done
for f in "$SUITES"/simdjson-data/jsonchecker/*.json; do
	name=$(basename "$f" .json)
	case "$name" in
	pass*|fail01_EXCLUDE|fail18_EXCLUDE|fail39_EXCLUDE|fail41_toolarge|fail60|fail73) add "simdjson/$name" simdjson "$f" accept ;;
	*) add "simdjson/$name" simdjson "$f" reject ;;
	esac
done
for f in "$SUITES"/simdjson-data/jsonchecker/adversarial/issue150/*; do
	add "adversarial/$(basename "$f")" adversarial "$f" crashcheck
done
for f in "$SUITES"/nativejson/data/roundtrip/*.json; do
	add "nativejson/$(basename "$f" .json)" nativejson "$f" accept
done
for f in "$SUITES"/json5-tests/*/*; do
	rel="${f#"$SUITES"/json5-tests/}"
	case "$rel" in
	comments/irregular-block-comment.json) add "json5/$rel" json5 "$f" reject ;;
	*.json) add "json5/$rel" json5 "$f" accept ;;
	*.json5|*.js|*.txt) add "json5/$rel" json5 "$f" reject ;;
	esac
done

# Expected canonical forms of the accepted cases, from the oracle in one process
mkdir -p "$tmpdir/expected"
awk -F'\t' '$4 == "accept" { print NR "\t" $3 }' "$cases" | python3 "$ORACLE" -batch "$tmpdir/expected" || {
	echo "ERROR: the oracle failed"
	exit 1
}

declare -A skip_reason
if [ -f "$SKIP" ]; then
	while IFS=$'\t' read -r id reason; do
		[[ -z "$id" || "$id" == \#* ]] && continue
		skip_reason[$id]="$reason"
	done < "$SKIP"
fi
declare -A expected_reason
if [ -f "$EXPECTED" ]; then
	while IFS=$'\t' read -r id mode reason; do
		[[ -z "$id" || "$id" == \#* ]] && continue
		expected_reason["$id	$mode"]="$reason"
	done < "$EXPECTED"
fi

{
	echo "=== JSON suite log ==="
	echo "Date: $(date)"
	echo "Binary: $BIN"
	echo ""
} > "$LOGFILE"

suites="nst nst-transform checker simdjson adversarial nativejson json5"
failed=0
first_mode=1
for mode in $MODES; do
	case "$mode" in
	events) flag="-events" ;;
	document) flag="" ;;
	stream1) flag="-stream 1" ;;
	stream16) flag="-stream 16" ;;
	*) echo "ERROR: unknown mode $mode"; exit 1 ;;
	esac

	declare -A acc_pass=() acc_total=() rej_pass=() rej_total=() crash_count=()
	skipped=0
	unexpected=()
	fixed=()
	index=0
	while IFS=$'\t' read -r id suite path expect; do
		index=$((index + 1))
		if [ -n "${skip_reason[$id]+x}" ]; then
			skipped=$((skipped + 1))
			continue
		fi
		timeout 10 "$BIN" $flag "$path" > "$tmpdir/out" 2> "$tmpdir/err"
		status=$?
		ok=1
		why=""
		if [ $status -gt 1 ]; then
			crash_count[$suite]=$(( ${crash_count[$suite]:-0} + 1 ))
			ok=0
			if [ $status -eq 124 ]; then why="TIMEOUT"; else why="CRASH ($status)"; fi
		fi
		case "$expect" in
		accept)
			acc_total[$suite]=$(( ${acc_total[$suite]:-0} + 1 ))
			if [ $ok -eq 1 ] && [ $status -ne 0 ]; then
				ok=0
				why="REJECTED: $(head -1 "$tmpdir/err")"
			elif [ $ok -eq 1 ]; then
				if [ "$suite" = nst-transform ]; then
					want="tests/nst/transform/${id#nst-transform/}.out"
				else
					want="$tmpdir/expected/$index.out"
				fi
				if [ ! -f "$want" ]; then
					ok=0
					why="THE ORACLE REJECTS IT: $(cat "$tmpdir/expected/$index.rej" 2>/dev/null)"
				elif ! cmp -s "$tmpdir/out" "$want"; then
					ok=0
					why="CANONICAL MISMATCH"
					cp "$want" "$tmpdir/want"
				else
					acc_pass[$suite]=$(( ${acc_pass[$suite]:-0} + 1 ))
				fi
			fi
			;;
		reject|crashcheck)
			rej_total[$suite]=$(( ${rej_total[$suite]:-0} + 1 ))
			if [ $ok -eq 1 ] && [ $status -eq 0 ]; then
				ok=0
				why="ACCEPTED"
			elif [ $ok -eq 1 ] && [ "$expect" = crashcheck ]; then
				rej_pass[$suite]=$(( ${rej_pass[$suite]:-0} + 1 ))
			elif [ $ok -eq 1 ]; then
				golden="tests/errors/$id.err"
				if [ -n "${UPDATE_GOLDEN:-}" ] && [ $first_mode -eq 1 ]; then
					mkdir -p "$(dirname "$golden")"
					head -1 "$tmpdir/err" > "$golden"
					rej_pass[$suite]=$(( ${rej_pass[$suite]:-0} + 1 ))
				elif head -1 "$tmpdir/err" | cmp -s - "$golden"; then
					rej_pass[$suite]=$(( ${rej_pass[$suite]:-0} + 1 ))
				else
					ok=0
					why="ERROR MESSAGE CHANGED (expected: $(cat "$golden" 2>/dev/null || echo 'no golden file'))"
				fi
			fi
			;;
		esac

		listed=""
		if [ -n "${expected_reason["$id	$mode"]+x}" ] || [ -n "${expected_reason["$id	*"]+x}" ]; then
			listed=1
		fi
		if [ $ok -eq 0 ]; then
			if [ -n "$listed" ]; then
				echo "--- expected failure: $id [$mode]: $why" >> "$LOGFILE"
			else
				unexpected+=("$id")
				{
					echo "--- $why: $id [$mode] $path ---"
					head -c 300 "$path" | od -An -c | head -5
					echo "stderr: $(head -c 500 "$tmpdir/err")"
					if [ "$why" = "CANONICAL MISMATCH" ]; then
						echo "Expected:"
						head -c 1000 "$tmpdir/want"
						echo "Actual:"
						head -c 1000 "$tmpdir/out"
					fi
					echo ""
				} >> "$LOGFILE"
			fi
		elif [ -n "$listed" ]; then
			fixed+=("$id")
			echo "--- listed in $EXPECTED but passes: $id [$mode]" >> "$LOGFILE"
		fi
	done < "$cases"

	for suite in $suites; do
		line="[$mode] $suite:"
		if [ -n "${acc_total[$suite]:-}" ]; then
			line="$line accepted ${acc_pass[$suite]:-0}/${acc_total[$suite]}"
		fi
		if [ -n "${rej_total[$suite]:-}" ]; then
			line="$line rejected ${rej_pass[$suite]:-0}/${rej_total[$suite]}"
		fi
		if [ -n "${crash_count[$suite]:-}" ]; then
			line="$line CRASHES ${crash_count[$suite]}"
		fi
		echo "$line"
	done
	if [ $skipped -gt 0 ]; then
		echo "[$mode] skipped: $skipped (listed in $SKIP)"
	fi
	if [ ${#unexpected[@]} -gt 0 ]; then
		echo "[$mode] unexpected failures (${#unexpected[@]}): ${unexpected[*]:0:20}$([ ${#unexpected[@]} -gt 20 ] && echo ' ...')"
		failed=1
	fi
	if [ ${#fixed[@]} -gt 0 ]; then
		echo "[$mode] listed in $EXPECTED but passing (remove them): ${fixed[*]}"
		failed=1
	fi
	first_mode=0
done

if [ $failed -ne 0 ]; then
	echo "FAIL: see $LOGFILE"
	exit 1
fi
echo "PASS"
