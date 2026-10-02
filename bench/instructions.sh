#!/bin/bash
# Instructions per input byte (user space) of the Release JsonTester's passes, per bench/compare input:
# a measure that, unlike time, does not depend on the machine's load, for comparing changes when a quiet
# machine is not available (XmlBeef's bench/instructions.sh). It is not speed: memory traffic and
# branch misses are not in it. Timed figures come from bench/compare/run.sh on a quiet machine.
# Usage: bash bench/instructions.sh [input names...]      (beefbuild -config=Release first)
#   MODES="events document" limits the columns (default: events document stream write).
#   EVENT=cycles counts CPU cycles instead (closer to speed, as it sees branch misses and memory stalls,
#   but it varies with the load: compare runs taken back to back).
set -uo pipefail
cd "$(dirname "$0")/.."
T=./build/Release_Linux64/JsonTester/JsonTester
if ! command -v perf > /dev/null; then
	echo "ERROR: perf not found"
	exit 1
fi
if [ ! -x "$T" ] || ! "$T" -bench-loop events bench/compare/inputs/twitter.json 1 > /dev/null 2>&1; then
	echo "ERROR: $T missing or without -bench-loop: beefbuild -config=Release first (inputs: bench/compare/gen-inputs.py)"
	exit 1
fi
if [ $# -gt 0 ]; then
	inputs=("$@")
else
	inputs=(twitter twitterescaped citm_catalog canada github_events gsoc-2018 mesh numbers marine_ik
		tiny rest records strings integers floats events)
fi
modes=(${MODES:-events document stream write})

EVENT="${EVENT:-instructions}"
count() { # mode path iterations
	perf stat -x, -e "$EVENT:u" "$T" -bench-loop "$1" "$2" "$3" 2>&1 > /dev/null | grep "$EVENT" | cut -d, -f1
}

line=$(printf '%-15s' input)
for mode in "${modes[@]}"; do
	line+=$(printf ' %9s' "$mode")
done
echo "$line"
for name in "${inputs[@]}"; do
	path=bench/compare/inputs/$name.json
	[ -f "$path" ] || path=bench/compare/inputs/$name.ndjson
	if [ ! -f "$path" ]; then
		echo "$name: no input (bench/compare/gen-inputs.py)"
		continue
	fi
	bytes=$(du -sb --apparent-size "$path" | cut -f1)
	line=$(printf '%-15s' "$name")
	for mode in "${modes[@]}"; do
		if [ "$mode" = write ] && [[ "$path" == *.ndjson ]]; then
			line+=$(printf ' %9s' -)
			continue
		fi
		# Two runs that differ by five iterations: reading the file and starting up cancel out
		one=$(count "$mode" "$path" 1)
		six=$(count "$mode" "$path" 6)
		line+=$(awk -v a="$one" -v b="$six" -v n="$bytes" 'BEGIN { printf " %9.2f", (b - a) / 5 / n }')
	done
	echo "$line"
done
