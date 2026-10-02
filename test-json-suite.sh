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
# Every case runs in each of MODES (default "document events stream1 stream16 push1 push7 rewrite
# rewrite-pretty collect stream-collect preserve"):
# document builds a JsonDocument and prints from it; events prints straight from JsonReader's tokens;
# stream1 builds the document from a Stream fed in 1-byte reads, stream16 reads events from 16-byte
# reads (both through a 16-byte buffer, so refills land inside numbers, literals, escapes, surrogate
# pairs and UTF-8 sequences); push1 and push7 feed a JsonPushReader 1 or 7 bytes at a time (a token cut
# off waits for the rest); rewrite and rewrite-pretty write the document compact or indented, read
# that back and print it (the writer must keep everything; exit 3 if its output is rejected); collect
# and stream-collect read with JsonReadConfig.CollectErrors from memory and from 1-byte stream reads
# (the first error must still be the golden one, and recovery must finish); preserve reads with
# JsonMetadataMode.PreserveStyle (test-roundtrip.sh checks that it writes back byte for byte).
#
# The extension modes of EXTENSIONS (default "comments jsonc nonfinite ijson") run once each: every y_
# case stays accepted (but those of tests/nst/reject-<mode>.txt, for I-JSON), and exactly the cases
# listed in tests/nst/accept-<mode>.txt and tests/json5/accept-<mode>.txt are accepted among the nst n_
# cases and json5-tests (docs/test-suites.md §1.5, §4.1). Then the string options (-utf8=replace,
# -surrogates=replace|wtf8) are compared with the oracle on every nst case.
#
# Two more checks run once: every nativejson round-trip file written by the compact writer must equal
# the file byte for byte (JsonFloatFormat.Plain keeps `0.0`, `-0.0`, `1.7976931348623157e308`), and
# every RFC 8785 test vector (json-canonicalization testdata) written with -jcs must equal its output
# file byte for byte.
#
# Failures are compared with tests/expected-failures.txt (`id<TAB>mode<TAB>reason`, mode `*` for all):
# an unlisted failure fails the run, and so does a listed case that passes. tests/suites-skip.txt
# (`id<TAB>reason`) skips cases. Both are expected to stay empty. Details go to test-json-suite.log.
#
# Fetch the suites first with tests/fetch-suites.sh. Needs python3 (the oracle).

BIN="${BIN:-./build/Debug_Linux64/JsonTester/JsonTester}"
SUITES="${SUITES:-tests/suites}"
MODES="${MODES:-document events stream1 stream16 push1 push7 rewrite rewrite-pretty collect stream-collect preserve}"
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
	document) flag="" ;;
	events) flag="-events" ;;
	stream1) flag="-stream 1" ;;
	stream16) flag="-events -stream 16" ;;
	rewrite) flag="-rewrite" ;;
	rewrite-pretty) flag="-rewrite-pretty" ;;
	collect) flag="-collect" ;;
	stream-collect) flag="-collect -stream 1" ;;
	push1) flag="-push 1" ;;
	push7) flag="-push 7" ;;
	preserve) flag="-preserve" ;;
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

