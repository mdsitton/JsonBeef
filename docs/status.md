# JsonBeef status

Last reviewed: 2026-10-02 (phases 1–7 done; the first timed benchmark run is in).

## Verification baseline

| Check | Expected result |
|-------|-----------------|
| `beefbuild -test` (Debug checks) | 281/281 pass |
| `beefbuild -test -config=TestRelease` (Release settings) | 281/281 pass |
| `bash ./test-json-suite.sh` (Debug `JsonTester`; run `beefbuild` first) | In each of the document, events, stream1, stream16, push1, push7 (a JsonPushReader fed 1 or 7 bytes at a time), rewrite, rewrite-pretty, collect, stream-collect and preserve modes: nst 107/107 accepted (95 `y_` + 12 `i_`) and 211/211 rejected (188 `n_` + 23 `i_`); nst transform 16/16 accepted with the committed outputs, 6/6 rejected; JSON_checker 5/5 and 31/31; simdjson jsonchecker 33/33 and 75/75; adversarial 1457/1457 rejected without a crash; nativejson 27/27; json5-tests (strict) 25/25 and 89/89. Accepted cases match the oracle's canonical form byte for byte; rejected ones their golden message (`tests/errors/`). Then the extension modes: with `-comments` every `y_` case accepted and exactly the 3 listed `n_` cases and 36 json5-tests files, with `-jsonc` 6 and 38, with `-nonfinite` 3 and 28, with `-ijson` 0 and 24 and exactly the 10 listed `y_` cases rejected, with `-json5` 36 and 83 (`tests/nst/accept-*.txt`, `reject-ijson.txt`, `tests/json5/accept-*.txt`); every nst case and json5-tests file with `-json5` (as a document, as tokens, as tokens from 1-byte streams) agrees with `tests/tools/json5-canonical.py` (226 accepted with its canonical form, 206 rejected); every nst parsing and transform case with `-utf8=replace -surrogates=replace` (149 accepted, 191 rejected) and with `-surrogates=wtf8` (136, 204) agrees with the oracle under the same options, from memory and 1-byte streams; nativejson written back by the compact writer 27/27 byte for byte, and RFC 8785 vectors 6/6 |
| `bash ./test-roundtrip.sh` (and with the Release `BIN`) | 269 accepted inputs (the suites' strict ones, the 38 JSONC-accepted json5-tests files with `-jsonc`, the other 45 JSON5 ones with `-json5`, the 14 corpus files): PreserveStyle writes each back byte for byte from memory and from a 16-byte stream, and 3 seeds of random edits each (807 runs) read back into the edited document. Run with `SEEDS=10` (2,240 runs) during phase 5 |
| `BIN=./build/Release_Linux64/JsonTester/JsonTester bash ./test-json-suite.sh` (run `beefbuild -config=Release` first) | Same as Debug |
| `bash ./test-json-corpus.sh` (and with the Release `BIN`) | The 14 simdjson-data jsonexamples files: canonical form in 6 modes equal to the oracle's, compact writer a fixed point; twitter/twitterescaped strings equal; mesh/mesh.pretty RFC 8785 output equal; 27 JSON Pointer lookups agree with the oracle on the document (`-pointer`) and on demand (`-select`, from memory and from 7-byte stream reads) |
| `bash ./test-json-numbers.sh` (and with the Release `BIN`) | fxx: 1,414,285 lines, 0 mismatches (1,414,116 numbers bit-exact in f64 and f32, 169 non-JSON strings rejected, 30,700 overflows); es6: 100,000 lines, 0 mismatches (writes and reads) |
| `bash ./test-leaks.sh` | No leaks (LeakSanitizer over the TestRelease `[Test]`s) |
| `beefbuild-win -test`, `beefbuild-win -test -config=TestRelease` (`~/development/beef-proton`) | 281/281 pass (the Debug runtime's leak check at exit also passes: it breaks the run, exit code 0x80000003, on a leak LeakSanitizer can miss) |
| `tests/fetch-suites.sh` | Pinned suites in `tests/suites/` (`docs/test-suites.md`) |
| `bash ./test-json-lines.sh` (and with the Release `BIN`) | JsonSequenceReader against the oracle's `-lines` and `-concatenated`, from memory and from 7-byte stream reads: amazon_cellphones.ndjson (793 records), simdjson-data's three jsonchecker .ndjson files, 8 generated inputs (CRLF, empty lines, a BOM, ill-formed UTF-8, touching values) and every nst parsing case, both ways: 1,320 runs, 0 differences |
| `bash ./test-json-fuzz.sh` (and with the Release `BIN`) | The stream sweep: every suite input through streams fed 1 to 31 bytes per read (16,895 runs) reads as from memory; then 2 seeds × 50 rounds of every suite input (57,200 runs) and 3 rounds of the 14 real-world files: fast build, reader, 1-byte stream and a push reader fed 1 byte at a time agree on every mutation, with CollectErrors memory and stream give the same errors and recovered document, SkipValue (the fast loop from memory, the token loop from a stream; the whole value and the first one inside it) gives the reader's outcome, and with `InvalidUtf8.Replace` and `InvalidSurrogates.Wtf8`, and as JSON5 (with SkipValue there too), a document from memory, one from 1-byte streams and the reader's tokens agree; each document read, copied into another with SetValue, prints the same, is ValueEquals to it and passes a JSON Patch testing and replacing it with the original. Run with `SEEDS=3 ROUNDS=200` (343,326 runs, Release) at the end of phase 6: 0 disagreements |
| `bench/compare/run.sh` | The existing implementations and JsonBeef's columns in all four tracks: `JsonBeef` (DOM), `JsonBeef JsonReader` (streaming), `JsonBeef [JsonObject]` (typed), `JsonBeef JsonReader` (on-demand query). No quiet machine is assumed: each process samples until converged, and each cell runs processes until 3 of them agree within ±10% (at most 9; a cell that never settles is marked `~`). JsonBeef's check lines equal the reference on all 16 inputs in the DOM and streaming tracks and on twitter, citm_catalog and canada in the typed and query tracks (`./build.sh beef`). A full run takes about 95 minutes; remeasure JsonBeef's columns alone with `ONLY='JsonBeef.*'` (a partial rerun keeps every other cell and track) |
| `bash bench/instructions.sh` (after `beefbuild -config=Release`; `MODES="events document typed query"` after `bench/compare/build.sh beef`) | The instruction counts below |

Any change to `.bf` files must keep these green in both Debug and Release.

## Performance baseline

Timed run of 2026-10-02 (`bench/compare/results.md`, plots in `docs/benchmark-*.svg`; Ryzen 9 5900X,
single thread; load average 4–7 throughout, absorbed by run.sh's settling repeats: every JsonBeef cell
settled, and 4 cells of other libraries remain `~`). JsonBeef's MB/s and rank among the
implementations that passed each input:

| Track | twitter | twitterescaped | citm | canada | strings | floats | Rank, most inputs | Ahead of JsonBeef |
|---|---:|---:|---:|---:|---:|---:|---|---|
| DOM (`JsonBeef`) | 1,202 (2nd) | 627 (6th) | 1,621 (2nd) | 494 (4th) | 414 (20th) | 262 (8th) | 2nd–4th of 43–49 | simdjson DOM; yyjson and sonic-rs on most inputs |
| Streaming (`JsonReader`) | 860 (3rd) | 456 (9th) | 988 (5th) | 359 (4th) | 351 (10th) | 237 (3rd) | 3rd–8th of 18–20 | simdjson On-Demand, jiter; RapidJSON SAX and serde_json on numeric and string-heavy inputs |
| Typed (`[JsonObject]`) | 554 (7th) | | 752 (8th) | 259 (7th) | | | 7th–8th of 19–22 | glaze, sonic-rs, sonic, go-json, fastjson2, serde_json |
| On-demand (`Find`) | 824 (8th) | | 1,303 (6th) | 387 (5th) | | | 5th–8th of 13–14 | simdjson On-Demand, jiter, serde_json partial, pysimdjson |

For reference, yyjson's DOM does 1,027 on twitter and 1,637 on twitterescaped; simdjson's 3,046 and
1,947; jiter's streaming 940 and 469. The weak spots are escaped strings (strings, twitterescaped:
P3E) and the on-demand query, which is no faster than the full streaming pass on twitter (P6Q).

The load-independent measure, user-space instructions per input byte of the Release `JsonTester`
(`bench/instructions.sh`):
the event pass (`JsonReader` from memory, every string decoded and number converted), the document
read, and at the end of phase 3 also the event pass from a `Stream` (64 KiB buffer) and the compact
write:

| | twitter | twitterescaped | citm | canada | github | gsoc | mesh | numbers | marine_ik | tiny | rest | records | strings | integers | floats | events |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Events, phase 2 | 17.50 | 25.34 | 16.30 | 51.10 | 12.30 | 7.21 | 42.10 | 36.36 | 37.79 | 33.49 | 19.00 | 26.76 | 27.49 | 48.53 | 51.31 | 25.79 |
| Events, phase 3 | 13.39 | 23.87 | 12.07 | 43.67 | 10.57 | 4.93 | 39.23 | 27.00 | 35.53 | 30.35 | 15.81 | 23.79 | 26.77 | 35.55 | 46.63 | 23.39 |
| Document, phase 2 | 19.08 | 27.19 | 17.76 | 55.84 | 13.80 | 7.88 | 47.17 | 40.66 | 42.63 | 40.98 | 21.85 | 31.02 | 27.89 | 35.03 | 53.56 | 31.03 |
| Document, phase 3 | 11.85 | 19.55 | 9.39 | 39.09 | 9.22 | 5.03 | 31.19 | 23.63 | 28.76 | 27.44 | 14.12 | 20.70 | 22.23 | 20.80 | 45.42 | 20.79 |
| Stream events, phase 3 | 19.32 | 30.34 | 18.45 | 48.32 | 12.32 | 7.40 | 48.40 | 31.22 | 42.36 | 37.76 | 17.84 | 27.84 | 32.71 | 41.22 | 48.81 | 27.19 |
| Compact write, phase 3 | 17.60 | 19.76 | 10.67 | 47.16 | 13.95 | 7.66 | 49.11 | 52.17 | 43.17 | | | 35.97 | 4.82 | 28.83 | 35.90 | |
| Events, phase 6 | 14.69 | 24.25 | 13.42 | 43.60 | 11.73 | 5.32 | 42.27 | 26.86 | 36.30 | 31.38 | 16.36 | 24.70 | 26.82 | 36.17 | 46.66 | 24.28 |
| Document, phase 6 | 11.91 | 19.61 | 9.45 | 37.62 | 9.25 | 5.05 | 30.16 | 22.43 | 27.90 | 27.96 | 14.18 | 20.66 | 22.23 | 20.52 | 43.71 | 21.01 |
| Typed, phase 6 | 19.91 | | 18.99 | 60.55 | | | | | | | | | | | | |
| Query, phase 6 | 14.73 | | 10.63 | 40.19 | | | | | | | | | | | | |

About a third of canada's, floats' and numbers' document instructions are corlib's fast_float (17-digit
mantissas are past Clinger's fast path; plan §9 item 6 keeps fast_float).

The events pass grew by about 10% on twitter between phases 3 and 6 (13.39 to 14.69), with the token
path's changes of phases 4 and 5 (UTF-8 errors in document order, comments, trailing commas,
collect-errors); which of them costs what is not measured yet. Phase 7's JSON5 dialect checks add
about 1% more on twitter and citm_catalog (14.68 to 14.85 and 13.40 to 13.54; canada and every
document count unchanged); the non-finite, replacement and I-JSON options cost nothing measurable. Typed is the
`JsonBeef [JsonObject]` column's work (`JsonSerializer.Read` into the reference schema's classes:
every member bound, the objects allocated and deleted), query the on-demand column's
(`JsonReader.Find` and the queried values read, the rest skipped and checked through to the end of the
text): only twitter, citm_catalog and canada are in those tracks.

