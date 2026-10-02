# JsonBeef: implementation plan and handoff

JsonBeef is a JSON (RFC 8259) parser and writer for the Beef programming language: fully correct by
default, fast, with located errors, and with the opt-in extensions config files need (JSONC comments
and trailing commas, JSON5, JSON Lines). It is the fourth sibling of TomlBeef
(`~/development/TomlBeef`), KdlBeef (`~/development/KdlBeef`) and XmlBeef (`~/development/XmlBeef`)
and reuses their design, tooling and, where it fits, their code: a pull reader under an ID-based
document, compile-time typed mapping, a Positions/PreserveStyle sidecar, resource limits and streams.

This document is the handoff for the session that starts the implementation. Read with it:

- `docs/spec-reference.md` — RFC 8259 and ECMA-404 rule by rule, I-JSON, RFC 8785 (JCS), JSON
  Pointer, JSONC/JSON5/JSON Lines/RFC 7464, numbers in depth, security, writer and round-trip rules,
  and 167 edge cases worth a test.
- `docs/test-suites.md` — nst/JSONTestSuite with a per-case stance on the 35 `i_` cases, JSON_checker,
  simdjson's adversarial files, the number corpora (1.4M lines), json5 and jsonc tests, JCS vectors,
  the canonical output format and the planned test scripts.
- `docs/implementation-survey.md` — the eight Beef JSON libraries (built and tested), what Beef offers
  (number parsing/formatting, SIMD), and ~35 implementations in eight languages.
- `bench/compare/results.md` — the four-track benchmark of the existing implementations (§2.3, §8).
- `AGENTS.md` — conventions, verification and commit rules.
- XmlBeef's `docs/plan.md` and `docs/architecture.md`, KdlBeef's and TomlBeef's architecture docs —
  the designs this plan adapts.

## 1. State of the repository (2026-10-01)

| Path | What it is |
|---|---|
| `BeefSpace.toml`, `BeefProj.toml` | Workspace: the `JsonBeef` library (`src/JsonBeef/`) and the `JsonTester` CLI; `TestRelease` and Windows (LLVM toolset) configs |
| `src/JsonBeef/JsonValueKind.bf` | Placeholder public type |
| `src/JsonBeef/tests/JsonSmokeTests.bf` | One smoke test (1/1) |
| `JsonTester/src/Program.bf` | Stub; becomes the suite and benchmark CLI (phase 1) |
| `tests/fetch-suites.sh` | Pinned suites into `tests/suites/` (112 MB, git-ignored; `test-suites.md`) |
| `bench/compare/` | The four-track benchmark (§2.3, §8) |
| `docs/` | This plan, the spec reference, the test-suite reference, the survey, `status.md` |

## 2. What the research says

### 2.1 Existing Beef libraries

