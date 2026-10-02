# Test suites and corpora

The reference for everything test-related in JsonBeef: which third-party test suites and corpora are
used, what each case expects, how a strict RFC 8259 parser (plus opt-in extensions) should judge every
implementation-defined case, and the planned test scripts. Facts below were checked on 2026-10-01; all
counts were computed from the fetched files with small scripts (strict-JSON classification with a
Python oracle, JSON5 and JSONC classification with the reference implementations `json5@2.2.3` and
`jsonc-parser@3.3.1`), and the rules in section 9 are precise enough to re-derive them.
`docs/spec-reference.md` (cited as "spec §n") has the rules the expectations come from.

Fetch everything with `tests/fetch-suites.sh` (into the git-ignored `tests/suites/`, about 112 MB):

| Directory | What | Pin | Size |
|---|---|---|---|
| `JSONTestSuite/` | nst/JSONTestSuite `test_parsing/` (318 cases) and `test_transform/` (22) | commit `1ef36fa0…` (2024-11-22) | 1.7 MB |
| `JSON_checker/` | json.org JSON_checker `test.zip` (3 pass, 33 fail) | SHA-256 `5abaf51d…7c02c0` | 5.7 KB |
| `simdjson-data/` | simdjson/simdjson-data `jsonchecker/` (incl. `minefield/`, `adversarial/`) and 15 standard inputs from `jsonexamples/` | commit `4197c425…` (2025-11-21) | 29 MB |
| `nativejson/` | miloyip/nativejson-benchmark `data/roundtrip/` (27) | commit `478d5727…` (2022-10-28) | 0.3 MB |
| `yajl/` | lloyd/yajl `test/parsing/cases` (58 cases + `.gold` traces) | commit `5e3a7856…` (2015-09-24) | 0.7 MB |
| `json5-tests/` | json5/json5-tests (114 cases) | commit `ceb24d40…` (2026-02-20) | 0.7 MB |
| `jsonc-parser/` | microsoft/node-jsonc-parser `src/test/` + scanner/parser sources | commit `164a8e9e…` (2026-09-29) | 0.3 MB |
| `json-canonicalization/` | cyberphone/json-canonicalization `testdata/` (RFC 8785 vectors) | commit `19d51d7f…` (2024-12-13) | 0.3 MB |
| `es6-numbers/` | First 100,000 lines of the RFC 8785 number file (`ES6_LINES=1000000` for 1M) | published prefix SHA-256 `22776e6d…` | 3.9 MB |
| `parse-number-fxx/` | nigeltao/parse-number-fxx-test-data `data/*.txt`, 10 files, 1,414,285 lines (`FXX_FULL=1` adds 3,885,708 more, 198 MB) | commit `55d79b18…`, per-file SHA-256 | 75 MB |

Git checkouts are blobless, sparse and depth 1; plain downloads are verified against hard-coded
SHA-256 sums; each directory has a `.pinned` stamp so reruns are no-ops (a rerun takes under a second).

---

## 1. nst/JSONTestSuite

<https://github.com/nst/JSONTestSuite>, MIT (Nicolas Seriot, 2016). The accompanying article "Parsing
JSON is a Minefield" (<https://seriot.ch/parsing_json.php>) explains the cases. The repository
is 87 MB because of `parsers/` (vendored implementations) and `results/`; only `test_parsing/`,
`test_transform/`, `LICENSE` and `README.md` are fetched. Last commit 2024-11-22; `test_parsing/` last
changed in 2020 (a file-name typo fix; the simdjson-data copy predates it) and its content in 2018.

### 1.1 Layout and counts

`test_parsing/` holds one file per case; the prefix is the expectation:

- `y_`: must be accepted (95);
- `n_`: must be rejected (188);
- `i_`: implementation-defined, "parsers are free to accept or reject" (35).

| Area | y_ | n_ | i_ |
|---|---:|---:|---:|
| array | 11 | 26 | 0 |
| number (incl. `y_number.json`) | 19 | 51 | 10 |
| object (incl. `y_object.json`) | 12 | 28 | 1 |
| string | 43 | 29 | 22 |
| structure | 10 | 49 | 2 |
| incomplete / multidigit / single | 0 | 5 | 0 |
| **total** | **95** | **188** | **35** |

Cross-check: a strict oracle (Python `json` with `NaN`/`Infinity` disabled, strict UTF-8 decoding, no
BOM, lone surrogates rejected) accepts exactly the 95 `y_` files and rejects all 188 `n_` files (175
syntax, 12 invalid UTF-8, 1 BOM-only), so no `y_`/`n_` case is wrong for an RFC 8259 parser. Cases worth
knowing: `n_structure_100000_opening_arrays` (100,000 `[`, 100 KB) and `n_structure_open_array_object`
(50,000 levels of `[{"":`, 250 KB) crash recursive parsers (jsonc-parser 3.3.1 dies with
`RangeError: Maximum call stack size exceeded` on both); `n_multidigit_number_then_00` and
`n_structure_null-byte-outside-string` put a NUL after/inside the structure; `n_structure_UTF8_BOM_no_data`
is a BOM with nothing after it; `y_string_space.json` is the top-level string `" "`;
`y_structure_lonely_*` are top-level scalars.

### 1.2 The i_ cases: JsonBeef's stance (default configuration)

"Accept/reject" is the parse result with default settings; the option column says what changes it.
The last column is from the suite's own results matrix (section 1.3): how many of the 67 parser
versions tested accepted / rejected / crashed.

