#!/bin/bash
# Fetches the third-party JSON test suites and corpora at pinned versions into tests/suites/
# (git-ignored). See docs/test-suites.md for what each one is, how the runner classifies its cases and
# why they are fetched rather than vendored (several have no license or mixed terms, and none of them
# is needed in the repository to build JsonBeef).
#
#   tests/suites/JSONTestSuite/     nst/JSONTestSuite: test_parsing/ (y_/n_/i_ cases) and test_transform/.
#   tests/suites/JSON_checker/      json.org JSON_checker test.zip (pass1-3, fail1-33).
#   tests/suites/simdjson-data/     simdjson/simdjson-data: jsonchecker/ (incl. minefield/, adversarial/)
#                                   and the standard real-world jsonexamples/ (no semanticscholar).
#   tests/suites/nativejson/        miloyip/nativejson-benchmark: data/roundtrip/ only.
#   tests/suites/yajl/              lloyd/yajl test/parsing/cases (*.json + *.gold event traces).
#   tests/suites/json5-tests/       json5/json5-tests (JSON5 accept/reject cases).
#   tests/suites/jsonc-parser/      microsoft/node-jsonc-parser src/test/ (cases to port by hand).
#   tests/suites/json-canonicalization/  cyberphone/json-canonicalization testdata/ (RFC 8785 vectors).
#   tests/suites/es6-numbers/       First $ES6_LINES lines of the RFC 8785 number test file
#                                   (es6testfile100m.txt.gz), fetched with a ranged download.
#   tests/suites/parse-number-fxx/  nigeltao/parse-number-fxx-test-data data/*.txt. The four
#                                   remyoudompheng-fptest files (198 MB, 3.9M lines) only with FXX_FULL=1.
#
# Git checkouts are pinned by commit hash (blobless, sparse, depth 1); plain downloads are verified
# against the SHA-256 sums below. Each suite directory gets a .pinned stamp, and a suite whose stamp
# matches is left alone, so rerunning the script is cheap. Bump a pin deliberately and rerun the
# conformance scripts.
set -euo pipefail

NST_REPO="https://github.com/nst/JSONTestSuite.git"
NST_COMMIT="1ef36fa01286573e846ac449e8683f8833c5b26a"            # 2024-11-22

SIMDJSON_DATA_REPO="https://github.com/simdjson/simdjson-data.git"
SIMDJSON_DATA_COMMIT="4197c425e857f0ec38e89822fdd0bd9ea21f4daf"  # 2025-11-21

NATIVEJSON_REPO="https://github.com/miloyip/nativejson-benchmark.git"
NATIVEJSON_COMMIT="478d5727c2a4048e835a29c65adecc7d795360d5"     # 2022-10-28

YAJL_REPO="https://github.com/lloyd/yajl.git"
YAJL_COMMIT="5e3a7856e643b4d6410ddc3f84bc2f38174f2872"           # 2015-09-24 (2.1.0+)

JSON5_TESTS_REPO="https://github.com/json5/json5-tests.git"
JSON5_TESTS_COMMIT="ceb24d4080137d70833f86c25659c1331b80a387"    # 2026-02-20

JSONC_REPO="https://github.com/microsoft/node-jsonc-parser.git"
JSONC_COMMIT="164a8e9eb137449adfe95ef906de7cb1fa757265"          # 2026-09-29

JCS_REPO="https://github.com/cyberphone/json-canonicalization.git"
JCS_COMMIT="19d51d7fe467d4706a3ff08adf8a748f29fc21e0"            # 2024-12-13

JSON_CHECKER_URL="https://www.json.org/JSON_checker/test.zip"
JSON_CHECKER_SHA256="5abaf51d15cd19beb36db16a659bc4fe298c5e5f870f5ae0d6831ea2eb7c02c0"   # 5721 bytes

# RFC 8785 Appendix B points to this 100-million-line test vector (2.08 GB gzipped). Only a prefix is
# fetched: its SHA-256 for each supported line count is published in the repository's
# testdata/README.md, so the prefix is verified without downloading the whole file.
ES6_URL="https://github.com/cyberphone/json-canonicalization/releases/download/es6testfile/es6testfile100m.txt.gz"
ES6_LINES="${ES6_LINES:-100000}"
case "$ES6_LINES" in
	1000)    ES6_SHA256="be18b62b6f69cdab33a7e0dae0d9cfa869fda80ddc712221570f9f40a5878687"; ES6_RANGE=1048575 ;;
	10000)   ES6_SHA256="b9f7a8e75ef22a835685a52ccba7f7d6bdc99e34b010992cbc5864cd12be6892"; ES6_RANGE=1048575 ;;
	100000)  ES6_SHA256="22776e6d4b49fa294a0d0f349268e5c28808fe7e0cb2bcbe28f63894e494d4c7"; ES6_RANGE=3145727 ;;
	1000000) ES6_SHA256="49415fee2c56c77864931bd3624faad425c3c577d6d74e89a83bc725506dad16"; ES6_RANGE=25165823 ;;
	*) echo "ES6_LINES must be 1000, 10000, 100000 or 1000000" >&2; exit 1 ;;