None is reusable (`implementation-survey.md`, "The existing Beef libraries", 38 tricky inputs):
**BJSON** (M0n7y5) is the only correct one but slow by design (a virtual `Stream.Peek` per byte, a
`Dictionary` per object, typed mapping that builds the tree first; turns `1e400` into Infinity);
**StructuredData** (the Beef IDE's reader) accepts invalid UTF-8, stores fractions as `float`, wraps
2^64 to 0, segfaults on deep nesting and only treats input as JSON when it starts with `{` or `[{`;
EinScott/json, Zorbn/Json and Atma.Json are imprecise or crash on `\u` escapes; two more do not build.
BJSON stays as the conformance cross-check and the Beef baseline in the benchmark.

### 2.2 What Beef itself offers

- **Numbers:** since 2026-08-25 corlib parses doubles with fast_float (correctly rounded) and formats
  them with zmij (shortest digits). Both are lenient or differently laid out for JSON (`Double.Parse`
  accepts `1.`, `.5`, `+1`, `Infinity`, `nan`; `ToString` writes `1e+16`, `1e-05`, `1`), so JsonBeef
  validates the JSON number grammar itself and re-lays out the digits. No algorithm port is needed;
  TomlBeef's Clinger fast paths (`TryParsePlainInteger`, `TryParsePlainFloat`) sit in front.
- **SIMD:** user-declared vector types compile to real vector code (SSE2 by default, AVX2 with
  `BfSIMDSetting`), but there is no movemask, `pshufb`, `pclmulqdq`, `tzcnt` or `popcnt`, platform
  intrinsics crash the compiler, and indexing a bool vector fails in codegen. **simdjson's stage-1
  structural index cannot be built in Beef as designed.** Use the siblings' 8-byte SWAR scanning, and
  measure an optional 16-byte compare scan in phase 3.

### 2.3 The benchmark

Four tracks, never mixed (the author's direction): **DOM** (48 columns), **typed** (21), **streaming**
(19) and **on-demand** (13) over 12 languages (C, C++, Rust, Go, Java, C#, Python, JavaScript on
Node/Bun/Deno, Perl, Lua/LuaJIT, Zig, Beef). Inputs: nine real files (twitter, twitterescaped,
citm_catalog, canada, github_events, gsoc-2018, mesh, numbers, marine_ik) and seven generated ones
(tiny and REST-sized documents in batches, NDJSON events, records, strings, integers near 2^53/2^63/2^64,
hard floats); ~39 MB. Every cell is checked (counts of each value kind, decoded string length, and a
bit-exact sum of every number as a double), and peak RSS is recorded per cell. The toolchains not
installed here (Ruby, PHP, Swift, Dart, Nim, Crystal, Julia, R, Haskell, OCaml, Elixir/Erlang, D,
Kotlin, Scala) are left out; Boost.JSON (no Boost headers, ~1 GB) and DAW JSON Link are skipped.

**No timed run exists yet**: the machine stayed loaded (load average 8–17), so only a one-sample smoke
run was taken (`bench/compare/results-smoke.md`, labeled unreliable). Rough picture on twitter.json
(MB/s): DOM simdjson ~3,000, sonic-rs and yyjson ~1,000, RapidJSON in-situ ~750, jiter ~700, BJSON 45;
typed glaze ~900, go-json and fastjson2 ~750–800, sonic-rs ~600; streaming simdjson On-Demand ~1,700,
jiter ~950; on-demand simdjson ~4,500.

**Correctness (independent of load):** on valid inputs, floats are not correctly rounded by default in
RapidJSON (needs `kParseFullPrecisionFlag`), serde_json (needs `float_roundtrip`), DSL-JSON's typed
path, JSON::XS, EinScott/json and StructuredData (32-bit floats); Jansson and ijson reject integers
above INT64_MAX and lua-cjson saturates them; JSON::PP drops characters after some `\u` escapes;
json-c's heap grows ~3× the input per parse; Newtonsoft rewrites date-like strings unless told not to.

**Working targets for JsonBeef** (numeric ones from the timed run): a document at least in yyjson's
and sonic-rs's class without SIMD stage 1 (they are the fastest correct DOMs; simdjson's DOM is the
ceiling), the typed track in glaze's and go-json's class, the streaming reader in jiter's class, and
correct on every input with no flags.

### 2.4 The test suites

nst/JSONTestSuite: 95 `y_` (accept), 188 `n_` (reject), 35 `i_` (implementation-defined: JsonBeef
accepts 12 — the number cases, 500-deep nesting, a leading BOM — and rejects 23: lone surrogates,
invalid UTF-8, UTF-16 input), 22 transform cases. JSON_checker 5 accept / 31 reject (two of its
"fail" files are valid under RFC 8259); simdjson's jsonchecker 33 / 75 and 1,457 adversarial files
(all rejected); nativejson-benchmark round trips (27); json5-tests (114); the RFC 8785 vectors and
100,000 ECMAScript number lines; parse-number-fxx (1.4M lines; 3.9M more with `FXX_FULL=1`). The
exact `n_` cases each extension mode turns into accepts are computed (`test-suites.md` §1.5).

## 3. Requirements

"Must" is the phase 1–5 scope.

| Feature | Priority | Notes |
|---|---|---|
| RFC 8259 exactly, checked by default (UTF-8 validation, grammar, escapes, lone surrogates rejected) | Must | Every suite at the strengths of §2.4; never skip checks for speed |
| Numbers: exact int64/uint64, correctly rounded double, `-0` kept, big integers and out-of-range values kept as their lexeme (`GetDouble` fails with `NumberOutOfRange`, never silent Infinity) | Must | `spec-reference.md` §9; `float` fields parsed directly (via double is off by one ulp on `7.038531e-26`) |
| Pull reader (`JsonReader`) | Must | `Utf8JsonReader`/`jsontext` style: token views valid until the next call, numbers as lexemes with a kind, an "escaped" flag on strings |
| Document (`JsonDocument`, node IDs, handles) | Must | Siblings' linked node IDs built in preorder; mutable; members in order with duplicates kept |
| Writer: compact, pretty, shortest round-trip floats; JCS (RFC 8785) mode | Must | §4.8 |
| On-demand access | Must | Validating `SkipValue`, `ReadRaw`, JSON Pointer `Find` on the reader and the document, typed binding straight from the reader (§4.6) |
| Located errors, Positions sidecar, collect-errors | Must | Columns count code points (as decided for XmlBeef); collect-errors required before integration |
| Resource limits with safe defaults | Must | Depth, input/string/number length, members, nodes |
| Streams: `Read(Stream)` through a bounded window | Must | Siblings' buffered cursor |
| JSONC: `Comments`, `TrailingCommas` (separately), `Jsonc` preset | Must | VS Code/tsconfig behavior (`spec-reference.md` §12.1) |
| PreserveStyle for JSONC config files: unchanged documents byte for byte, edits regenerate only what changed | Must | hujson's model (trivia before/after each value, raw literals, trailing-comma state) on KdlBeef's slices; comments owned by members |
| Compile-time typed mapping (`[JsonObject]`) | Must | KdlBeef/XmlBeef generator; binds from the reader (no tree) and from nodes |
| JSON Lines / concatenated / RFC 7464 sequence reader | Should | `JsonSequenceReader` |
| JSON5 (full 1.0.0) | Should | Same reader, more token kinds |
| `AllowNonFiniteNumbers`, I-JSON check, invalid-UTF-8/surrogate replacement modes | Should | Opt-in |
| Push streaming (`Feed`/`Finish`) | Later | Network input |
| JSON Patch / Merge Patch | Later | |

## 4. Design

### 4.1 Layers

```
bytes ─► BOM skip ─► UTF-8 validation (SWAR) ─► cursor (contiguous, or a bounded stream window)
      ─► JsonReaderCore<TCursor>: tokenizer + structure state machine (depth stack as bits)
      ─► JsonReader (public pull tokens)
             ├─► document builder ─► JsonDocument (+ Positions / PreserveStyle sidecar)
             ├─► [JsonObject] generated readers (straight from tokens: the typed track)
             ├─► on-demand: SkipValue, ReadRaw, Find(pointer) (the selective track)
             └─► user code (the streaming track)
JsonDocument ─► writer (compact, pretty, JCS) | preserving writer
```

### 4.2 Cursor and scanning

Port XmlBeef's/KdlBeef's cursor (in-memory and buffered stream under one interface, the reader core
generic over it, absolute offsets, marks, `MaxTokenBytes`, 8 bytes of slack past the window). Scans:
whitespace skip with a first-byte dispatch table; string bodies stop at `"`, `\`, controls and bytes
≥ 0x80 (8-byte SWAR, `ScanRun`); UTF-8 validated once up front for memory input and per refill for
streams (the siblings' validator). Measure a `u8x16` compare scan for strings in phase 3.

### 4.3 Document model

- The siblings' design: a store (recycled `BumpAllocator`, arena strings as views,
  `ReleaseCachedMemory`) and node IDs into one record table with parent/first/last/next/previous links
  and a child count, built in preorder from reader tokens. `JsonNode` is a handle struct whose
  properties read and write through (`node["name"]`, `node[3]`, `node.Kind`, `TryGetInt64`, …).
- Records are ~40 bytes; measure a 32-byte variant in phase 3. System.Text.Json's flat `MetadataDb`
  (12-byte rows) and yyjson's 16-byte values are the read-only alternatives: add a flat read-only
  document only if the benchmark shows the gap is worth a second model.
- Object members: name and value in order, duplicates kept, lookup last-wins by a linear scan; a hash
  index built lazily past ~32 members (TomlBeef's `TomlEntryMap` pattern). `DuplicateNames = Error`
  is an option.
- Strings: views into the document's copy of the input when unescaped; decoded into the arena when
  escaped.
- Numbers: the reader classifies each as int64, uint64, double or big; the document stores the value
  and keeps the lexeme only where it is needed (big, out of range, and in PreserveStyle).

### 4.4 Numbers

Validate the grammar first, then: integers through a direct int64/uint64 path; floats through
TomlBeef's Clinger fast path, then corlib's fast_float. Mantissas are bounded (~768 significant
digits, then truncated with a sticky bit, as fast_float does); exponents saturate. Writing: shortest
round-trip digits from corlib's zmij, re-laid out (§4.8).

### 4.5 Errors and limits

`JsonParseError { Kind, Message, Line, Column, Offset, Length, Source }` as the siblings'; columns in
code points. Collect-errors with recovery (resynchronize at the next `,` or closing bracket at the
right depth). `JsonReadConfig` limits: `MaxDepth` 1024 (iterative parsing: depth costs a bit, not
stack; the nst 500-deep case needs ≥ 500), `MaxInputBytes`, `MaxStringBytes`, `MaxNumberLength` (the
lexeme, against slow decimal paths), `MaxMembers`, `MaxNodes`, `MaxTokenBytes` (streams).

### 4.6 On-demand

A validating `SkipValue` (skipping still checks everything: the "fully correct" rule beats
simdjson's "validate only what you use"), `ReadRaw` (the value's source span), JSON Pointer
(RFC 6901) `Find` on the reader (forward-only) and on the document, and `[JsonObject]` binding
straight from the reader. Typed member matching: try the next declared member first, then a
generated switch, always confirmed by a byte compare (never hash-only matching, which DSL-JSON, DAW
and orjson's cache get wrong).

### 4.7 Typed mapping (`[JsonObject]`)

KdlBeef's/XmlBeef's generator. Names as declared by default (TomlBeef and XmlBeef; serde and Go do
the same) with `CamelCase`, `SnakeCase`, `KebabCase` policies and `[JsonName]`; unknown members
ignored, strict mode opt-in; duplicate members an error in typed binding; enums as strings by
default; `null` for nullable members; optional discriminator for polymorphism. Attribute names must
not collide with BJSON's (`[JsonObject]`, `[JsonIgnore]`) in files importing both: TomlTester imports
BJSON (§9).

### 4.8 Writer

Compact and pretty; minimal escaping (`"`, `\`, controls; optionally non-ASCII and `</`); floats as
shortest round-trip digits; JCS mode (RFC 8785: ECMAScript number layout, UTF-16 key order). The
plain layout is an open question (§9). PreserveStyle keeps number lexemes, string escape spellings,
whitespace, comments and trailing commas.

## 5. Porting table

| Source | Use in JsonBeef | Changes |
|---|---|---|
| XmlBeef/KdlBeef cursor and char files | `JsonCursor.bf`, `JsonChar.bf` | JSON stop classes |
| XmlBeef/KdlBeef reader structure | `JsonReaderCore`, `JsonReader` | JSON tokens, depth bits, extension modes |
| TomlBeef `TomlParser.Values.bf` number fast paths | `JsonNumber.bf` | JSON grammar, uint64, big lexemes |
| KdlBeef/XmlBeef store, document, node handles, mutation | `JsonDocument`, `JsonNode*` | Values, members |
| TomlBeef `TomlEntryMap.bf` | member index | Duplicates kept, last-wins |
| KdlBeef/XmlBeef style sidecar | `JsonDocument.Style.bf` | JSONC trivia slots |
| KdlBeef/XmlBeef serializer generator | `[JsonObject]` | JSON roles, reader binding |
| Siblings' test scripts | `test-leaks.sh`, `test-json-suite.sh`, `test-json-numbers.sh`, `test-roundtrip.sh` | `test-suites.md` §9 |

## 6. Phases

Each ends with Debug and Release tests, the leak check, the suite scripts on both binaries and the
Windows tests, committed (`AGENTS.md`).

1. **Reader and suite runner.** *Done (2026-10-02): nst 95 `y_` accepted, 188 `n_` rejected, the 35
   `i_` as in `test-suites.md` §1.2 (12/23); transform 16/6; JSON_checker 5/31; simdjson jsonchecker
   33/75 and 1,457/1,457 adversarial rejected; nativejson 27; json5-tests strict 25/89; every accepted
   case equal to the oracle's canonical form and every rejected one to its golden message, from memory
   and through 1- and 16-byte stream reads, in Debug and Release; fxx 1,414,116 numbers bit-exact in
   f64 and f32 and es6 100,000 lines both ways. The full number corpora run in Debug too (4 s), so
   there is no subsampling; `-stream 1` feeds 1-byte reads through the 16-byte minimum buffer.*
   Cursor, validation, tokenizer, number classification, `JsonReader`,
   `JsonTester` printing the canonical form (`test-suites.md` §9.2), `test-json-suite.sh` and
   `test-json-numbers.sh`. Done when every suite passes at its §2.4 strength and the number corpora
   round-trip exactly.
2. **Document and writer.** *Done (2026-10-02): `JsonDocument` with 40-byte records and `JsonNode`
   handles, text as views of the document's copy of the source (decoded strings in an arena), lookups
   with a seeded member index past 16 members, the four duplicate-name policies, JSON Pointer;
   `JsonWriter` and `JsonDocument.Write` (compact, indented, RFC 8785). The suites pass in document,
   stream and rewrite (compact and indented) modes; the compact writer reproduces the 27 nativejson
   files and the RFC 8785 vectors 6/6; the corpora agree with the oracle in every mode
   (`test-json-corpus.sh`). Mutation stays in phase 5.*
   Store, nodes, members, the builder, compact/pretty/JCS writers, lookups,
   JSON Pointer.
3. **Speed.** *Code done, timed run pending (2026-10-02): `JsonBeef` and `JsonBeef JsonReader` join
   the DOM and streaming tracks with check lines equal to the reference on all 16 inputs (typed and
   on-demand follow `[JsonObject]` in phase 6); UTF-8 is checked in the string scan instead of a pass
   before reading; a fast document build for memory input that falls back to the reader to report
   errors; SWAR whitespace and digits; floats' mantissas gathered in the one scan; the `u8x16` string
   scan (SSE2 compares, kept: fewer instructions on long strings, neutral on short ones). Document
   reads went from 17.8 to 9.4 instructions per byte on citm_catalog, 19.1 to 11.9 on twitter
   (`docs/status.md`). The machine stayed loaded (load average 7–27), so the timed run, and with it
   the 32-byte record's measurement and the comparison with the §2.3 targets, waits for a quiet one.*
   Join the four benchmark tracks (`JsonBeef` columns), profile, fast paths; measure the
   `u8x16` scan and the 32-byte record. Targets from §2.3.
4. **Errors, positions, limits, streams, collect-errors.** *Done (2026-10-02): errors located in
   document order and identical from memory and streams (UTF-8 is checked in the string scan since
   phase 3); `JsonDiagnostic`; `MaxNodes` and `MaxMembers` for documents and an `Untrusted` preset;
   `JsonMetadataMode.Positions` with value and name ranges (line and column from a lazy line index for
   memory input, located while reading for streams); collect-errors with reader recovery (balanced
   tokens, synthetic End tokens, the end closing every container) and `JsonDocument.Errors`. The suite
   passes in collect and stream-collect modes with the golden first errors; streams fed 1 to 31 bytes
   per read read every suite input as memory does; 343,000 fuzzed mutations agree across the fast
   build, the reader, 1-byte streams and collect-errors.*
5. **JSONC and PreserveStyle, mutation.** Byte-exact round trips of every accepted suite input and of
   JSONC samples; edits keep neighbors.
6. **`[JsonObject]` and on-demand.** Typed binding from the reader and nodes; the typed and on-demand
   benchmark tracks.
7. **Extras.** Sequence reader (JSON Lines), JSON5, non-finite numbers, I-JSON check, replacement
   modes; then push streaming, Patch.

## 7. Testing

Every suite of §2.4 with checked-in expected-deviation lists (a listed failure that starts passing
fails the run); the number corpora; `[Test]`s from `spec-reference.md` §16 (each line is a test);
security tests (deep nesting, huge numbers and strings, duplicate-key floods); LeakSanitizer; Windows;
the benchmark inputs as large-input checks (checksums must match the reference).

## 8. Rerunning the benchmark

```bash
tests/fetch-suites.sh
cd bench/compare
./fetch.sh && ./build.sh && ./gen-inputs.py
./run.sh                                 # refuses to run above load average 2 (FORCE=1 overrides)
ONLY='JsonBeef.*' ./run.sh               # later: remeasure only JsonBeef, merged into results.md
```

## 9. Decisions and open questions

Decided in this plan from the research (override any):

1. RFC 8259 strict by default; extensions opt-in (JSONC first, JSON5 later).
2. `MaxDepth` 1024; BOM skipped by default.
3. Out-of-range numbers and big integers are accepted and kept as lexemes; converting them to double
   fails (`NumberOutOfRange`); typed binding errors.
4. Duplicate names: kept, lookup last-wins; `Error` option; typed binding errors by default.
5. Lone surrogates and invalid UTF-8 rejected; replacement (U+FFFD) and WTF-8 modes opt-in.
6. Corlib's fast_float and zmij behind TomlBeef's fast paths; no ported algorithms.
7. On-demand validates what it skips.
8. Collect-errors required (as for XmlBeef); error columns in code points.
9. Typed-mapping names as declared (as XmlBeef), with naming policies.

Open:

1. **Plain writer float layout:** ECMAScript/JCS (`100`, `1e+21`) everywhere, or keep floats visibly
   floats (`100.0`, serde/ryu style; nativejson's compact round trip passes 27/27 instead of 24/27)
   with JCS as a separate mode (proposed)? And `-0` or `-0.0` for negative zero?
2. **TomlTester's BJSON dependency:** move it to JsonBeef once phase 2 is done (proposed), and avoid
   attribute-name clashes until then?
3. **A flat read-only document** in addition to the mutable one, if phase 3 shows a large gap to
   yyjson/System.Text.Json?