| Case | Content | Stance | Reason | Option | Matrix a/r/c |
|---|---|---|---|---|---|
| `i_number_double_huge_neg_exp` | `[123.456e-789]` | **accept** → +0 | Valid grammar; underflow rounds to zero (spec §9.6) | | 61/6/0 |
| `i_number_huge_exp` | `[0.4e00669999…969999999006]` (exponent of ~130 digits) | **accept**; double → `NumberOutOfRange` | Valid grammar; exponent accumulation must saturate | `NumberOverflow = Infinity` → +∞ | 48/15/4 |
| `i_number_neg_int_huge_exp` | `[-1e+9999]` | **accept**; double → `NumberOutOfRange` | as above | → −∞ | 54/13/0 |
| `i_number_pos_double_huge_exp` | `[1.5e+9999]` | **accept**; double → `NumberOutOfRange` | as above | → +∞ | 55/12/0 |
| `i_number_real_neg_overflow` | `[-123123e100000]` | **accept**; double → `NumberOutOfRange` | as above | → −∞ | 57/10/0 |
| `i_number_real_pos_overflow` | `[123123e100000]` | **accept**; double → `NumberOutOfRange` | as above | → +∞ | 55/12/0 |
| `i_number_real_underflow` | `[123e-10000000]` | **accept** → +0 | Underflow | | 59/7/1 |
| `i_number_too_big_neg_int` | `[-123123123123123123123123123123]` | **accept**: big integer (exact text, double −1.2312312312312312e29) | Beyond int64 | | 58/9/0 |
| `i_number_too_big_pos_int` | `[100000000000000000000]` | **accept**: big integer (double 1e20) | Beyond uint64 | | 58/9/0 |
| `i_number_very_big_negative_int` | `[-237462374673276894279832749832423479823246327846]` | **accept**: big integer | Beyond int64 | | 58/9/0 |
| `i_object_key_lone_2nd_surrogate` | `{"\uDFAA":0}` | **reject** | Lone surrogate, not representable in UTF-8 (spec §5.2; RFC 8259 §9 "character contents") | `InvalidSurrogates = Replace` / `Wtf8` → accept | 35/31/1 |
| `i_string_1st_surrogate_but_2nd_missing` | `["\uDADA"]` | **reject** | Lone high surrogate | as above | 33/34/0 |
| `i_string_1st_valid_surrogate_2nd_invalid` | `["\uD888ሴ"]` | **reject** | High followed by a non-low escape | as above | 33/34/0 |
| `i_string_incomplete_surrogate_and_escape_valid` | `["\uD800\n"]` | **reject** | High followed by another escape | as above | 33/34/0 |
| `i_string_incomplete_surrogate_pair` | `["\uDd1ea"]` | **reject** | Lone low surrogate | as above | 35/31/1 |
| `i_string_incomplete_surrogates_escape_valid` | `["\uD800\uD800\n"]` | **reject** | Two highs | as above | 33/34/0 |
| `i_string_invalid_lonely_surrogate` | `["\ud800"]` | **reject** | Lone high | as above | 33/34/0 |
| `i_string_invalid_surrogate` | `["\ud800abc"]` | **reject** | High followed by text | as above | 33/34/0 |
| `i_string_inverted_surrogates_U+1D11E` | `["\uDd1e\uD834"]` | **reject** | Low then high | as above | 34/32/1 |
| `i_string_lone_second_surrogate` | `["\uDFAA"]` | **reject** | Lone low | as above | 35/31/1 |
| `i_string_UTF-8_invalid_sequence` | `E6 97 A5 D1 88 FA` | **reject** | `FA` is never valid UTF-8 (spec §5.3) | `InvalidUtf8 = Replace` → accept | 26/39/2 |
| `i_string_UTF8_surrogate_U+D800` | `ED A0 80` | **reject** | Encoded surrogate | as above (three U+FFFD) | 38/28/1 |
| `i_string_invalid_utf-8` | `FF` | **reject** | Invalid byte | as above | 28/37/2 |
| `i_string_iso_latin_1` | `E9` (Latin-1 é) | **reject** | Truncated sequence | as above | 28/38/1 |
| `i_string_lone_utf8_continuation_byte` | `81` | **reject** | Stray continuation | as above | 29/36/2 |
| `i_string_not_in_unicode_range` | `F4 BF BF BF` | **reject** | Above U+10FFFF | as above | 32/33/2 |
| `i_string_overlong_sequence_2_bytes` | `C0 AF` | **reject** | Overlong | as above | 32/34/1 |
| `i_string_overlong_sequence_6_bytes` | `FC 83 BF BF BF BF` | **reject** | 6-byte form | as above | 28/37/2 |
| `i_string_overlong_sequence_6_bytes_null` | `FC 80 80 80 80 80` | **reject** | 6-byte overlong NUL | as above | 28/37/2 |
| `i_string_truncated-utf-8` | `E0 FF` | **reject** | Truncated + invalid | as above | 26/40/1 |
| `i_string_utf16BE_no_BOM` | `00 5B 00 22 …` | **reject** | UTF-16 is not supported (RFC 8259 §8.1) | none (transcode first) | 10/57/0 |
| `i_string_utf16LE_no_BOM` | `5B 00 22 00 …` | **reject** | as above | none | 9/58/0 |
| `i_string_UTF-16LE_with_BOM` | `FF FE 5B 00 …` | **reject** | as above | none | 9/57/1 |
| `i_structure_500_nested_arrays` | `[`×500 `]`×500 | **accept** | Depth 500 ≤ recommended `MaxDepth = 1024` (spec §13); with the siblings' 256 it would be a depth-limit reject | `MaxDepth` | 54/11/2 |
| `i_structure_UTF-8_BOM_empty_object` | `EF BB BF {}` | **accept** | RFC 8259 §8.1 "MAY ignore" a BOM | `AllowBom = false` → reject | 26/41/0 |

Totals for the default configuration: **12 accepted** (10 numbers, the 500-deep arrays, the BOM) and
**23 rejected** (10 surrogate escapes, 10 invalid UTF-8, 3 UTF-16). Every rejection must be a clean,
located error with a specific kind (`InvalidSurrogate`, `InvalidUtf8`, `UnsupportedEncoding`), not a
generic syntax error. With `InvalidSurrogates = Wtf8` the expected canonical outputs of the 10 surrogate
cases are their `\udXXX` escapes (lowercase); with `Replace` each unpaired surrogate becomes U+FFFD.

### 1.3 The results matrix and known parser behaviors

`results/parsing.html` (1.4 MB, not fetched) is the matrix of all cases × parsers; `results/logs.txt`
(270 KB) lists only the unexpected results and every `i_` outcome, as `parser<TAB>status<TAB>file` with
status `IMPLEMENTATION_PASS`, `IMPLEMENTATION_FAIL`, `SHOULD_HAVE_PASSED`, `SHOULD_HAVE_FAILED`, `CRASH`
or `TIMEOUT`. It covers 67 parser versions (C, C++, C#, Go 1.7, Java, JavaScript, Lua, Obj-C, OCaml,
Perl, PHP, Python 2.7/3.5, R, Ruby, Rust, Swift, ...), mostly from 2016–2019, so treat it as history, not
as current behavior: 1,002 `SHOULD_HAVE_FAILED` and 444 `SHOULD_HAVE_PASSED` lines, 70 crashes and 2
timeouts across all parsers. Patterns that are still relevant:

- **Huge-exponent numbers** split the field: Go 1.7, RapidJSON, nlohmann, jansson, Json.NET and Apple's
  parsers rejected overflow; JavaScript, Python, Jackson, System.Text.Json accepted (as ±Infinity).
  `i_number_huge_exp` crashed 4 parsers (exponent accumulator overflow).
- **Lone surrogate escapes** split the field almost evenly (33–35 accept vs 31–34 reject): UTF-16-based
  runtimes (JavaScript, Java, .NET, Python) accept, UTF-8-based ones (Rust, C, C++, Perl, PHP) reject.
- **Invalid UTF-8** was accepted by about 40% of parsers, often because the test harness decoded the
  bytes with replacement before parsing (Go, JavaScript, .NET in the matrix).
- **UTF-16 input** was rejected by nearly everyone (Jackson, Json.NET and Apple's NSJSONSerialization
  autodetect it).
- **BOM**: 26 accept, 41 reject.
- **Depth**: 11 parsers rejected 500 levels, 2 crashed. The two `n_structure` deep cases account for
  most of the 70 crashes.

### 1.4 The transform tests: JsonBeef's expected output