esac

FXX_COMMIT="55d79b184b7d8fac2e143e89dc19b766ec4e54b8"            # 2022-04-13
FXX_BASE="https://raw.githubusercontent.com/nigeltao/parse-number-fxx-test-data/$FXX_COMMIT/data"
# name sha256 (sizes and line counts in docs/test-suites.md)
FXX_FILES="
exhaustive-float16 6ac73ebcc2425ec1d82ac28483891919f7a3595261b0d89facea6b9c03c0f6c7
freetype-2-7 107ac506a0fb6af384b731019f83e184c27bd384364528ff18cd3720681eee66
google-double-conversion 734ac4ea2034818681b76e50623da8fd6a5d66799378cf696b5f110cade5d087
google-wuffs 7d648e3fadd7d75707743c1f091f5e005596aaae44d79b3fd9a960fa79d64605
ibm-fpgen a2bb29cfb648f9ebfe153fe03e3113ed682f7efed5950c56e167fc90fed1e835
lemire-fast-double-parser 2f3c6e0afa2bb6d641595dcbb095cfb10466ab871cca261f495524ac90f095a6
lemire-fast-float f68aab81b870cffa4606d481f7b841e5dce567a44297fe55d9c79ea77e0fbe4b
more-test-cases ea87ec4945712ecad563ba8f728c015d4ae68bed92ab128a8b440b0abf168148
tencent-rapidjson 227476db6faf338c0e62efbed51f79c1ddacc63e297fef1b284ea0e9648d3b7b
ulfjack-ryu 5c54633e8301c6ba3e9b9b5c5f6f7e0884cd2311418f2da6f2f9864d274be86c
"
FXX_FULL_FILES="
remyoudompheng-fptest-0 9eb7c06fd33084c8edee4c22b191752ecf9b51f3dcfe0bffa16a244aca9f2533
remyoudompheng-fptest-1 cd4e15a09424575287a5f6cd5479ec098109ace7402611c126b0cb9addcdae36
remyoudompheng-fptest-2 01cdab4298e0441de4ee6e52fa24dac765eaebaf74d8bb1ae4b8615f0c223a44
remyoudompheng-fptest-3 a1c3bd437ad173b426c725f6bd982b07f722cb2f7a525685c3b8a2fed439614c
"
if [ "${FXX_FULL:-0}" = "1" ]; then
	FXX_FILES="$FXX_FILES$FXX_FULL_FILES"
fi

SUITES="$(cd "$(dirname "$0")" && pwd)/suites"
DOWNLOADS="$SUITES/.downloads"
mkdir -p "$DOWNLOADS"

# is_current <dir> <pin>: true when <dir> was fully populated from <pin> by an earlier run.
is_current() {
	[ -f "$1/.pinned" ] && [ "$(cat "$1/.pinned")" = "$2" ]
}

# verify <file> <sha256>: true when <file> exists and has the given SHA-256.
verify() {
	[ -f "$1" ] && echo "$2  $1" | sha256sum --check --status
}

# download <url> <sha256> <file>: makes <file> a verified copy of <url>, downloading it when needed.
download() {
	local url="$1" sha="$2" file="$3"
	if ! verify "$file" "$sha"; then
		echo "downloading $url" >&2
		curl -fsSL --retry 3 -o "$file.part" "$url"
		if ! verify "$file.part" "$sha"; then
			echo "checksum mismatch for $url: expected $sha, got $(sha256sum "$file.part" | cut -d' ' -f1)" >&2
			rm -f "$file.part"
			exit 1
		fi
		mv "$file.part" "$file"
	fi
}

# sparse_checkout <name> <repo> <commit> <pattern>...: a blobless, sparse, depth-1 checkout of
# <commit> into $SUITES/<name> containing only the paths matching the gitignore-style patterns.
sparse_checkout() {
	local name="$1" repo="$2" commit="$3"
	shift 3
	local dir="$SUITES/$name"
	if is_current "$dir" "$commit" && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$commit" ]; then
		echo "$name already at $commit"
		return
	fi
	rm -rf "$dir"
	git init -q "$dir"
	git -C "$dir" remote add origin "$repo"
	git -C "$dir" config core.sparseCheckout true
	printf '%s\n' "$@" > "$dir/.git/info/sparse-checkout"
	git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$commit"
	git -C "$dir" checkout -q FETCH_HEAD
	echo "$commit" > "$dir/.pinned"
	echo "$name at $commit: $(find "$dir" -type f -not -path '*/.git/*' -not -name .pinned | wc -l) files"
}

# nst/JSONTestSuite: only the cases (the repository is 87 MB because of parsers/ and results/).
sparse_checkout JSONTestSuite "$NST_REPO" "$NST_COMMIT" \
	'/LICENSE' '/README.md' '/test_parsing/' '/test_transform/'

