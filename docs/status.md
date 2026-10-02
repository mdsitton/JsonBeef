# JsonBeef status

Last reviewed: 2026-10-02 (phase 2 done).

## Verification baseline

| Check | Expected result |
|-------|-----------------|
| `beefbuild -test` (Debug checks) | 167/167 pass |
| `beefbuild -test -config=TestRelease` (Release settings) | 167/167 pass |
| `bash ./test-json-suite.sh` (Debug `JsonTester`; run `beefbuild` first) | In each of the document, events, stream1, stream16, rewrite and rewrite-pretty modes: nst 107/107 accepted (95 `y_` + 12 `i_`) and 211/211 rejected (188 `n_` + 23 `i_`); nst transform 16/16 accepted with the committed outputs, 6/6 rejected; JSON_checker 5/5 and 31/31; simdjson jsonchecker 33/33 and 75/75; adversarial 1457/1457 rejected without a crash; nativejson 27/27; json5-tests (strict) 25/25 and 89/89. Accepted cases match the oracle's canonical form byte for byte; rejected ones their golden message (`tests/errors/`). Then nativejson written back by the compact writer 27/27 byte for byte, and RFC 8785 vectors 6/6 |
| `BIN=./build/Release_Linux64/JsonTester/JsonTester bash ./test-json-suite.sh` (run `beefbuild -config=Release` first) | Same as Debug |
| `bash ./test-json-corpus.sh` (and with the Release `BIN`) | The 14 simdjson-data jsonexamples files: canonical form in 6 modes equal to the oracle's, compact writer a fixed point; twitter/twitterescaped strings equal; mesh/mesh.pretty RFC 8785 output equal; 27 JSON Pointer lookups agree with the oracle |
| `bash ./test-json-numbers.sh` (and with the Release `BIN`) | fxx: 1,414,285 lines, 0 mismatches (1,414,116 numbers bit-exact in f64 and f32, 169 non-JSON strings rejected, 30,700 overflows); es6: 100,000 lines, 0 mismatches (writes and reads) |
| `bash ./test-leaks.sh` | No leaks (LeakSanitizer over the TestRelease `[Test]`s) |
| `beefbuild-win -test`, `beefbuild-win -test -config=TestRelease` (`~/development/beef-proton`) | 167/167 pass |
| `tests/fetch-suites.sh` | Pinned suites in `tests/suites/` (`docs/test-suites.md`) |
| `bench/compare/run.sh` | The existing implementations, four tracks; refuses to run above load average 2. No timed run yet (the machine has stayed loaded); JsonBeef joins in phase 3 |

Any change to `.bf` files must keep these green in both Debug and Release.

## Feature status

| Area | State |
|------|-------|
| Pull reader (`JsonReader`): memory and `Stream` input, UTF-8 validation, BOM, UTF-16/32 detection, iterative nesting, numbers, strings, located errors, limits (depth, input, string, number, token) | Done (phase 1) |
| Number conversion and formatting (`JsonNumber`): exact integers, correctly rounded doubles and floats, plain and ECMAScript layouts | Done (phase 1) |
| `JsonTester` (canonical form, `-stream N`, `-fxx`, `-es6`), `test-json-suite.sh`, `test-json-numbers.sh`, `test-leaks.sh`, the oracle | Done (phase 1) |
| Document (`JsonDocument`, `JsonNode`): memory, file and stream reads, navigation, lookups with a member index past 16 members, duplicate-name policies (KeepAll, LastWins, FirstWins, Error), JSON Pointer | Done (phase 2) |
| Writers: `JsonWriter` (compact, indented, escaping options, non-finite policy), `JsonDocument.Write` (plain floats keep `.0`), RFC 8785 canonical output; `test-json-corpus.sh` | Done (phase 2) |
| Mutation of documents | Phase 5 |
| Speed, benchmark columns | Phase 3 |
| Positions sidecar, collect-errors | Phase 4 |
| JSONC, PreserveStyle, mutation | Phase 5 |
| `[JsonObject]`, on-demand | Phase 6 |
| Sequences, JSON5, non-finite numbers, I-JSON, replacement modes, push streaming, Patch | Phase 7 |

## Open items

| ID | Item | Size |
|----|------|------|
| P3 | Phase 3: speed: JsonBeef columns in the four benchmark tracks, profile, fast paths; the timed run needs a quiet machine (load average under 2) | L |
| T | TomlTester's BJSON dependency could move to JsonBeef now that the document and writer exist (`plan.md` §9 open item 2): a separate step in TomlBeef, when the author asks | S |
| Q | Open questions (`plan.md` §9): the proposals are in use (floats keep `.0`, JCS separate; TomlTester moves later; a flat document only if phase 3 asks for one) | — |