`test_transform/` (22 files) has no expected results: the files probe what a parser *does* with valid
but awkward input (`results/transform.html` shows each parser's re-serialization). JsonBeef needs its own
expectations, written in the canonical form of section 9.2 and compared byte for byte (the NFC/NFD
cases only make sense byte-level):

| File | Input | Expected canonical output (default configuration) |
|---|---|---|
| `number_1.0` | `[1.0]` | `[1]` (float token; the document keeps it a float and the style-preserving writer keeps `1.0`) |
| `number_1.000000000000000005` | `[1.000000000000000005]` | `[1]` |
| `number_1000000000000000` | `[1000000000000000]` | `[1000000000000000]` |
| `number_10000000000000000999` | `[10000000000000000999]` | `[10000000000000000999]` (fits uint64) |
| `number_1e6` | `[1E6]` | `[1000000]` |
| `number_1e-999` | `[1E-999]` | `[0]` |
| `number_9223372036854775807` | | `[9223372036854775807]` (int64 max) |
| `number_-9223372036854775808` | | `[-9223372036854775808]` (int64 min) |
| `number_9223372036854775808` | | `[9223372036854775808]` (uint64) |
| `number_-9223372036854775809` | | `[-9223372036854776000]` (big integer → double; ECMAScript layout) |
| `object_key_nfc_nfd` | `{"é":"NFC","é":"NFD"}` (U+00E9 vs e+U+0301) | identical bytes: two distinct names, no normalization |
| `object_key_nfd_nfc` | reverse order | identical bytes |
| `object_same_key_different_values` | `{"a":1,"a":2}` | `{"a":1,"a":2}` (KeepAll; name lookup yields 2; `DuplicateNames = Error` rejects) |
| `object_same_key_same_value` | `{"a":1,"a":1}` | `{"a":1,"a":1}` |
| `object_same_key_unclear_values` | `{"a":0, "a":-0}` | `{"a":0,"a":-0}` (negative zero survives) |
| `string_1_escaped_invalid_codepoint` | `["\uD800"]` | error (default); `["\ud800"]` with `Wtf8`; `["U+FFFD"]` with `Replace` |
| `string_2_escaped_invalid_codepoints` | `["\uD800\uD800"]` | error; `["\ud800\ud800"]` (Wtf8) |
| `string_3_escaped_invalid_codepoints` | `["\uD800\uD800\uD800"]` | error; `["\ud800\ud800\ud800"]` (Wtf8) |
| `string_1_invalid_codepoint` | `["` ED A0 80 `"]` | error; with `InvalidUtf8 = Replace`: three U+FFFD |
| `string_2_invalid_codepoints` | two `ED A0 80` | error; six U+FFFD |
| `string_3_invalid_codepoints` | three `ED A0 80` | error; nine U+FFFD |
| `string_with_escaped_NULL` | `["A\u0000B"]` | `["A\u0000B"]` |

These 22 expectations (×3 configurations for the 6 string cases) are JsonBeef's own work and go in
`tests/nst/transform/<name>.out` (and `.wtf8.out`, `.replace.out`).

### 1.5 The n_ cases in extension modes

An extension must turn exactly the right `n_` cases into accepts and nothing else. Computed with the
reference implementations:

- `Comments` (jsonc-parser defaults): 3 cases become valid: `n_object_trailing_comment`
  (`{"a":"b"}/**/`), `n_object_trailing_comment_slash_open` (`{"a":"b"}//`),
  `n_structure_object_with_comment`. `n_object_trailing_comment_open` (`/**//`) and
  `n_object_trailing_comment_slash_open_incomplete` (`/`) stay invalid.
- `Comments` + `TrailingCommas` (jsonc-parser `allowTrailingComma`): those 3 plus `n_array_extra_comma`
  (`["",]`), `n_array_number_and_comma` (`[1,]`), `n_object_trailing_comma` (`{"id":0,}`) = 6.
  `n_array_double_extra_comma`, `n_object_several_trailing_commas` and `n_array_unclosed_trailing_comma`
  stay invalid.
- `AllowNonFiniteNumbers`: `n_number_NaN`, `n_number_infinity`, `n_number_minus_infinity` = 3
  (`n_number_-NaN`, `n_number_+Inf`, `n_number_Inf` stay invalid).
- `Json5` (json5 2.2.3): 36 cases: the 6 JSONC ones and the 3 non-finite ones, plus `n_number_-NaN`,
  `n_number_+1`, `n_number_0.e1`, `n_number_2.e3`, `n_number_2.e+3`, `n_number_2.e-3`, `n_number_-2.`,
  `n_number_.2e-3`, `n_number_hex_1_digit`, `n_number_hex_2_digits`, `n_number_neg_real_without_int_part`,
  `n_number_real_without_fractional_part`, `n_number_starting_with_dot`, `n_object_key_with_single_quotes`,
  `n_object_single_quote`, `n_object_unquoted_key`, `n_object_repeated_null_null` (`null` is an
  `IdentifierName` key), `n_string_single_quote`, `n_string_escape_x`, `n_string_invalid_backslash_esc`
  (`\a` → `a`), `n_string_escaped_emoji`, `n_string_escaped_ctrl_char_tab`, `n_string_backslash_00`,
  `n_string_unicode_CapitalU` (`\U` → `U`), `n_string_unescaped_tab`, `n_string_unescaped_ctrl_char`
  (raw controls other than line terminators are legal in JSON5 strings), `n_structure_whitespace_formfeed`.
  All 95 `y_` cases stay valid in every mode; the `i_` outcomes do not change.

The runner keeps these as `tests/nst/accept-<mode>.txt` and checks that each mode accepts exactly the
listed `n_` cases.

---

## 2. JSON_checker and its descendants

### 2.1 json.org JSON_checker

<https://www.json.org/JSON_checker/test.zip> (5,721 bytes, SHA-256 `5abaf51d…7c02c0`): Douglas
Crockford's 2006–2007 test set for his JSON_checker. `pass1.json`–`pass3.json` must be accepted;
`fail1.json`–`fail33.json` were written for RFC 4627. Under RFC 8259 two "fails" are valid:
`fail1.json` (a top-level string, "A JSON payload should be an object or array") and `fail18.json`
(20 nested arrays, "Too deep": JSON_checker's depth limit was 20). **Expected: accept 5 (pass1–3,
fail1, fail18), reject 31.** `pass1.json` is a good single smoke test (every escape, `E`/`e` exponents,
`1e00`, `2e-00`, `0.123456789e-12`, `23456789012E66`, a 20-character name made of escapes, `"\/"`).
No license file in the archive; the json.org JSON_checker source itself carries the "JSON License"
("The Software shall be used for Good, not Evil"), which is not open source, so nothing from json.org
is vendored. nativejson-benchmark's `data/jsonchecker/` and simdjson-data's `jsonchecker/pass0[1-3]`,
`fail0[1-33]` are copies (not fetched separately).

### 2.2 simdjson-data `jsonchecker/`

<https://github.com/simdjson/simdjson-data> (simdjson moved its test data here), README: "provided for
educational and testing purposes. Please check individual files for any specific licensing
information"; no license file.

- `pass01.json`–`pass27.json` (27; the first three are JSON_checker's): all valid. Notable: `pass04`
  (π to 100 digits and `0.000…0003` with 117 zeros), `pass05` (`12345678900000002170460276904689664.000000`),
  `pass11`/`pass12`/`pass21`/`pass22` (2^62, 2^31, 2^63, 2^64−1 at top level), `pass17` (values near
  the subnormal and max boundaries), `pass18` (`1000000000000000000e0` variants), `pass20`
  (`1.2e000000010`), `pass23` (`-5.96916642387374e-309`, subnormal), `pass25` (`4E-2147483674`),
  `pass26` (`1e` + 58 zeros = 1), `pass27` (`0e9999999999999999999999999999` = 0).
- `fail02.json`–`fail82.json` plus `fail01_EXCLUDE`, `fail18_EXCLUDE`, `fail39_EXCLUDE` and
  `fail41_toolarge` (81 files; there is no `fail40`). The strict oracle finds 6 of them valid JSON:
  `fail01_EXCLUDE` and `fail18_EXCLUDE` (the JSON_checker 4627-isms), `fail39_EXCLUDE` (duplicate name,
  "this is allowable as per the json spec"), `fail41_toolarge` (`18446744073709551616`, rejected by
  simdjson as a too-large integer), `fail60` (`[1e+1111]`) and `fail73`
  (`10000000000000000000000000000000000000000000e+308`), the last two rejected by simdjson as out of
  range. **Expected for JsonBeef: accept those 6 (the last two convert to `NumberOutOfRange`), reject
  75.** Notable rejects: `fail57` (`"\udc00\ud800\uggggxy"`), `fail66`–`fail69` (NUL bytes between
  digits/literals), `fail70` (empty file), `fail72` (NUL after trailing whitespace), `fail74` (an
  unclosed nested array), `fail76`/`fail77` (3-digit `\u` escapes), `fail80`
  (`7E-9223372036854775808` in an unclosed object), `fail81` (`""n`), `fail82` (`10.2.2`), and three
  invalid-UTF-8 files (`fail34`, `fail35`, `fail71`).
- `pass01.ndjson`, `pass02.ndjson` (valid line-delimited; `pass01` has values spanning lines, so it is
  concatenated JSON rather than strict JSON Lines), `fail01.ndjson` (line 2 is `["Gilbert", "2013", 24, true}`).
- `minefield/`: a copy of the nst `test_parsing/` set (identical except one file name typo,
  `n_string_unescaped_crtl_char`). Skipped by the runner (duplicate).
- `adversarial/issue150/`: 1,457 fuzzer-generated files (3.7 MB, from simdjson issue 150), all invalid
  JSON per the oracle (mostly long runs of garbage after a surrogate-pair escape in a name). **Expected:
  reject all 1,457, no crash, no timeout**: a cheap robustness corpus.

### 2.3 nativejson-benchmark round-trip cases

<https://github.com/miloyip/nativejson-benchmark> (MIT, Milo Yip), `data/roundtrip/roundtrip01.json`–
`roundtrip27.json`: tiny one-value arrays/objects (`[null]`, `[-1234567890123456789]`,
`[-9223372036854775808]`, `[0.0]`, `[-0.0]`, `[5e-324]`, `[2.225073858507201e-308]`,
`[2.2250738585072014e-308]`, `[1.7976931348623157e308]`, `{"a":null,"foo":"bar"}`, ...). The benchmark
requires parse → compact write to reproduce the file byte for byte. 24 of them already equal their
ECMAScript-layout canonical form; the other three (`[0.0]`, `[-0.0]`, `[1.7976931348623157e308]`) need
the ryu/serde layout (spec §9.5). **Expected**: all 27 round-trip exactly through the
style-preserving writer; through the plain compact writer, 24 or 27 depending on the chosen float
layout (a decision, section 9.8). The `data/jsonchecker/` copy is redundant; `data/*.json` are the
standard canada/citm/twitter inputs (section 7).

### 2.4 yajl test cases

<https://github.com/lloyd/yajl> (ISC), `test/parsing/cases/`: 58 inputs with `.gold` event traces
(`map open '{'`, `integer: 1`, `parse error: ...`, `memory leaks: 0`). The file prefix selects yajl
options: `ac_` allow comments, `ag_` allow trailing garbage, `am_` allow multiple values, `ap_` allow
partial values; `run_tests.sh` runs each case with **read buffer sizes 1 to 31** to stress streaming.
22 golds are errors. The verdicts are yajl's, not RFC 8259's: `high_overflow.json`
(`9223372036854775808`) and `low_overflow.json` (`-9223372036854775808`!) are "integer overflow"
errors in yajl but valid JSON; `isolated_surrogate_marker.json` is accepted by yajl. Use the inputs as
fixtures (especially `am_*` for the concatenated-values reader and the 1–31 buffer-size loop as the
streaming test pattern), not the traces.

---

## 3. Number corpora

### 3.1 parse-number-fxx-test-data

<https://github.com/nigeltao/parse-number-fxx-test-data> (Apache-2.0, Nigel Tao; last commit
2022-04-13). Strings extracted from other projects' test suites with their correctly rounded float16,
float32 and float64 bit patterns. Format, one case per line:

```
3C00 3F800000 3FF0000000000000 1
3D9A 3FB33333 3FF6666666666666 1.4
7C00 7F800000 7FF0000000000000 123.456e789
```

Columns (0-based byte ranges): f16 hex `[0..4]`, f32 hex `[5..13]`, f64 hex `[14..30]`, the ASCII
string `[31..]`. Overflow lines carry the infinity bit pattern. No string has a sign (no negative
cases); all are ASCII.

| File | Lines | JSON-grammar lines | f64 = +∞ | Longest | Size | Fetched by default |
|---|---:|---:|---:|---:|---:|---|
| `exhaustive-float16.txt` | 31,745 | 31,745 | 0 | 26 | 1.4 MB | yes |
| `freetype-2-7.txt` | 3,566 | 3,526 | 5 | 22 | 0.1 MB | yes |
| `google-double-conversion.txt` | 564,745 | 564,725 | 50 | 66 | 31.5 MB | yes |
| `google-wuffs.txt` | 10,744 | 10,690 | 85 | 1,024 | 0.4 MB | yes |
| `ibm-fpgen.txt` | 102,792 | 102,792 | 30,066 | 40 | 5.3 MB | yes |
| `lemire-fast-double-parser.txt` | 94,313 | 94,310 | 88 | 1,024 | 4.7 MB | yes |
| `lemire-fast-float.txt` | 3,299 | 3,293 | 123 | 1,024 | 0.1 MB | yes |
| `more-test-cases.txt` | 60 | 60 | 27 | 31 | 2.8 KB | yes |
| `tencent-rapidjson.txt` | 3,563 | 3,549 | 29 | 100 | 0.1 MB | yes |
| `ulfjack-ryu.txt` | 599,458 | 599,426 | 227 | 90 | 34.4 MB | yes |
| `remyoudompheng-fptest-0.txt` … `-3.txt` | 3,885,708 | 3,885,708 | 0 | 23 | 197.7 MB | `FXX_FULL=1` |
| **default total** | **1,414,285** | **1,414,116** | **30,700** | | **78 MB** | |
| **full total** | **5,299,993** | **5,299,824** | | | **276 MB** | |

"JSON-grammar lines" match RFC 8259's `number` production; the other 169 lines in the default set are
forms like `.0`, `.0001`, `9007199254740992.e-256`, `.2e-5678` (and other leading/trailing-point forms),
which a strict JSON number parser must reject. The remyoudompheng files are 3.9 million hard
round-trip cases (shortest-digit outputs near rounding boundaries from `TestTortureAtof64` in
remyoudompheng/fptest); the README reports the whole set (5.3M lines) parsing in under 7 s with
Wuffs' C++ test program on a 2016 laptop.

**How to run** (section 9.5): in one process, read each line, parse column 4 with JsonBeef's number
scanner and converter, and compare: non-JSON lines must be rejected by the scanner; JSON lines must give
the f64 bits exactly, with the 30,700 overflow lines giving `NumberOutOfRange` (or +∞ when the
overflow option is on); if `float` parsing is offered, compare f32 bits too (the f32 column exposes
double-rounding bugs). **Subsampling** for Debug builds: every line of `more-test-cases.txt`,
`freetype-2-7.txt`, `tencent-rapidjson.txt`, `lemire-fast-float.txt`, `google-wuffs.txt` (all the
long-mantissa and edge cases, 21,232 lines) plus every 25th line of the five larger files (`awk 'NR % 25 == 1'`,
deterministic, ~55,700 lines); Release runs everything. Also feed the 1,024-digit lines through the
full document parser (as `[<number>]`) to cover the token path, not just the converter.

### 3.2 RFC 8785 ECMAScript number vectors (es6testfile)

`https://github.com/cyberphone/json-canonicalization/releases/download/es6testfile/es6testfile100m.txt.gz`
(2,081,240,993 bytes gzipped, 100 million lines, 4.0 GB unpacked), referenced by RFC 8785 Appendix B.
Format: `hex-ieee,expected\n` with 1–16 hex digits (no leading zeros) for the binary64 bits and the
expected ECMAScript `Number::toString` text:

```
0,0
8000000000000000,0
1,5e-324
4340000000000001,9007199254740994
444b1ae4d6e2ef50,1e+21
3eb0c6f7a0b5ed8c,9.999999999999997e-7
```

The first 2,168 lines are fixed: 168 edge values (±1/3·10^k across the exponent range, the RFC's
Appendix B values, powers of ten, values next to 1, 2^53 and the subnormal/normal boundary), then 2,000
consecutive doubles starting at the smallest normal `0010000000000000`; the rest are SHA-256-derived
random finite doubles. `testdata/README.md` publishes the SHA-256 of the first 1,000 /
10,000 / 100,000 / 1,000,000 / 10,000,000 / 100,000,000 lines, so `fetch-suites.sh` fetches only the head
of the gzip stream with an HTTP range request (3 MB for 100,000 lines, 24 MB for 1,000,000), cuts it to
the line count and verifies that hash. The default 100,000 lines are checked into nothing; 1,000,000
lines (40 MB) via `ES6_LINES=1000000`. `testdata/numgen.go` and `numgen.js` regenerate any prefix
offline. Verified: a Python implementation of the layout rules in spec §9.5 matches all 100,000 lines.

**How to run**: both directions in one process. Writer: bits → JsonBeef's ECMAScript-layout writer →
must equal column 2 (with negative zero mapped to `0`, as JCS requires). Reader: column 2 → JsonBeef's
number parser → must give the bits back (except line 2, `-0` → `0`). Debug: the first 10,000 lines;
Release: all fetched lines.

### 3.3 Not fetched: other number data

| Source | URL / license | What | Use |
|---|---|---|---|
| Google double-conversion | <https://github.com/google/double-conversion> (BSD-3-Clause) | `test/cctest/gay-shortest.cc` (6.3 MB, 100,000 doubles with their shortest digits and decimal point, from David Gay's dtoa), `gay-precision.cc`, `gay-fixed.cc`, `gay-shortest-single.cc`; `test-strtod.cc` (59 KB of hand-picked strtod cases) | Writer oracle (shortest digits) if the es6 file is not enough; strtod cases are already in fxx `google-double-conversion.txt` |
| Ryu | <https://github.com/ulfjack/ryu> (Apache-2.0 or Boost) | `ryu/tests/d2s_test.cc`, `s2d_test.cc` (inline cases) | Already in fxx `ulfjack-ryu.txt` |
| fast_float supplemental test files | <https://github.com/fastfloat/supplemental_test_files> (Apache-2.0/MIT) | Large files of decimal strings with expected bits (same 4-column format as fxx) | More of the same; fetch only if a bug class appears |
| Jackson FastDoubleParser cases | `jackson-core/src/test/resources/data/FastDoubleParser_errorcases.txt` (934 KB, Apache-2.0), `floats-755.json` | Strings that broke the Java fast_float port | Optional extra regression input |
| serde_json `tests/lexical/` | <https://github.com/serde-rs/json> (MIT or Apache-2.0) | Rust unit tests of its float parser (inline) | Port a handful by hand (section 6) |

---

## 4. Extension suites

### 4.1 json5/json5-tests

<https://github.com/json5/json5-tests> (MIT, Aseem Kishore and contributors; last commit 2026-02-20).
114 cases in 8 directories (`arrays`, `comments`, `misc`, `new-lines`, `numbers`, `objects`,
`strings`, `todo`); the extension is the expectation:

| Extension | Meaning | Count | Strict JSON | JSON5 |
|---|---|---:|---|---|
| `.json` | Valid JSON, must stay valid JSON5 | 26 | accept 25 | accept 26 |
| `.json5` | Valid JSON5 only | 57 | reject | accept |
| `.js` | Valid ES5 but not JSON5 (legacy "noctal" `080`, `-098`, `0780`; `[,null]`, `[,]`) | 6 | reject | reject |
| `.txt` | Invalid ES5 (octal `010`, `0x`, `1e2.3`, comments-only documents, unterminated comment, raw newline in a string, `{10twenty: …}`) | 25 | reject | reject |

8 `.errorSpec` files give the reference implementation's error position and message for some invalid
cases (`{ at, lineNumber, columnNumber, message }`); positions are worth matching, messages are not.
One misnamed case: `comments/irregular-block-comment.json` (`true` followed by
`/*/* … /*/`) contains a comment, so it is **not** valid JSON; a strict-mode run must treat it as
JSON5-only. The two `todo/` cases (`unicode-unquoted-key.json5` with `ümlåût`,
`unicode-escaped-unquoted-key.json5` with `sigΣma`) are valid JSON5 that older reference versions
did not handle; json5 2.2.3 accepts both. Cross-check: json5 2.2.3 agrees with every extension label
(83 accepted, 31 rejected).

**Expected for JsonBeef**: strict mode accepts the 25 genuine `.json` files and rejects the other 89;
`Json5` mode accepts the 83 `.json`/`.json5` files and rejects the 31 `.js`/`.txt` files. jsonc-parser
3.3.1 with defaults accepts 36 (all 26 `.json` files and the 10 `.json5` files whose only JSON5 feature is
a comment: `comments/*-comment-*.json5`, `new-lines/comment-{lf,cr,crlf}.json5`), and with
`allowTrailingComma` 38 (plus `arrays/trailing-comma-array.json5`, `objects/trailing-comma-object.json5`);
JsonBeef's `Comments` and `Jsonc` modes must accept exactly those (`tests/json5/accept-comments.txt`,
`accept-jsonc.txt`).