# simdjson-data: the jsonchecker collection and the standard real-world inputs.
sparse_checkout simdjson-data "$SIMDJSON_DATA_REPO" "$SIMDJSON_DATA_COMMIT" \
	'/README.md' '/jsonchecker/' \
	'/jsonexamples/apache_builds.json' '/jsonexamples/canada.json' '/jsonexamples/citm_catalog.json' \
	'/jsonexamples/github_events.json' '/jsonexamples/gsoc-2018.json' '/jsonexamples/instruments.json' \
	'/jsonexamples/marine_ik.json' '/jsonexamples/mesh.json' '/jsonexamples/mesh.pretty.json' \
	'/jsonexamples/numbers.json' '/jsonexamples/random.json' '/jsonexamples/twitter.json' \
	'/jsonexamples/twitterescaped.json' '/jsonexamples/update-center.json' \
	'/jsonexamples/amazon_cellphones.ndjson'

# nativejson-benchmark: the 27 round-trip cases (its jsonchecker copy duplicates JSON_checker).
sparse_checkout nativejson "$NATIVEJSON_REPO" "$NATIVEJSON_COMMIT" \
	'/LICENSE' '/data/roundtrip/'

# yajl: parsing cases with expected event traces.
sparse_checkout yajl "$YAJL_REPO" "$YAJL_COMMIT" \
	'/COPYING' '/test/parsing/'

# json5-tests: the whole repository (about 100 small files).
sparse_checkout json5-tests "$JSON5_TESTS_REPO" "$JSON5_TESTS_COMMIT" '/*'

# node-jsonc-parser: its tests are TypeScript with inline cases; fetched as the reference to port from,
# together with the scanner and parser they exercise.
sparse_checkout jsonc-parser "$JSONC_REPO" "$JSONC_COMMIT" \
	'/LICENSE.md' '/README.md' '/src/test/' '/src/impl/scanner.ts' '/src/impl/parser.ts' '/src/main.ts'

# json-canonicalization: RFC 8785 input/output vectors.
sparse_checkout json-canonicalization "$JCS_REPO" "$JCS_COMMIT" \
	'/LICENSE' '/README.md' '/testdata/'

# JSON_checker (json.org): 3 pass and 33 fail documents.
DIR="$SUITES/JSON_checker"
if is_current "$DIR" "$JSON_CHECKER_SHA256"; then
	echo "JSON_checker already at test.zip $JSON_CHECKER_SHA256"
else
	download "$JSON_CHECKER_URL" "$JSON_CHECKER_SHA256" "$DOWNLOADS/JSON_checker-test.zip"
	rm -rf "$DIR" "$SUITES/.JSON_checker.tmp"
	mkdir -p "$SUITES/.JSON_checker.tmp"
	unzip -q "$DOWNLOADS/JSON_checker-test.zip" -d "$SUITES/.JSON_checker.tmp"
	mv "$SUITES/.JSON_checker.tmp/test" "$DIR"
	rm -rf "$SUITES/.JSON_checker.tmp"
	echo "$JSON_CHECKER_SHA256" > "$DIR/.pinned"
	echo "JSON_checker: $(find "$DIR" -name '*.json' | wc -l) files"
fi

# RFC 8785 number serialization vector: a ranged download of the head of the gzip stream, decompressed
# up to the truncation point and cut to exactly $ES6_LINES lines, then checked against the published hash.
DIR="$SUITES/es6-numbers"
FILE="$DIR/es6testfile-$ES6_LINES.txt"
if verify "$FILE" "$ES6_SHA256"; then
	echo "es6-numbers already has $ES6_LINES lines"
else
	mkdir -p "$DIR"
	echo "downloading the first $ES6_LINES lines of $ES6_URL" >&2
	curl -fsSL --retry 3 -r "0-$ES6_RANGE" -o "$DOWNLOADS/es6testfile.head.gz" "$ES6_URL"
	# gzip reports "unexpected end of file" for the truncated stream; head closing the pipe early is
	# also expected, so the pipeline's status is ignored and the result is judged by its hash.
	{ gzip -dc "$DOWNLOADS/es6testfile.head.gz" 2>/dev/null || true; } | head -n "$ES6_LINES" > "$FILE.part" || true
	rm -f "$DOWNLOADS/es6testfile.head.gz"
	if ! verify "$FILE.part" "$ES6_SHA256"; then
		echo "checksum mismatch for the first $ES6_LINES lines of $ES6_URL" >&2
		rm -f "$FILE.part"
		exit 1
	fi
	mv "$FILE.part" "$FILE"
	echo "es6-numbers: $(wc -l < "$FILE") lines"
fi

# parse-number-fxx-test-data: raw files at the pinned commit, each verified by SHA-256.
DIR="$SUITES/parse-number-fxx"
mkdir -p "$DIR"
download "https://raw.githubusercontent.com/nigeltao/parse-number-fxx-test-data/$FXX_COMMIT/LICENSE" \
	"c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4" "$DIR/LICENSE"
count=0
while read -r name sha; do
	[ -n "$name" ] || continue
	download "$FXX_BASE/$name.txt" "$sha" "$DIR/$name.txt"
	count=$((count + 1))
done <<< "$FXX_FILES"
echo "parse-number-fxx at $FXX_COMMIT: $count data files, $(cat "$DIR"/*.txt | wc -l) lines"