## Feature status

| Area | State |
|------|-------|
| Pull reader (`JsonReader`): memory and `Stream` input, UTF-8 validation, BOM, UTF-16/32 detection, iterative nesting, numbers, strings, located errors, limits (depth, input, string, number, token) | Done (phase 1) |
| Number conversion and formatting (`JsonNumber`): exact integers, correctly rounded doubles and floats, plain and ECMAScript layouts | Done (phase 1) |
| `JsonTester` (canonical form, `-stream N`, `-fxx`, `-es6`), `test-json-suite.sh`, `test-json-numbers.sh`, `test-leaks.sh`, the oracle | Done (phase 1) |
| Document (`JsonDocument`, `JsonNode`): memory, file and stream reads, navigation, lookups with a member index past 16 members, duplicate-name policies (KeepAll, LastWins, FirstWins, Error), JSON Pointer | Done (phase 2) |
| Writers: `JsonWriter` (compact, indented, escaping options, non-finite policy), `JsonDocument.Write` (plain floats keep `.0`), RFC 8785 canonical output; `test-json-corpus.sh` | Done (phase 2) |
| Errors and limits: located errors in document order (memory and streams alike), `JsonDiagnostic`, `MaxNodes`/`MaxMembers`, the `Untrusted` preset | Done (phase 4) |
| Positions (`JsonMetadataMode.Positions`: value and member-name ranges, lazy line/column) | Done (phase 4) |
| Collect-errors (reader recovery, `JsonDocument.Errors`) | Done (phase 4) |
| JSONC (`Comments`, `TrailingCommas`, the `Jsonc` and `Strict` presets) | Done (phase 5) |
| Mutation (setters, Add, Insert, Remove, Rename, CreateRoot) | Done (phase 5) |
| PreserveStyle (byte-exact writes, edits regenerated in their surroundings' style) | Done (phase 5) |
| `[JsonObject]` typed mapping: reading straight from the reader (strict kinds and ranges, duplicates, required and unknown members, errors with JSON Pointer paths, polymorphism by discriminator, converters, allocators), writing to a JsonWriter and into document nodes in place; `JsonSerializer` (texts, streams, files, nodes) | Done (phase 6) |
| On demand: `SkipValue` (checks what it skips; a fast loop for memory input), `ReadRaw`, the reader's `Find`; `JsonTester -select` | Done (phase 6) |
| Speed: fast paths and the benchmark columns of all four tracks | Done (phases 3 and 6); timed run of 2026-10-02 in `bench/compare/results.md` |
| Non-finite numbers (`AllowNonFiniteNumbers`), replacement modes (`InvalidUtf8`, `InvalidSurrogates`: Replace, Wtf8 with the writer's `\udxxx`), the I-JSON check (`IJson`) | Done (phase 7) |
| JSON5 (`JsonDialect.Json5`, the `Json5` preset): identifier and single-quoted names, JSON5 strings and escapes, hexadecimal and other JSON5 numbers reported as JSON numbers, JSON5 whitespace | Done (phase 7) |
| Sequences (`JsonSequenceReader`: JSON Lines, concatenated, RFC 7464; memory and streams) | Done (phase 7) |
| Push streaming (`JsonPushReader`: `Feed`/`Finish`, whole tokens only, every chunk size reads as the whole input) | Done (phase 7) |
| JSON Patch (`JsonPatch.Apply`, RFC 6902: all or nothing, `test` by value), Merge Patch (`JsonPatch.Merge`, RFC 7396), `JsonNode.SetValue` (deep copy from any document) and `ValueEquals`; `JsonTester -patch`/`-merge-patch` | Done (phase 7). Checked once, outside the committed tests, against json-patch-tests (108 enabled cases, 0 failures) |

## Open items

| ID | Item | Size |
|----|------|------|
| P3E | Escaped strings are JsonBeef's weak spot: DOM strings 414 MB/s (20th; yyjson 945, sonic-rs 1,064), twitterescaped 627 (6th; yyjson 1,637). The decoding loop after the first `\` (escapes, `\u` pairs, the copy into the decode buffer) is the place to look; profile with `perf` on the Release `JsonTester -bench` | M |
| P6Q | The on-demand query is no faster than the full streaming pass on twitter (824 MB/s against 860) and only 1.3× on citm_catalog (1,303 against 988), where simdjson's on-demand gains 1.6–1.8× over its streaming: skipped values pay for more than structure (SkipValue checks every string and number it skips, by design), but the gap says the skip loop or Find's member matching costs more than it should | M |
| P3S | The stream event pass costs 1.3–1.5× the memory one in instructions (XmlBeef got its to 1.1–1.3×): the reader's `Grow` checks in scans | S |
| P6T | Typed binding's overhead over the event pass in instructions (twitter 19.9 per byte against 14.7; citm_catalog 19.0 against 13.4): the generated member matching (User's 40 fields: about 2 per byte), allocation (about 1), and the per-token calls through `JsonReader`'s memory/stream dispatch. The timed run puts the typed track 7th–8th (twitter 554 MB/s against glaze's 911 and sonic-rs's; citm_catalog 752 against glaze's 2,104), the furthest JsonBeef is from the front | M |
| P6S | The on-demand fast loop serves memory input only; streams skip through the token loop | S |
| P7S | json-patch-tests (github.com/json-patch/json-patch-tests: `tests.json`, `spec_tests.json`) could join `tests/fetch-suites.sh` as a pinned suite with a runner over `JsonTester -patch`; checked once by hand so far, when the author agrees to add a suite | S |
| T | TomlTester's BJSON dependency could move to JsonBeef now that the document and writer exist (`plan.md` §9 open item 2): a separate step in TomlBeef, when the author asks | S |
| Q | Open questions (`plan.md` §9): the proposals are in use (floats keep `.0`, JCS separate; TomlTester moves later; a flat document only if phase 3 asks for one: the timed run does not, the DOM is 2nd–4th on most inputs) | — |