### 4.2 microsoft/node-jsonc-parser tests

<https://github.com/microsoft/node-jsonc-parser> (MIT). The tests are TypeScript with inline cases, so
they are fetched for reference and ported by hand into JsonBeef fixtures. `src/test/json.test.ts` (28
tests: 57 `assertKinds` scanner checks, 35 `assertValidParse`, 17 `assertInvalidParse`, 8
`assertScanError`, 15 `assertTree`, 15 `assertVisit`, 26 `assertLocation`, ...), `edit.test.ts` (20
tests of `modify`/`applyEdits`), `format.test.ts` (38 formatter tests), `string-intern.test.ts` (2).
Worth porting:

- From `json.test.ts`: comments (`// …` at EOF, `/* … */` with CRLF, unterminated `/* …`), the string
  scan errors (`"\v"` invalid escape, raw TAB and NUL `InvalidCharacter`, raw LF ends the string),
  number tokenization (`01` and `-01` are two tokens; `-` and `.0` are unknown), keywords (`nulllll`,
  `True`, `foo-bar` are unknown), `parse: objects with errors`/`array with errors` (the recovered
  values define a collect-errors mode), `parse: disallow comments`, `parse: trailing comma` (6 valid
  with the option, 3 invalid without), `'1,1'` and `''` as errors.