# Extension modes: every y_ case stays accepted, and exactly the n_ cases of tests/nst/accept-<mode>.txt
# and the json5-tests files of tests/json5/accept-<mode>.txt are accepted (docs/test-suites.md §1.5,
# §4.1)
read_list() { # file
	grep -v '^#' "$1" | grep -v '^$' | sort
}
for ext in ${EXTENSIONS:-comments jsonc nonfinite ijson json5}; do
	: > "$tmpdir/nst-accepted"
	y_rejected=()
	for f in "$SUITES"/JSONTestSuite/test_parsing/[yn]_*.json; do
		name=$(basename "$f" .json)
		if timeout 10 "$BIN" "-$ext" "$f" > /dev/null 2>&1; then
			[[ "$name" == n_* ]] && echo "$name" >> "$tmpdir/nst-accepted"
		else
			[[ "$name" == y_* ]] && y_rejected+=("$name")
		fi
	done
	: > "$tmpdir/json5-accepted"
	for f in "$SUITES"/json5-tests/*/*; do
		rel="${f#"$SUITES"/json5-tests/}"
		case "$rel" in
		*.json|*.json5|*.js|*.txt)
			timeout 10 "$BIN" "-$ext" "$f" > /dev/null 2>&1 && echo "$rel" >> "$tmpdir/json5-accepted"
			;;
		esac
	done
	ok=1
	y_accepted=$((95 - ${#y_rejected[@]}))
	if [ -f "tests/nst/reject-$ext.txt" ]; then
		# A mode stricter than RFC 8259 (I-JSON) rejects exactly the listed y_ cases
		if ! diff <(read_list "tests/nst/reject-$ext.txt") <(printf '%s\n' "${y_rejected[@]}" | grep -v '^$' | sort) > "$tmpdir/diff"; then
			echo "[-$ext] y_ cases rejected differ from tests/nst/reject-$ext.txt:"
			sed 's/^/  /' "$tmpdir/diff"
			ok=0
		fi
		y_rejected=()
	fi
	if [ ${#y_rejected[@]} -gt 0 ]; then
		echo "[-$ext] y_ cases rejected: ${y_rejected[*]}"
		ok=0
	fi
	if ! diff <(read_list "tests/nst/accept-$ext.txt") <(sort "$tmpdir/nst-accepted") > "$tmpdir/diff"; then
		echo "[-$ext] nst n_ cases accepted differ from tests/nst/accept-$ext.txt:"
		sed 's/^/  /' "$tmpdir/diff"
		ok=0
	fi
	if ! diff <(read_list "tests/json5/accept-$ext.txt") <(sort "$tmpdir/json5-accepted") > "$tmpdir/diff"; then
		echo "[-$ext] json5-tests accepted differ from tests/json5/accept-$ext.txt:"
		sed 's/^/  /' "$tmpdir/diff"
		ok=0
	fi
	if [ $ok -eq 1 ]; then
		echo "[-$ext] nst: $y_accepted y_ accepted, n_ accepted as listed ($(wc -l < "$tmpdir/nst-accepted")); json5-tests accepted as listed ($(wc -l < "$tmpdir/json5-accepted"))"
	else
		failed=1
	fi
done

# String options (docs/test-suites.md §1.2, §1.4): every nst parsing and transform case read with
# -utf8=replace -surrogates=replace and with -surrogates=wtf8, as a document from memory and as tokens
# from 1-byte stream reads: accepted with the oracle's canonical form under the same options, or
# rejected by both
ls "$SUITES"/JSONTestSuite/test_parsing/*.json "$SUITES"/JSONTestSuite/test_transform/*.json | awk '{ print NR "\t" $0 }' > "$tmpdir/optcases"
for opts in "-utf8=replace -surrogates=replace" "-surrogates=wtf8"; do
	rm -rf "$tmpdir/opt"
	mkdir -p "$tmpdir/opt"
	python3 "$ORACLE" $opts -batch "$tmpdir/opt" < "$tmpdir/optcases" || { echo "ERROR: the oracle failed"; exit 1; }
	accepted=0
	rejected=0
	bad=()
	while IFS=$'\t' read -r n f; do
		if [ -f "$tmpdir/opt/$n.out" ]; then accepted=$((accepted + 1)); else rejected=$((rejected + 1)); fi
		for flag in "" "-events -stream 1"; do
			timeout 10 "$BIN" $opts $flag "$f" > "$tmpdir/out" 2> /dev/null
			status=$?
			if [ -f "$tmpdir/opt/$n.out" ]; then
				{ [ $status -eq 0 ] && cmp -s "$tmpdir/out" "$tmpdir/opt/$n.out"; } || bad+=("$(basename "$f") [$flag] exit $status")
			elif [ $status -ne 1 ]; then
				bad+=("$(basename "$f") [$flag] exit $status, the oracle rejects it")
			fi
		done
	done < "$tmpdir/optcases"
	if [ ${#bad[@]} -eq 0 ]; then
		echo "[$opts] nst: $accepted accepted with the oracle's canonical form, $rejected rejected by both"
	else
		echo "[$opts] ${#bad[@]} disagreements with the oracle:"
		printf '  %s\n' "${bad[@]:0:20}"
		failed=1
	fi
done

# JSON5 (-json5): every nst parsing case and json5-tests file, as a document from memory, as tokens and
# as tokens from 1-byte stream reads, accepted with the canonical form of tests/tools/json5-canonical.py
# (an independent JSON5 reader, checked against json5 2.2.3), or rejected by both
ls "$SUITES"/JSONTestSuite/test_parsing/*.json "$SUITES"/json5-tests/*/*.json "$SUITES"/json5-tests/*/*.json5 \
	"$SUITES"/json5-tests/*/*.js "$SUITES"/json5-tests/*/*.txt | awk '{ print NR "\t" $0 }' > "$tmpdir/json5cases"
rm -rf "$tmpdir/json5"
mkdir -p "$tmpdir/json5"
python3 tests/tools/json5-canonical.py -batch "$tmpdir/json5" < "$tmpdir/json5cases" || { echo "ERROR: the JSON5 oracle failed"; exit 1; }
accepted=0
rejected=0
bad=()
while IFS=$'\t' read -r n f; do
	if [ -f "$tmpdir/json5/$n.out" ]; then accepted=$((accepted + 1)); else rejected=$((rejected + 1)); fi
	for flag in "" "-events" "-events -stream 1"; do
		timeout 10 "$BIN" -json5 $flag "$f" > "$tmpdir/out" 2> /dev/null
		status=$?
		if [ -f "$tmpdir/json5/$n.out" ]; then
			{ [ $status -eq 0 ] && cmp -s "$tmpdir/out" "$tmpdir/json5/$n.out"; } || bad+=("${f#"$SUITES"/} [$flag] exit $status")
		elif [ $status -ne 1 ]; then
			bad+=("${f#"$SUITES"/} [$flag] exit $status, the oracle rejects it")
		fi
	done
done < "$tmpdir/json5cases"
if [ ${#bad[@]} -eq 0 ]; then
	echo "[-json5] nst and json5-tests: $accepted accepted with the oracle's canonical form, $rejected rejected by both"
else
	echo "[-json5] ${#bad[@]} disagreements with the JSON5 oracle:"
	printf '  %s\n' "${bad[@]:0:20}"
	failed=1
fi

# The compact writer reproduces the nativejson round-trip files
pass=0; total=0; bad=()
for f in "$SUITES"/nativejson/data/roundtrip/*.json; do
	total=$((total + 1))
	if timeout 10 "$BIN" -compact "$f" 2> "$tmpdir/err" | cmp -s - "$f"; then
		pass=$((pass + 1))
	else
		bad+=("$(basename "$f")")
	fi
done
echo "[compact] nativejson written back byte for byte: $pass/$total"
if [ ${#bad[@]} -gt 0 ]; then
	echo "[compact] differ: ${bad[*]}"
	failed=1
fi

# RFC 8785 vectors
pass=0; total=0; bad=()
for f in "$SUITES"/json-canonicalization/testdata/input/*.json; do
	total=$((total + 1))
	if timeout 10 "$BIN" -jcs "$f" 2> "$tmpdir/err" | cmp -s - "$SUITES/json-canonicalization/testdata/output/$(basename "$f")"; then
		pass=$((pass + 1))
	else
		bad+=("$(basename "$f")")
	fi
done
echo "[jcs] RFC 8785 vectors: $pass/$total"
if [ ${#bad[@]} -gt 0 ]; then
	echo "[jcs] differ: ${bad[*]}"
	failed=1
fi

if [ $failed -ne 0 ]; then
	echo "FAIL: see $LOGFILE"
	exit 1
fi
echo "PASS"