- From `edit.test.ts` and `format.test.ts`: insertion/removal/replacement cases with exact expected text,
  the model for JsonBeef's style-preserving edits (comma handling, indentation inference, comments).

Cross-check of the reference against the nst suite: with defaults (comments on, trailing commas off)
jsonc-parser 3.3.1 accepts every `y_` case, accepts 3 `n_` cases (section 1.5), and crashes on the two
deep-nesting `n_` cases.

### 4.3 JSON Lines / NDJSON

No official suite. Sources of inputs: <https://jsonlines.org/examples/> (four tiny examples; the page
license is unstated), `simdjson-data/jsonexamples/amazon_cellphones.ndjson` (793 lines, all valid, 278
KB), `simdjson-data/jsonchecker/pass0[12].ndjson` and `fail01.ndjson`, and yajl's `am_*` cases. The
rules (spec §12.3, §12.4) are simple enough that hand-written fixtures under `tests/lines/` cover them:
blank lines (error vs. skip option), CRLF, missing final newline, a line with two values, a value
spanning lines, a BOM on line 1 (error: JSON Lines forbids it), invalid UTF-8 in one line with
continue-after-error, RS-separated sequences including the truncated-number rule.

---

## 5. RFC 8785 JCS test vectors

<https://github.com/cyberphone/json-canonicalization> (Apache-2.0, Anders Rundgren), `testdata/`:
6 cases, each as `input/<name>.json` (pretty, unsorted), `output/<name>.json` (canonical, no trailing
newline) and `outhex/<name>.txt` (the expected UTF-8 bytes in hex):

| Case | Tests |
|---|---|
| `arrays` | Sorting inside an array element (`"1"`, `"10"`, `"d"`), empty array |
| `french` | `peach`, `péché`, `pêche`, `sin`: code-unit order, not French collation |
| `structures` | Nested sorting, `"\n"` as a name, empty objects, `56.0` → `56` |
| `unicode` | `"Å"` stays two code points (no normalization) |
| `values` | The RFC §3.2.2 example: numbers, escapes (`\u000f` lowercase, `\/` → `/`, `B` → `B`) |
| `weird` | The RFC §3.2.3 sorting set plus `\u000a`, `</script>`, DEL (`\u007f` written raw) |

**Expected**: `JsonTester -jcs` reproduces all 6 outputs byte for byte; together with the es6 number
file (section 3.2) and the spec §16 JCS cases this covers RFC 8785. The repository's
`testdata/numgen.go`/`numgen.js` regenerate the number file. Other implementations listed in RFC 8785
Appendix G (Java, Go, .NET, Python, JavaScript) are in the same repository but not fetched.

---

## 6. Not fetched: unit-test collections worth porting

| Source | License | What to take |
|---|---|---|
| serde_json `tests/test.rs` (2,617 lines) | MIT or Apache-2.0 | `test_parse_number_errors` (`00`, `0x80`, `.0`, `1.`, `1.e1`, `1e+`, `100e777777777777777777777777777` → out of range with exact column), `test_parse_negative_zero` (`-0`, `-0.0`, `-0e2`, `-1e-400`, `-1e-4000000000000000000000000000000000000000000000000` all negative zero), `test_parse_f64` (`3.5E-2147483647`, `0.0100000000000000000001`, 309-digit integers equal to `1e308`, `0e1000000000000000000000000000000000000000000000`), `test_parse_string` (exact error columns, `"\uD83C￿"` lone surrogate), `test_byte_buf_de_invalid_surrogates` (the WTF-8 bytes for each surrogate pattern, a ready oracle for `InvalidSurrogates = Wtf8`), `test_stack_overflow` (127 levels OK, 129 → "recursion limit exceeded at line 1 column 128"), `test_roundtrip_f32` (`7.038531e-26`), `test_json_pointer` |
| ICRAR/ijson `tests/` (Python, inline) | BSD-3-Clause (Ivan Sagalaev) | The streaming event model (`start_map`, `map_key`, `number`, ...) and prefix-path matching (`item.a.b`), multiple-values and incomplete-input tests: a model for JsonBeef's pull reader and on-demand selection, not data |
| Jackson (`jackson-core`) | Apache-2.0 | Java tests with inline strings; `StreamReadConstraints` tests (depth, number length, string length, name length) as a checklist for JsonBeef's limits; the data files of section 3.3 |
| System.Text.Json (`dotnet/runtime` `src/libraries/System.Text.Json/tests`) | MIT | C# tests with inline data (`Utf8JsonReaderTests*.cs`: multi-segment input, i.e. buffer boundaries; `JsonReaderStateAndOptionsTests.cs`: depth and comment options) and a 1.3 MB `Strings.resx`; no reusable corpus |
| JSON Schema Test Suite | MIT | Out of scope (validation, not parsing); its 2,375 KB of `.json` files are all valid JSON and could serve as an extra must-parse corpus |

---

## 7. Real-world corpora

For correctness these are must-parse inputs, round-trip inputs and cross-mode equivalence inputs; the
benchmark work chooses its own speed inputs. The fetched set is the 12 standard files of the
simdjson/nativejson benchmarks plus `mesh.pretty.json`, `twitterescaped.json` and
`amazon_cellphones.ndjson` from simdjson-data. None has an explicit license: they are dumps of public
API responses or generated data distributed with benchmarks, so they are fetched, never vendored.

| File | Size | Content | Depth | Objects / arrays | Strings | Ints / floats | Correctness use |
|---|---:|---|---:|---|---:|---|---|
| `twitter.json` | 631,515 | Twitter search API response (Japanese text) | 11 | 1,264 / 1,050 | 18,099 | 2,108 / 1 | 95,406 non-ASCII bytes; 64-bit `id` next to `id_str` (int64 exactness) |
| `twitterescaped.json` | 562,408 | The same, all non-ASCII as `\u` escapes (31,818) | 11 | same | same | same | Same strings as `twitter.json` after unescaping, but its ids went through a double (`505874924095815681` → `505874924095815700`): equal to `twitter.json` only for strings |
| `citm_catalog.json` | 1,727,204 | Event catalog (French) | 8 | 10,937 / 10,451 | 26,604 | 14,392 / 0 | Many small objects, numeric-string keys |
| `canada.json` | 2,251,051 | GeoJSON outline of Canada | 8 | 4 / 56,045 | 12 | 46 / 111,080 | 17-digit coordinates (`-65.613616999999977`): parse correctness and shortest round trip (writes `-65.613617`) |
| `gsoc-2018.json` | 3,327,831 | Google Summer of Code 2018 projects (schema.org) | 4 | 3,793 / 0 | 34,128 | 0 / 0 | Long strings, 1,292 `\u` escapes, numeric-string keys `"0"`… |
| `github_events.json` | 65,132 | GitHub API events | 7 | 180 / 19 | 1,891 | 149 / 0 | URLs, nulls, booleans |
| `marine_ik.json` | 2,983,466 | three.js model | 12 | 9,680 / 28,377 | 38,268 | 130,225 / 114,950 | Mixed int/float arrays |
| `mesh.json` | 723,597 | 3D mesh (positions, normals, indices) | 5 | 3 / 3,610 | 11 | 40,613 / 32,400 | Float arrays |
| `mesh.pretty.json` | 1,577,353 | `mesh.json` pretty-printed **with sorted keys** | 5 | same | same | same | Equal to `mesh.json` only after key sorting: JCS output of both must be identical |
| `numbers.json` | 150,124 | 10,001 doubles in one array | 2 | 0 / 1 | 0 | 0 / 10,001 | Float parsing |
| `random.json` | 510,476 | Generated user records (Cyrillic names) | 6 | 4,001 / 1,001 | 33,005 | 5,002 / 0 | 103,482 non-ASCII bytes |
| `update-center.json` | 533,178 | Jenkins update-center metadata | 6 | 1,896 / 1,937 | 27,229 | 0 / 0 | String-heavy |
| `instruments.json` | 220,346 | Audio instrument definitions | 7 | 1,012 / 194 | 6,889 | 4,935 / 0 | Pretty-printed, many small ints |
| `apache_builds.json` | 127,275 | Jenkins (Apache) builds API | 4 | 884 / 3 | 5,289 | 2 / 0 | Escaped HTML in strings |
| `amazon_cellphones.ndjson` | 277,673 | 793 JSON Lines records | | | | | JSON Lines reader |

All 14 `.json` files are valid strict JSON with no duplicate names (checked). Not fetched from
simdjson-data: `semanticscholar-corpus.json` (8.6 MB), `google_maps_api_*`, `twitter_api_*`,
`twitter_timeline.json`, `repeat.json`, `tree-pretty.json`, `small/`, `generated/`. nativejson-benchmark
`data/` has `canada.json`, `citm_catalog.json`, `twitter.json` identical to the simdjson-data copies.

Corpus checks (section 9.6): every file parses in every reading mode with identical canonical output;
parse → write (compact and pretty) → parse gives the same canonical output; the style-preserving
writer reproduces each file byte for byte; `JsonTester -jcs mesh.json` = `-jcs mesh.pretty.json`;
JSON Pointer lookups of a few known paths (`/statuses/0/id_str`) agree between the document and the
on-demand reader.

---

## 8. Licensing: why everything is fetched, not vendored

JsonBeef is MIT. The suites' terms:

- nst/JSONTestSuite: MIT (could be vendored with its notice).
- json5-tests: MIT. jsonc-parser: MIT. nativejson-benchmark: MIT. yajl: ISC. JCS vectors: Apache-2.0.
  parse-number-fxx-test-data: Apache-2.0 (the extracted strings come from projects under their own
  licenses: double-conversion BSD-3, Ryu Apache-2.0/Boost, RapidJSON MIT, FreeType FTL/GPL, IBM fpgen
  under IBM's terms).
- JSON_checker `test.zip`: no license; the json.org JSON_checker code uses the non-free "JSON License".
- simdjson-data: no license ("educational and testing purposes"); its corpora are third-party API dumps
  (Twitter, GitHub, Jenkins, Google Summer of Code) with no stated terms.
- The es6 number file: generated data from an Apache-2.0 repository.

Mixed and missing licenses, plus size (the number data alone is 75–276 MB), make fetching at pinned
versions the uniform rule: `tests/fetch-suites.sh` downloads into the git-ignored `tests/suites/`, and
nothing derived from those files (manifests, expected outputs computed from them) is committed. What
the repository does commit is JsonBeef's own work: expectation lists, expected-deviation lists, golden
error messages, the transform expectations of section 1.4, hand-written fixtures and ported test cases
(rewritten, with attribution in comments).

---

## 9. Planned test scripts and expectation files

Modeled on XmlBeef's `test-xml-conformance.sh` and KdlBeef's `test-kdl-spec.sh`.

### 9.1 JsonTester interface the scripts need

- `JsonTester [mode flags] [extension flags] FILE` (or `-` for stdin): parse FILE; on success print the
  canonical form (section 9.2) to stdout and exit 0; on a parse error print
  `line:column: kind: message` (1-based, column in code points, as the siblings do) to stderr and exit
  1; a resource-limit error is also exit 1 with its own kind; usage errors exit 2; anything else (crash,
  assertion, leak report in the leak build) is a failure by definition.
- Reading modes, so every path is covered by the same expectations: `-document` (default: build the
  document, print from it), `-events` (print straight from the pull reader's events, no document),
  `-stream N` (read FILE through a Stream with an N-byte buffer, so refills land inside numbers,
  literals, `\u` escapes, surrogate pairs, multibyte UTF-8, CRLF and comments; the runner uses N = 1 and
  16), `-preserve` (read with style preservation and print the canonical form; `-preserve -echo`
  writes the document back unchanged instead, which must equal the input bytes), `-rewrite` (write
  compact, read back, print canonical: exit 3 if the writer's output is rejected), `-select POINTER`
  (on-demand: print the canonical form of the selected value only), `-collect` (collect-errors mode:
  print every error, exit 1 if any).
- Extension flags mirroring the config: `-comments`, `-trailing-commas`, `-jsonc` (both), `-json5`,
  `-nonfinite`, `-no-bom`, `-dup=keep|last|first|error`, `-utf8=error|replace`,
  `-surrogates=error|replace|wtf8`, `-overflow=error|infinity`, `-max-depth N`, `-ijson`.
- Output modes: `-jcs` (RFC 8785 output instead of the canonical form), `-lines`, `-concatenated`,
  `-rs` (sequence readers: one canonical line per value, errors as `record N: line:column: ...`).
- Batch modes for the number corpora (one process, millions of cases): `-fxx FILE...` and
  `-es6 FILE [-limit N] [-every K]`, printing `N checked, M mismatches` and the first mismatches, exit 1
  on any mismatch.

### 9.2 The canonical output format

Chosen to be exact (no information the parser exposes is lost), independent of formatting, trivially
reproducible by an oracle, and diffable. It is not RFC 8785: JCS sorts members (hiding order and
duplicate bugs) and rounds integers through binary64. Rules:

1. UTF-8, no BOM, no whitespace between tokens, **one `\n` at the end** (one value per line in the
   sequence modes).
2. Literals `null`, `true`, `false`.
3. Objects: **every member in document order, duplicates included** (whatever the `DuplicateNames`
   policy keeps: `KeepAll` by default), `{"name":value,...}`. Arrays in order.
4. Strings and names: `"` and `\` as `\"` `\\`; U+0008/0009/000A/000C/000D as `\b \t \n \f \r`; other
   U+0000–001F as `\u00xx` (lowercase hex); WTF-8 surrogates (only in `-surrogates=wtf8`) as `\udxxx`
   (lowercase); everything else raw UTF-8, including `/`, DEL, C1 controls, U+2028/2029 and
   noncharacters. (Identical to JCS string output, plus the surrogate rule.)
5. Numbers:
   - an integer token (no `.`, no exponent) whose value fits `int64` or `uint64`: its exact decimal
     value, except that the token `-0` prints `-0`;
   - every other number: its correctly rounded binary64 value in ECMAScript `Number::toString` layout
     (spec §9.5), with negative zero as `-0`; a value that overflows prints `Infinity` / `-Infinity`
     (the tester converts with the overflow option on so it can show the value; these are not JSON and
     appear only for the `i_number` overflow cases and their kin).
   So `[1.0]` → `[1]`, `[1E6]` → `[1000000]`, `[100000000000000000000]` → `[100000000000000000000]`,
   `[-9223372036854775809]` → `[-9223372036854776000]`, `[123e65]` → `[1.23e+67]`, `[-0.0]` → `[-0]`.
   The int-vs-float distinction is not visible in this form; it is covered by the style-preserving echo
   and by unit tests.

An oracle for this form is ~70 lines of Python (`json.loads` with `parse_int`/`parse_float` keeping the
token text, `parse_constant` raising, `object_pairs_hook` keeping pairs, strict UTF-8 decoding, explicit
BOM and lone-surrogate checks, `repr()` digits re-laid-out per spec §9.5). A prototype reproduced the
`y_` set, the transform expectations of section 1.4 and all 100,000 es6 lines. The runner computes
expected outputs with it at test time (`tests/tools/json-canonical.py`), so no expected output derived
from third-party files is committed; JsonBeef's own golden files (transform, errors) are committed.

**Is byte-level comparison needed?** Yes, everywhere: the form is deterministic, so `cmp` of stdout
against the expected file (or the oracle's output) is the comparison. Only the NFC/NFD and
duplicate-name transform cases would be broken by any normalizing comparison, which is why none is used.

### 9.3 `test-json-suite.sh`

1. Check `$BIN` (default `./build/Debug_Linux64/JsonTester/JsonTester`, `BIN=./build/Release_Linux64/…`
   for Release) and `tests/suites/JSONTestSuite/test_parsing` (else: "run `bash tests/fetch-suites.sh`").
2. Build the case list (section 9.4 table) from file names; apply `tests/suites-skip.txt`
   (`path<TAB>reason`, expected to stay empty).
3. For each case and each mode in `MODES` (default `document events stream1 stream16 preserve rewrite`;
   `select` and `collect` in their own passes), run `timeout 10 $BIN <flags> FILE` and judge:
   - must-accept: exit 0, and stdout equals the oracle's canonical output (or the committed `.out` file
     for transform cases); in `preserve -echo` mode stdout equals the input bytes;
   - must-reject: exit 1, and the first stderr line equals `tests/errors/<suite>/<case>.err` (golden
     `line:column: kind: message`, the same in every mode, so stream and document reading fail
     identically); `UPDATE_GOLDEN=1 MODES=document` rewrites them for review;
   - policy cases (the overflow numbers): accept, and the canonical output shows `Infinity`.
   Exit codes other than 0/1, timeouts and leak reports are always failures.
4. Extension passes: run the nst `n_` set and the json5-tests set with `-jsonc`, `-comments`,
   `-nonfinite` and `-json5`, and check that exactly the cases listed in `tests/nst/accept-<mode>.txt`
   / `tests/json5/accept-<mode>.txt` are accepted (and that every `y_` case still is).
5. Compare failures with `tests/expected-failures.txt` (`suite/case<TAB>mode<TAB>reason`): an unlisted
   failure fails the run, a listed case that passes fails it too ("remove it from the list");
   `UPDATE_EXPECTED=1` rewrites the list for review.
6. Log to `test-json-suite.log` (git-ignored via `test-*.log`) and print a summary per suite and mode:
   accepted x/N, rejected x/N, canonical matches, golden-error matches, crashes, timeouts, skips.

### 9.4 Expected outcomes per suite (default configuration)

| Suite | Must accept | Must reject | Notes |
|---|---:|---:|---|
| nst `y_` / `n_` / `i_` | 95 + 12 | 188 + 23 | `i_` per section 1.2 (the 5 overflow cases canonicalize to ±`Infinity`) |
| nst transform | 16 (+6 with the string options) | 6 | Expected outputs committed (section 1.4) |
| JSON_checker | 5 | 31 | `fail1`, `fail18` accepted |
| simdjson-data `jsonchecker` | 27 + 6 | 75 | `fail01_EXCLUDE`, `fail18_EXCLUDE`, `fail39_EXCLUDE`, `fail41_toolarge`, `fail60`, `fail73` accepted |
| simdjson-data `.ndjson` (with `-lines`/`-concatenated`) | 2 | 1 | `pass01.ndjson` needs `-concatenated` (values span lines) |
| simdjson-data `adversarial/issue150` | 0 | 1,457 | Crash/timeout check; no golden messages needed |
| nativejson round-trip | 27 | 0 | Plus `preserve -echo` byte equality (27) and compact-writer equality (24 or 27) |
| json5-tests | 25 (strict), 83 (`-json5`) | 89 (strict), 31 (`-json5`) | `irregular-block-comment.json` is JSON5-only |
| JCS vectors (`-jcs`) | 6 | 0 | Byte equality with `output/` |
| Real-world corpora | 14 + 793 lines | 0 | Section 7 checks |
| fxx (`-fxx`) | 1,414,116 numbers (5,299,824 full) | 169 strings | 30,700 overflow lines → `NumberOutOfRange` |
| es6 (`-es6`) | 100,000 writes + 99,999 reads | | |

### 9.5 `test-json-numbers.sh`

Runs `$BIN -fxx tests/suites/parse-number-fxx/*.txt` and `$BIN -es6
tests/suites/es6-numbers/es6testfile-*.txt`. In Debug (the default binary) it applies the subsampling of
section 3.1 and `-limit 10000` for es6; with a Release `BIN`, or `FULL=1`, everything. Mismatches are
printed with the input string, expected bits and actual bits; there is no expected-failure list (a
number mismatch is always a bug).

### 9.6 Other scripts

- `test-json-corpus.sh`: section 7's checks over `simdjson-data/jsonexamples` (and any extra directory
  given as an argument): every mode gives identical canonical output; compact and pretty rewrites read
  back to the same canonical output; `-preserve -echo` is byte-identical; the twitter/twitterescaped
  string equality and the mesh/mesh.pretty JCS equality; `-select` of a few pointers matches the
  document.
- `test-roundtrip.sh`: every accepted suite case (nst `y_`, JSON_checker pass, simdjson pass, json5 in
  `-json5`) through `-rewrite` and `-preserve -echo`; the style-preserving writer must reproduce comments
  and trailing commas in JSONC/JSON5 inputs byte for byte.
- `test-leaks.sh`: as in the siblings (Debug allocator leak report over every mode for a sample of
  accepted and rejected cases, including every error path).
- Unit tests (`beefbuild -test`): the spec §16 edge cases, ported serde_json/jsonc-parser cases,
  writer cases, limits, and a fixture-count floor so a missing fixture directory cannot pass silently.

### 9.7 Files the repository should carry

- `tests/tools/json-canonical.py`: the oracle (section 9.2).
- `tests/nst/transform/*.out` (+ `.wtf8.out`, `.replace.out`): section 1.4.
- `tests/nst/accept-{comments,jsonc,nonfinite,json5}.txt`, `tests/json5/accept-{comments,jsonc}.txt`: sections 1.5,
  4.1.
- `tests/errors/<suite>/<case>.err`: golden first error lines for every must-reject case.
- `tests/expected-failures.txt`, `tests/suites-skip.txt`: kept honest by the unexpected-pass rule,
  ideally empty at release.
- Hand-written fixtures: `tests/jsonc/` (ported jsonc-parser cases, edit/format cases), `tests/lines/`
  (section 4.3), `tests/limits/` (depth, sizes, many members, hash-flooding names, long numbers), and the
  spec §16 list as unit tests.

### 9.8 Decisions the plan must make

- **Default `MaxDepth`**: 1024 (accepts `i_structure_500_nested_arrays`, needs iterative parse/free/
  write) or the siblings' 256 (that `i_` case becomes a limit rejection).
- **Number overflow**: reject at conversion (recommended), reject at parse (serde/simdjson style), or
  ±Infinity (JS/Python style). This decides the 5 overflow `i_` cases' meaning, 30,700 fxx lines and
  simdjson `fail60`/`fail73`.
- **Big integers**: keep exact text + double (recommended) or reject beyond 64 bits (simdjson DOM).
- **Duplicate names**: default `KeepAll` with last-wins lookup (recommended), or `Error`; the default
  must accept `y_object_duplicated_key`.
- **Lone surrogates and invalid UTF-8**: error by default (recommended), and whether to offer `Replace`
  and `Wtf8` in the first version (the 6 transform string cases and 20 `i_` cases exercise them).
- **BOM**: skip by default (recommended) or reject.
- **Float layout of the plain writer**: ECMAScript (recommended; needed for JCS anyway) or ryu/serde
  (`.0` on integral doubles, no `+`); decides whether the nativejson compact round trip is 24/27 or
  27/27. Whether negative zero prints `-0` (recommended) or `-0.0`.
- **Typed mapping coercions**: integer fields from `1.0`/`1e2` (error recommended), numbers from strings
  (opt-in per field), unknown members (ignored, per I-JSON §4.2), float32 fields parsed directly.
- **Which extensions ship first**: JSONC (comments + trailing commas, separately switchable) is the
  config-file must-have; JSON5, non-finite tokens and the sequence readers can follow.
- **On-demand validation**: whether skipped values are fully validated in strict mode.
- **Collect-errors mode** (jsonc-parser-style recovery): in scope or not; it decides the `-collect` pass.
- **Use corlib `Double.Parse` (fast_float) and `double.ToString` (zmij)** for the slow paths, or port
  Eisel–Lemire and a shortest-digit writer into JsonBeef (portability to `BF_RUNTIME_REDUCED`, wasm).
