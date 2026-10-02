# JsonBeef Architecture

How JsonBeef works today and why. It is not a task list: open work is in [status.md](status.md), the
phases still to come in [plan.md](plan.md), the JSON rules in [spec-reference.md](spec-reference.md),
the suites in [test-suites.md](test-suites.md). Code conventions and Beef gotchas are in `AGENTS.md`.

## 1. Overview

- A JSON (RFC 8259) library for Beef. Today it has a **pull reader** (`JsonReader`) over UTF-8 bytes in
  memory or a `Stream`, with on-demand `SkipValue`, `ReadRaw` and `Find`, and a fed **push reader**
  (`JsonPushReader`); number conversion and
  formatting (`JsonNumber`); a **document** built on the reader (`JsonDocument` with `JsonNode`
  handles, lookups, JSON Pointer, mutation, positions, PreserveStyle, JSON Patch and Merge Patch);
  **writers**: the streaming `JsonWriter` (compact or indented) and the document's `Write`, also in
  RFC 8785 canonical form; JSONC and JSON5; **sequences** (JSON Lines, concatenated, RFC 7464); and
  **typed mapping** (`[JsonObject]`, `JsonSerializer`) bound straight from the reader.
- **Strict and complete.** Every token is validated when it is read: UTF-8, the grammar, escapes,
  surrogate pairs, the number grammar. Nothing is skipped for speed. The first error stops the read
  with a located `JsonParseError` (kind, message, line, column in code points, byte offset, length,
  source name).
- **Lossless numbers.** Integers are exact (int64, uint64), doubles correctly rounded, and nothing
  becomes infinity silently: `1e400` and big integers are read as tokens whose text is kept, and only a
  conversion to double reports `NumberOutOfRange`.
- **Few allocations.** Token strings are views of the input; only strings with escapes are decoded,
  into one reusable buffer.

## 2. Source layout

| File (`src/JsonBeef/`) | Responsibility |
|---|---|
| `JsonDocument.bf` | `JsonNodeRecord`, `JsonNodeFlags`; `JsonDocument`: the node table, the text (source copy, string table), `Read`/`ReadFile` and the builder over the reader's core, links, member lookup and the duplicate-name policies |
| `JsonDocument.Write.bf` | `Write`/`WriteFile`: the iterative tree walk over `JsonWriter`, the canonical (RFC 8785) walk with UTF-16 member order |
| `JsonNode.bf` | `JsonNodeId`, the `JsonNode` handle (kind, navigation, lookups by name and index, values), `JsonNodeList`, `JsonMember`, `JsonMemberList` |
| `JsonMemberIndex.bf` | The seeded hash index of large objects |
| `JsonPointer.bf` | `JsonPointer` (RFC 6901 evaluation, syntax, escaping), `JsonPointerError` |
| `JsonPatch.bf` | `JsonPatch` (RFC 6902 `Apply`, RFC 7396 `Merge`), `JsonPatchError`; the document's `Checkpoint`, `CopyDetached` and `Adopt`; `JsonNode.SetValue` and `ValueEquals` |
| `JsonWriter.bf` | `JsonWriteOptions`, `JsonNonFiniteNumbers`, `JsonWriteError`; `JsonWriter`: the streaming writer, escaping, number output |
| `JsonValueKind.bf` | `JsonValueKind` |
| `JsonTextArena.bf`, `JsonStack.bf` | Internal: XmlBeef's chunked byte arena (kept across reads) and growable array with inlined `Add` |
| `JsonDecodeBuffer.bf` | Internal: the bytes strings with escapes decode to, written through a raw pointer |
| `JsonReader.bf` | `JsonToken`; `JsonReader` (public: tokens, depth, offsets, strings, number conversions, `SkipValue`, `ReadRaw`, `Find`), dispatching to one core per cursor type |
| `JsonReaderCore.bf` | `JsonFailure`; `JsonReaderCore<TCursor>`: the state machine, the container bit stack, literals, numbers, strings and escapes, whitespace, the window helpers, `Fail`; on demand: `SkipValue` and its fast loop, `ReadRaw`, `PeekMember` |
| `JsonReaderCore.Json5.bf`, `JsonIdentifierTables.bf` | JSON5's whitespace, strings, member names and numbers; the generated identifier ranges |
| `JsonSequenceReader.bf` | `JsonSequenceMode`; `JsonSequenceReader`: JSON Lines, concatenated and RFC 7464 sequences |
| `JsonPushReader.bf` | `JsonPushState`, `JsonPushCursor` (fed input); `JsonPushReader`: `Feed`, `Finish`, `Next` |
| `JsonCursor.bf` | `IJsonCursor`, `JsonLineCounter`, `JsonInputStart` (UTF-16/32 detection, the BOM), `JsonByteCursor` (in memory) |
| `JsonStreamCursor.bf` | `JsonBufferedStreamCursor` (a `Stream` through a bounded buffer) and its `JsonStreamState` |
| `JsonNumber.bf` | `JsonNumberKind`, `JsonFloatFormat`; `JsonNumber`: double/float parsing (Clinger, then corlib's fast_float), int64/uint64 parsing, grammar check and classification, shortest round-trip output of doubles and floats in the plain and ECMAScript layouts |
| `JsonChar.bf` | Byte classes, SWAR word tests, UTF-8 validation (`FindInvalid`), decode/encode, line and column, character descriptions for messages |
| `JsonError.bf`, `JsonReadConfig.bf` | `JsonErrorKind`, `JsonParseError` (KdlBeef's model, with a JSON Pointer path for binding errors); `JsonReadConfig` (dialect, metadata, collect-errors, limits, stream buffer), `JsonMetadataMode`, `JsonDuplicateNames` |
| `JsonDiagnostic.bf` | `JsonDiagnostic`: an error that owns its text |
| `JsonDocument.Positions.bf` | `JsonSourceRange`, `JsonRangeRecord`; the line index, `TryGetSourceRange`/`TryGetNameRange` |
| `JsonDocument.Fast.bf` | The fast build for memory input (phase 3) |
| `JsonDocument.Mutation.bf` | `IsValidText`, `CreateRoot`, the table operations behind editing; the mutation API on `JsonNode` (setters, Add, Insert, Remove, Rename) |
| `JsonDocument.Style.bf` | PreserveStyle: `JsonNodeStyle`, capture, layout detection, change marks, the preserving writer |
| `JsonObjectAttribute.bf` | `[JsonObject]`, `JsonNaming`, `[JsonName]`, `[JsonAlias]`, `[JsonIgnore]`, `[JsonRequired]`; `IJsonSerializable`, `IJsonConverter<T>`, `[JsonConverter]`, `[JsonUseConverter]` (all in the JsonBeef namespace: BJSON has `[JsonObject]` and `[JsonIgnore]` too) |
| `JsonSerializerPlan.bf`, `JsonSerializerCodeGen.bf` | The compile-time generator: field plans (`ValueSpec`) and checks; the emitted method shells and their bodies (`Body`), polymorphic dispatch (`TypeDispatch`) |
| `JsonBind.bf` | `JsonStep`, `JsonDuplicateAction`; `JsonBind`: what the generated code calls per value (reading with errors kept in the reader, located errors and paths, discriminators, writing helpers) |
| `JsonBind.Node.bf` | `JsonArrayCursor`, `JsonMemberWriter`; a node's text with its span map and error relocation; the in-place node setters |
| `JsonSerializer.bf` | `JsonSerializer`: whole texts, streams, files and document nodes to and from `[JsonObject]` types |

Tests are in `src/JsonBeef/tests/`: `JsonEdgeCaseTests` (spec-reference §16, one test per edge case,
numbered as there; each input is read from memory and through 1-byte stream reads, which must agree),
`JsonReaderTests` (API, limits, streams, number layouts), `JsonDocumentTests` (the document, the
writers), `JsonCollectTests`, `JsonPreserveTests`, `JsonObjectTests`, `JsonOnDemandTests`,
`JsonPushTests` and `JsonPatchTests`, with `JsonTestUtil` (the trace helpers and a trickling test stream). The CLI is
`JsonTester/src/` (`Program.bf`, `Canonical.bf`, `Numbers.bf`, `TrickleStream.bf`, `Push.bf`,
`Bench.bf`, `Fuzz.bf`, `Mutate.bf`);
the scripts are `test-json-suite.sh`, `test-json-corpus.sh`, `test-json-numbers.sh`,
`test-json-fuzz.sh`, `test-roundtrip.sh`, `test-json-lines.sh` and `test-leaks.sh`, and
`tests/tools/json-canonical.py` (with `json5-canonical.py` for JSON5) is the independent oracle of the
canonical form.

## 3. Reading

### Input and validation

`JsonInputStart.Check` runs first, on the first four bytes: a UTF-16 or UTF-32 byte order mark, or the
zero bytes of ASCII characters in 16- or 32-bit units (RFC 4627 §3's patterns, checked on four bytes
so that `[`, NUL, `]` stays a syntax error), is `UnsupportedEncoding` (RFC 8259 §8.1: transcode first);
one UTF-8 BOM is skipped unless `AllowBom` is off (`plan.md` §9 item 2). UTF-8 well-formedness
(Unicode §3.9 table 3-7: overlongs, encoded surrogates and code points above U+10FFFF are errors) is
checked where non-ASCII bytes can be: inside strings, by the string scan (see Fast paths). Anywhere
else a non-ASCII byte is a syntax error, reported as `InvalidUtf8` when it is ill-formed. Every code
point is legal inside a string, so no other character check exists.

### The window and the cursor

KdlBeef's and XmlBeef's design. `JsonReaderCore<TCursor>` reads `mData[offset]` for
`mBase <= offset < mEnd` through `Avail`/`AvailN`/`Grow`, which call `IJsonCursor.Fill` at the window's
end. `JsonByteCursor`'s `Fill` is an inlined `false`, so for memory input the helpers fold to compares;
`JsonReader` holds one core per cursor type and dispatches on a flag.

`JsonBufferedStreamCursor` reads a `Stream` through a buffer of `StreamBufferBytes` (default 64 KiB,
at least 16). `Fill` drops the bytes before the current token (`mRetain`, kept until the next call so
the token's views stay valid), reads more, and doubles the buffer only when one token does not fit,
up to `MaxTokenBytes`. The reader asks for a UTF-8 sequence's bytes before it checks one, so errors
are the same from memory and from a stream (the suite's stream modes compare every error with the
golden one). When the window moves the core rebases the token's views (`RebaseViews`). Lines are counted forward
(`JsonLineCounter`, XmlBeef's: newlines found 8 bytes at a time, columns counted only when asked from a
base on the current line); LF, CR and CRLF are one newline each.

### The state machine

`Next` resumes from a state naming what is expected: `Value` (the document's value, an element after
`,`, a member's value after `:`), `ArrayStart` (an element or `]`), `ObjectStart` (a name or `}`),
`Name` (a name after `,`), `Colon` (`:` after a name, then the value), `AfterValue` (`,` or the
container's end, or at depth 0 the end of the input). The open containers are a bit stack (1 =
object), so nesting costs a bit per level and no recursion: `MaxDepth` (default 1024, `plan.md` §9
item 2) is a limit of the configuration, not of the stack, and `MaxDepth = 0` reads 100,000 levels.
The value after the root is checked by the call that returns `EndOfDocument`; content after it is an
`InvalidStructure` error. Errors are sticky (`IsStopped`); internal methods return
`Result<T, JsonFailure>` with an empty error type and `Fail` records the real error (KdlBeef's measured
choice). Messages name what was expected and what was found (a character by its code point and name
when it is invisible: `U+000C (form feed)`), and common mistakes get their own wording (a trailing
comma, `'` strings, `+1`, `.5`, `NaN`, `True`, leading zeros, a number running into letters).

### JSONC

`JsonReadConfig.Comments` lets `//` (to the end of its line) and `/* */` (not nested) stand wherever
whitespace may; `TrailingCommas` accepts one comma before `]` or `}` (`[,]`, `[1,,]` and `{,}` stay
errors); `JsonReadConfig.Jsonc` sets both, as VS Code's settings and tsconfig.json mean "JSON with
comments". The whitespace fast path lets `/` through to the slow one, which skips comments (`SkipComment`,
out of line; UTF-8 checked inside); a malformed comment is left where it starts, and the error describer
reports it (`CommentError`: `UnterminatedComment`, an ill-formed UTF-8 sequence, or a lone `/`). In
strict JSON a `/` says that comments are not JSON. The fast build does not take comments or trailing
commas: it falls back to the reader at the first one. The suite checks that each mode accepts exactly
the nst `n_` cases and json5-tests files jsonc-parser does (`tests/nst/accept-*.txt`,
`tests/json5/accept-*.txt`).

### JSON5

`JsonDialect.Json5` (spec-reference §12.2; `JsonReaderCore.Json5.bf`) reuses the reader's state
machine, comments and trailing commas, and swaps in its own token readers where JSON5 differs:

- **Whitespace**: JSON's whitespace loop is unchanged; JSON5's other spaces (VT, FF, NBSP, U+FEFF,
  U+2028, U+2029 and the other Zs spaces: `Json5SpaceLength`) are taken where JSON would report the
  byte as unexpected (`SkipJson5Space`, in the value, name, colon and after-value paths, out of line),
  and the state reads again. `//` comments also end at U+2028 and U+2029. The dialect checks left on
  the token path (which reader a value or name goes to) cost about 1% of the event pass on twitter
  and citm_catalog (14.68 to 14.85 instructions per byte; canada and the document unchanged).
- **Strings** in either quote: a plain run is a view of the input; at a backslash (or an ill-formed
  sequence with `InvalidUtf8.Replace`) the decoder takes JSON5's escapes: `\'`, `\v`, `\0` (not
  before a digit), `\xHH`, line continuations, and any other character after `\` standing for itself
  except `1`-`9`. Raw control characters other than CR and LF are text.
- **Member names**: either quote, or an ECMAScript 5.1 identifier (`$`, `_`, letters, then digits,
  marks, connector punctuation, ZWNJ, ZWJ; `\uXXXX` escapes of those), from range tables generated
  from Unicode 16.0 (`JsonIdentifierTables.bf`, `tests/tools/gen-json5-tables.py`).
- **Numbers**: signs, `.5`, `5.`, hexadecimal integers of any length, `Infinity` and `NaN` with
  signs; no leading zeros. A token's `RawValue` is what was written and its `StringValue` the JSON
  number it is (`0x1F` → `31`, `.5` → `0.5`, `5.` → `5.0`, hex beyond 64 bits converted to decimal):
  conversions and documents use that text, so nothing downstream sees JSON5 syntax. `ValueIsEscaped`
  says when the two differ.

The fast build and SkipValue's fast loop read JSON's grammar, a subset with the same meanings, and
hand JSON5's tokens to the token loop. PreserveStyle keeps JSON5 text as written (single quotes,
unquoted names, hex), and edits are written in JSON syntax, which JSON5 reads. `test-json-suite.sh`
compares every nst case and json5-tests file read with `-json5` (document, tokens, 1-byte stream)
with `tests/tools/json5-canonical.py`, an independent JSON5 reader that agrees with json5 2.2.3 on the
suites but where JavaScript cannot (duplicate names, ill-formed UTF-8); the acceptance lists are
json5 2.2.3's (36 nst `n_` cases, 83 json5-tests files).

### Sequences

`JsonSequenceReader` (spec-reference §12.3, §12.4) reads many values from one input, in three modes:

- **Lines** (JSON Lines, NDJSON) and **RecordSeparated** (RFC 7464) split the input into records first
  (at LF, or at the record separator 0x1E), from memory or from a stream through a buffer that holds
  one record. Each record is checked whole with a reader over it (its value skipped, which checks it;
  exactly one value; for RFC 7464 a top-level number or literal must be followed by whitespace, §2.4)
  before Next hands out a reader at its first token, so a record gives a value or an error, never
  both, and the next call goes on with the next record. Errors are moved from the record to the whole
  input (`Locate` does it for the caller's own reads). Empty lines are errors unless SkipEmptyLines;
  consecutive separators are not elements; a byte order mark only at the very start (AllowBom).
- **Concatenated** values use one reader with a hidden multiple-values mode: at depth 0 after a value,
  where the reader would report "a document holds one value" (on its out-of-line error path, so
  single documents pay nothing), the next value starts; an input with none is an empty sequence.
  Values are read as they come, and the first error ends the sequence.

`ReadDocument` reads the current value into a document from its source text (ReadRaw). JsonTester's
`-lines`, `-concatenated` and `-rs` print one canonical line per value and each error as
`record N: line:column: ...`; `test-json-lines.sh` compares them with the oracle's `-lines` and
`-concatenated` on the ndjson corpora, every nst case and generated inputs, from memory and streams.

### Push input

`JsonPushReader` is the reader fed rather than pulling: `Feed` appends bytes, `Next` returns a token
or `None` when it needs more, `Finish` marks the end. It runs the same core over a third cursor,
`JsonPushCursor`, whose window is every byte fed and not yet dropped (`JsonPushState` owns the
buffer, its absolute base offset and the line count of what was dropped). Where the core would read
past the window, Begin and Fill note that they are starved instead of failing (unless the input is
finished, when the window's end is the input's end), and `NextTokenPush` takes the token back: it
snapshots everything a token can change (position, state, depth, the string start, pending closes,
the last error offset) and restores it, so the next `Next` after a `Feed` reads the token again from
its first byte. Tokens, values and errors are therefore those of a whole-input read, at any chunk
size; a number at the end of what was fed waits for more input or for `Finish`, and the encoding is
decided on the first four bytes (a BOM, UTF-16/32), so nothing is reported before them.

Re-reading a token after every feed would be quadratic for a long string fed a byte at a time, so a
token cut off inside a string waits until a `"` arrives past where the last scan stopped (`mScanFrom`)
before trying again. Bytes before the core's `KeepFrom` (the current token, or a value being skipped
or retained) are dropped after each token, counting their lines first; `RefreshWindow` rebases the
core and its views after a Feed has moved the buffer. MaxInputBytes counts every byte fed;
MaxTokenBytes bounds what one token holds back: the window given to the core ends MaxTokenBytes past
the token's start, so a longer token reaches Fill's limit check rather than waiting forever.

### Non-finite numbers, replacement, I-JSON

Opt-in departures from RFC 8259 in either direction (spec-reference §5.2, §5.3, §8, §12.5), each a
`JsonReadConfig` field and a `JsonTester` flag:

- **`AllowNonFiniteNumbers`**: `NaN`, `Infinity` and `-Infinity` are number tokens of kind `NonFinite`
  (where a value starts with `N` or `I`, and after `-`); their doubles are the values they name, and
  documents store them as doubles. The writers still follow `NonFiniteNumbers` (an error by default),
  and a PreserveStyle document writes them back as they were.
- **`InvalidUtf8 = Replace`**: the string scan treats an ill-formed sequence as a stop, like `\`, and
  the decoder writes one U+FFFD per maximal subpart (`JsonChar.MaximalSubpartLength`: the lead and the
  continuation bytes that could still have completed it), as Unicode §3.9 and Python's decoder do.
  Outside strings ill-formed bytes stay errors.
- **`InvalidSurrogates = Replace | Wtf8`**: an unpaired `\u` surrogate escape becomes U+FFFD, or its
  code point as three generalized-UTF-8 bytes (`ED A0 80`). Strings holding such bytes are not
  UTF-8; the writer turns them back into `\udxxx` escapes (not in canonical output: RFC 8785 makes them
  an error), so a WTF-8 document round-trips.
- **`IJson`** (RFC 7493): noncharacters in strings and names are `Noncharacter` errors (checked on the
  decoded text, so escaped ones count; `JsonChar.FindNoncharacter` looks only at lead bytes EF-F4),
  numbers beyond a finite double are `NumberOutOfRange`, documents reject duplicate names whatever
  `DuplicateNames` says, and the lenient options above are turned off. The reader still reports every
  member, as under every duplicate policy.

The fast build and SkipValue's fast loop take none of these paths themselves: what they do not accept
(a non-finite token, an ill-formed sequence, a lone surrogate) is handed to the token loop, and with
`IJson` neither runs. `test-json-suite.sh` checks the acceptance lists of `-nonfinite` and `-ijson`
(`tests/nst/accept-*.txt`, `reject-ijson.txt`, `tests/json5/accept-*.txt`) and compares every nst
case read with `-utf8=replace -surrogates=replace` and with `-surrogates=wtf8` with the oracle under
the same options; `JsonTester -fuzz` reads every mutation in the replacement modes from memory and
from 1-byte streams.

### Collect-errors

With `JsonReadConfig.CollectErrors` an error does not stop the read: `NextToken` returns it and calls
`Recover` (in `AfterError`), which puts the reader where the next call can go on; recovery never fails
and never makes an error itself (the pending one's message is in the per-thread buffer). It is
anchored at the error's offset (a stream's position may have moved past it inside the broken token),
and an error at or before the last one's offset resynchronizes a byte further, so recovery always
progresses. By what was expected:

- **inside a string** (`mStringStart`): past its closing quote, or to a raw line break (a string not
  closed on its line); a broken member name takes its member (`:` and value) with it;
- **a value**: a `,` or closing bracket where a value should be is read as what follows a value (a
  missing value: `[1,,2]`, a trailing comma); anything else, a broken literal or number or garbage, is
  skipped to the next whitespace, `"` or structural character;
- **a member name**: `}` closes (a trailing comma), `,` is skipped, anything else skips the member;
- **`:`**: assumed when a value follows; at `,` or `}` the name is left without a value;
- **`,` or a closing bracket**: assumed when a value (or in an object a name) follows; a closing
  bracket of the wrong kind closes the containers inside the one it matches, with empty End tokens
  first (`State.Closing`, `mPendingCloses`), or is skipped when nothing open matches;
- **the end of the input** anywhere: every open container gets its End token, then the end of the
  document (`mClosingAtEnd`); content after the document's value ends the read.

So tokens stay balanced: every Start gets its End. A member name may be followed by the next name or
the object's end when its value was broken; JsonDocument drops such a name. UTF-16/32 input, I/O
errors, resource limits and `MaxErrors` (default 100) still stop the read. `JsonDocument` keeps what it
read and the errors (`Errors`, their text copied into its arena) and returns the first; `JsonDiagnostic`
keeps an error with its own copy of the text. The suite runs in two more modes with it (`collect`,
`stream-collect`: the first error must be the golden one), and `test-json-fuzz.sh` requires the same
errors and the same recovered document from memory and from 1-byte stream reads. The normal path pays
one store per string (`mStringStart`).

### Tokens

- **Literals** compare the bytes and require that no ASCII letter, digit or `_` follows (`nulll`,
  `truefalse`); the error names the whole word.
- **Numbers** are scanned once: the grammar (leading zeros, digits after `.` and in the exponent), the
  magnitude of an integer accumulated in a uint64 (19 digits always fit; the 20th is checked), and the
  kind: `Integer` (fits int64; `-0` is one, with value 0), `UInteger` (2^63 to 2^64 − 1), `Float` (a
  fraction or an exponent), `BigInteger` (more than 64 bits), and with `AllowNonFiniteNumbers`
  `NonFinite` (`NaN`, `Infinity`, `-Infinity`). A number that runs into a letter, `.`,
  `+` or `-` is an `InvalidNumber` (`0x1F`, `1.2.3`), not a missing comma. `MaxNumberLength` bounds the
  token.
- **Strings** are scanned 8 bytes at a time for `"`, `\` and bytes below 0x20 (`JsonChar.StringStops`,
  exact per byte; the first stop is found by counting the bytes below the lowest set bit, Beef having
  no trailing-zero count). A string without escapes is a view of the input. At the first `\` the text
  so far is copied into the reader's buffer and the rest is decoded there: the eight one-character
  escapes, `\uXXXX` (hex in either case) and surrogate pairs, which must be a high `\uD800`–`\uDBFF`
  immediately followed by an escaped low one; a lone or inverted surrogate is an `InvalidSurrogate`
  error (`plan.md` §9 item 5) unless `InvalidSurrogates` says otherwise (see below). `RawValue` is the text between the quotes as written, `StringValue` the
  decoded text (it may hold NUL), `ValueIsEscaped` tells them apart. `MaxStringBytes` bounds the
  decoded length.

### Numbers: conversion and output

- **To double** (`JsonNumber.ParseDouble`, `JsonReader.TryGetDouble`/`GetDouble`): integers below 2^53
  convert directly; otherwise TomlBeef's Clinger fast path (at most 19 significant digits with a value
  of at most 2^53, a decimal exponent within ±22, or a little beyond 22 when the mantissa times the
  excess power stays exact) does one exact multiply or divide; everything else goes to corlib's
  fast_float (`double.[Friend]Parse` on the unsigned text, skipping corlib's string compares and culture
  lookup), which is correctly rounded for any length. Overflow gives ±∞ there, which `TryGetDouble`
  reports as failure and `GetDouble` as a located `NumberOutOfRange` error (`plan.md` §9 item 3).
  `ParseFloat` parses binary32 directly (through a double it rounds twice: `7.038531e-26`).
- **To text** (`JsonNumber.AppendDouble`): the shortest round-trip digits come from corlib's zmij
  (`double.[Friend]ToString_RoundTripFast`) and are re-laid out: `EcmaScript` is `Number::toString`
  (RFC 8785, the canonical form: `1e+21`, `0.000001`, `1e-7`, negative zero `0`); `Plain` (the writers'
  default, `plan.md` §9 open item 1, proposal taken) keeps a float visibly a float: the same choice of
  fixed or exponential notation, but `.0` on integral values, `-0.0` for negative zero and no `+` in
  the exponent (`1.0`, `100.0`, `1e21`), which reproduces all 27 nativejson round-trip files.
  `AppendCanonical` is ECMAScript with negative zero `-0` (the canonical form of test-suites.md §9.2).
- Verified against the whole parse-number-fxx corpus (1,414,116 numbers bit for bit in f64 and f32,
  30,700 overflows, the 169 non-JSON strings rejected by the reader) and the first 100,000 lines of the
  RFC 8785 number file (both directions), in Debug and Release.

### Fast paths

Phase 3 measured with instruction counts (`bench/instructions.sh`, which load does not distort; it
is not speed: branch misses and memory stalls are not in it) and `perf record -e instructions`. What
paid:

- **UTF-8 in the string scan.** The input is no longer validated in a separate pass before reading:
  only strings may hold non-ASCII bytes, so the string scan stops at bytes ≥ 0x80 and checks each
  sequence (`JsonChar.ValidSequenceLength`: two- and three-byte forms from one 32-bit load), and the
  error paths that describe a byte elsewhere report an ill-formed one as `InvalidUtf8`. Errors now
  come in document order, the same from memory and from a stream (one golden error changed:
  `[a` + E5 `]` reports the `a`). twitter: 17.5 → 15.3 instructions per byte.
- **Whitespace**: one compare inline when there is none (minified JSON), a byte or two out of line,
  and indentation 8 bytes at a time (`JsonChar.NonSpaceBytes`) from the second whitespace byte on.
- **Numbers**: the reader gathers a float's first 19 significant digits and decimal exponent during
  its one scan (`mFloatMantissa`, `mFloatExponent`), so Clinger's fast path needs no second pass over
  the text; digits are read 8 at a time where they fit (`AllDigits`, `ParseEightDigits`, simdjson's
  trick). Longer mantissas (canada's 17-digit coordinates) still go to corlib's fast_float, a third of
  canada's instructions: plan §9 item 6 keeps it (no ported Eisel–Lemire).
- **Strings**: 16 bytes at a time with SSE2 compares (`JsonChar.FirstStringStop16`, `JsonBytes16`:
  two `pcmpeqb` and a signed `pcmpgtb`, which also catches bytes ≥ 0x80; LLVM tests the mask with
  `movmskps`, and the first stop is found from the mask's two words), then 8-byte SWAR and bytes for
  the tail; the fast build enters them only when the next byte continues a plain run, since escapes
  and non-ASCII text come in clusters. gsoc-2018: 6.6 → 4.9 per byte.
- **The fast build** (`JsonDocument.Fast.bf`): the document from memory input is built by one loop
  with the position, depth, current container and the node table's pointer in locals (stores through
  `this` made the compiler reload them after every record), writing records directly instead of going
  token by token through the reader. It checks everything the reader does but reports nothing: at any
  problem it returns false and `Read` reads again with the reader, which reports the error exactly
  (messages and positions are the reader's by construction). It serves the default duplicate policy;
  streams and the other policies use the reader's builder, so both builders run in the suite.
  `test-json-fuzz.sh` reads random mutations of every suite input three ways (fast build, reader,
  1-byte stream) and requires the same canonical form or the same error.
- **Reader bookkeeping for streams** (`Retain`) folds away for memory input; the token depth is
  computed on request; literals compare as one 32-bit word.
- **Escaped strings** (after the timed run, from `perf record` on strings.json, where corlib's
  `String.Append` and memcpy took 43% of the document read): strings with escapes decode into a
  `JsonDecodeBuffer` through a raw pointer. Each run of plain text between escapes is copied with
  room for it and 16 bytes more made first (two 8-byte words when the run is at most 16 bytes and the
  source may be read that far, else memcpy), and each escape writes its at most 4 bytes into that
  slack; the buffer grows out of line. The reader's decoded value views the buffer; the fast build
  copies it into the string table once. `\u` escapes, two thirds of strings.json's bytes, take their
  four hex digits from a 256-entry table with one test for a bad digit (`JsonChar.Hex4`), where a digit
  at a time branched twice per digit, and the reader decodes one that names no surrogate inline. Runs
  of non-ASCII characters (CJK text) are validated in an inner loop, without going back through the
  vector and word scans for each character, in the fast build and in SkipValue's string skip as the
  reader's scan already did. strings.json: document 22.2 → 14.3 instructions per byte, 426 → about
  870 MB/s; the events pass 351 → 733 MB/s; twitterescaped 19.6 → 15.9; twitter 11.9 → 11.2; the
  twitter on-demand query +10%.

- **Whitespace in pretty-printed input** (`perf` on twitter's events pass: `SkipSpaceRun` was 18% of
  the instructions, about 54 per run of 5 bytes on average): the one space after `:` is taken inline
  (`SkipOneSpace`, in the Colon state only; half of pretty-printed JSON's runs); indentation from the
  run's third byte goes to `SkipIndentation`, out of line so that one- and two-byte runs keep
  `SkipSpaceRun`'s small entry, with the position in locals and a cheaper word test: the byte that
  ends a run is almost always above 0x20 and the bytes before it spaces (`BytesAboveSpace`, a few
  operations), the exact test (`NonSpaceBytes`) only when a byte below 0x20 comes first. Measured
  against the previous build, alternating the two under the same load: the events pass +4–10% on
  twitter, citm_catalog, github_events and mesh; the benchmark's streaming column +4–7% and query
  column +6–15% on twitter and citm_catalog; minified number-heavy files within ±2%. Taking the one
  space after `,` inline too cost canada 11% more cycles for the same instructions (its hot code
  moved), so it stays out.

Tried and dropped after the timed run: digits 4 at a time after the 8-at-a-time steps (fewer
instructions on numbers.json, more on integers and floats, none saved on canada) and whitespace 16
bytes at a time (more instructions on twitter and mesh than the 8-byte loop: most runs are one space
or a newline and under 16 spaces). Beef reaches no trailing-zero count, so `FirstByte` stays a
multiply.

Not done: Eisel–Lemire (decided against), a stream path as close to memory as XmlBeef's (the stream
column is 1.3–1.5× the event pass), a 32-byte record (its gain is memory traffic, which only a timed
run shows).

### On demand

`SkipValue`, `ReadRaw` and `Find` read only what they are asked for, but skipping is not "validate
only what you use" (simdjson): everything skipped is checked as reading would check it (plan §9
item 7).

- **SkipValue** moves from the value's first token to its last (at a member name, the member's value;
  before the first token, the document's). For memory input a container goes through `SkipFast`, one
  loop over the reader's own states (ObjectStart, Name, Colon, ArrayStart, Value, AfterValue) that
  makes no tokens and decodes no strings: strings are checked to their closing quote (escapes,
  surrogate pairs, UTF-8), numbers against the grammar and what may follow them, literals as one word,
  depth and the string and number limits. As with the fast build, anything it does not take (an error,
  a malformed comment, a trailing comma, a string over `MaxStringBytes` before decoding) is handed to
  the token loop where it is, in the equivalent state, which reports the exact error or reads on.
  Streams and collect-errors use the token loop. `JsonTester -fuzz` requires both to give the token
  reader's outcome on every mutation. citm_catalog's query: 12.6 → 10.6 instructions per byte.
- **ReadRaw** is SkipValue that returns the span from the first token's start to the last one's end.
  A stream holds its window from the value's start (`mHold`, beside the token's `mRetain`) until the
  next public `Next`, so the span stays one view and is bounded by `MaxTokenBytes`.
- **Find** (RFC 6901) walks forward from the current value: through an object member by member
  (comparing decoded names), through an array element by element, skipping what is passed. A reader
  cannot go back, so in an object with a repeated name it finds the first member (document lookups
  find the last); not found, the reader is left at the last token of the value where the lookup
  failed. `JsonTester -select` prints the value found; `test-json-corpus.sh` compares it with the
  document's `-pointer` and the oracle, from memory and from 7-byte stream reads.
- **PeekMember** (internal, for discriminators) looks ahead in an object for a member and comes back:
  the position, state and depth are saved (the open-container bits below the object do not change),
  and a stream holds its window meanwhile.

## 4. Document

### Values are IDs

The siblings' model. A value is a `JsonNodeId` into `JsonDocument.mNodes`, a table of 40-byte
`JsonNodeRecord`s: an 8-byte payload, an 8-byte member-name reference, the parent, first-child, next
and previous links (0 is none; slot 0 is unused, so the root is 1), and kind, flags and number kind.
The payload is the int64, uint64 or double bits of a number, a text reference for a string (or for a
number kept as its text: a big integer, a float beyond a double's range), and for a container its last
child and child count (so appending is O(1)). Records are built in preorder from the reader's tokens,
so a container's first child is the next record until something is edited. `JsonNode` is a 16-byte
handle (document, ID, generation): the generation changes on every `Clear` and `Read`, so a stale
handle is invalid rather than showing other content. Lookups and navigation accept the invalid
handle a failed lookup returns, so chains (`root["a"]["b"].GetInt64(0)`) end in the fallback.

### Text

A text reference is 8 bytes: an offset and a length into the document's copy of its source, or with
the record's `ValueInTable`/`NameInTable` flag an index into the string table (`mStrings`, views into
the arena). `Read(StringView)` copies the input once into the arena (`JsonTextArena`, chunks kept
across reads) and reads that copy, so a string or name without escapes is a view of it; escaped ones
are decoded by the reader and copied into the arena once. `ReadFile` reads the file straight into the
arena (one copy). `Read(Stream)` reads through the stream cursor and copies every string (the window
moves). Arena chunks never move, so every view the document hands out stays valid until it is cleared
or read again. Integers below 2^53 convert to double directly; larger ones round from their decimal
text, as the token would.

### Members

Members stay in document order, duplicates included by default (`JsonDuplicateNames.KeepAll`, plan §9
item 4); a lookup scans from the last member back, so the last duplicate wins. An object with more than
16 members gets a `JsonMemberIndex` on its first lookup: open addressing, at most half full, each slot
the member's ID and its name's 32-bit hash, the hash seeded per process (a time and address mix
through splitmix64) so colliding names cannot be prepared in advance; a name maps to its last member.
The other policies act while building: `Error` fails at the second name (located at it), `LastWins`
unlinks the earlier member, `FirstWins` reads the later value and leaves it unlinked (`Removed`);
past 16 members the index answers the duplicate checks and is kept up to date as members are appended.

### Positions and limits

With `JsonMetadataMode.Positions` the builder records a `JsonRangeRecord` per node ID (the value's
offset and length, its member name's, and for a stream the line and column, located as it reads: a
stream keeps no source), in a side table that stays empty otherwise. From memory the document keeps
its copy of the source anyway, so line and column are computed only when asked
(`JsonNode.TryGetSourceRange`, `TryGetNameRange`), from an index of line starts built on first use
(LF, CR and CRLF; a leading BOM takes no column; an offset on a CRLF's LF is on its line). Arrays and
objects span their brackets; strings and names their quotes. Positions and collect-errors read with
the reader's builder (the fast build serves the plain mode only).

`JsonDocument` adds two limits to the reader's: `MaxNodes` (values, against memory amplification such
as `[[],[],…]`) and `MaxMembers` (per object), each a located `ResourceLimitExceeded`. The `Untrusted`
preset sets every limit and rejects duplicate names.

### JSON Pointer

`JsonNode.Find` (and `At`) evaluate RFC 6901 pointers: tokens decoded `~1` before `~0`, array indexes
`0` or a nonzero digit and digits (`01`, `-1`, `1e0` are `InvalidIndex`; `-` and past-the-end are
`NotFound`), names resolved like lookups (the last duplicate). Errors carry the failing token's offset.

### Mutation

`JsonNode`'s setters (`SetNull`, `SetBool`, `SetString`, `SetNumber` for int64, uint64 and double,
`SetNumberText` for an exact spelling, `SetArray`, `SetObject`) change a value in place and return the
node for chaining; a container that becomes something else loses its children. `Add()` and
`Add(name)` append to an array or object, `Set(name)` finds the last member of a name or adds one,
`InsertBefore`/`InsertAfter` place a sibling, `Remove` takes a value and its subtree out (their handles
become invalid: the subtree is marked removed iteratively), `RemoveMember(name)` removes every member
of a name, `Rename` renames a member, and `JsonDocument.CreateRoot` replaces the whole content. Text
set in code must be well-formed UTF-8 (`JsonDocument.IsValidText`) and doubles finite; anything else
is a programming error (fatal), as in XmlBeef. New text goes to the string table; every change to an
object's members drops its lookup index. Removed records keep their slots until the document is
cleared or read again.

`SetValue(source)` copies a value and its subtree from any document: `CopyDetached` builds the copy
first as new records linked to nothing (iteratively, in preorder; text from another document goes to
the string table, text of the same document is shared by reference), so the source may lie under the
target, and `Adopt` then moves the copy's value and children into the target node, which keeps its
ID, name and place. `ValueEquals` compares two values (of any documents) with an explicit stack: kinds,
strings byte for byte, arrays in order, objects as sets of names (a repeated name counts once, with
the last value, as lookups do). Numbers of one kind compare directly (integers by payload, doubles as
doubles); mixed kinds compare exact decimal values: an integer or lexeme by its text, a double by its
exact binary value written out in base 10^9 limbs (2^64 is `18446744073709551616`, where its shortest
digits are `18446744073709552000`), each reduced to sign, significant digits and exponent.

### Patch

`JsonPatch.Apply` (RFC 6902) checks each operation object (`op`, `path`, `from`, `value`; a member
given twice is an error, unknown members are ignored) and applies it on the document's own
operations: `add` resolves the parent pointer and the last token (`-` appends, an index may equal
the count, an existing member is replaced in place), `remove` and `replace` the target, `move` and
`copy` copy `from` detached first (move then removes it: the add's indexes are those after the
removal), `test` is `ValueEquals`. All or nothing: a `JsonDocument.Checkpoint` taken first copies the
node records and style slots and counts the string table and range records (both only grow), and a
failure restores them, drops the member indexes and leaves handles from before valid (the generation
does not change). Its cost is linear in the document; the patch must be another document's.
`JsonPatch.Merge` (RFC 7396) cannot fail: a non-object patch replaces the value (`SetValue`), an
object patch walks its members depth first with an explicit stack in document order (so a later
member of the same name sees the earlier one's result), removing members for `null`, merging into
objects (made objects if they were not) and replacing anything else. With PreserveStyle the edits are
ordinary mutations: what a patch does not touch is written back as it was read.

### PreserveStyle

`JsonMetadataMode.PreserveStyle` keeps the source (a stream is read whole first) and, per node, where
its pieces are (`JsonNodeStyle`, byte offsets, `JsonDocument.Style.bf`): the leading trivia from the
separator before it, the name and the colon part, the value, the trivia before its comma, the comma,
and the comma's line tail; per container also the trivia before its closing bracket and where its first
child started. The reader's builder records the tokens (`CaptureValue`, `CaptureEnd`); `FinishStyle`
then finds the commas between them. The line tail after a value (after its comma, or for the last child
after the value itself) takes the comments on the rest of its line and the blanks before the line
break, so an end-of-line comment belongs to the member before it, while blanks before a token on the
same line belong to that token (`[1, 2]`). It also detects the layout of new values: the indentation
unit, the text between a name and its value, the line break (LF, CRLF or CR), and whether the document
is written on several lines.

`Write(output)` on such a document is the preserving writer (`WritePreserving`, iterative): an
unchanged subtree is its source text, so an unchanged document is written back byte for byte (BOM,
comments, trailing commas, number and string spellings). Changes are marked (`ValueDirty`,
`NameDirty`, `ChildrenDirty`, and `SubtreeDirty` up the ancestors): a changed container is written
piece by piece, its unchanged children still as their source. A changed scalar is regenerated in its
place, a renamed member keeps its value's spelling; commas follow the children that remain: a member
that becomes the last loses its comma (its end-of-line comment stays), one that stops being last gains
one (before its comment), and a container written with a trailing comma keeps one. A new value takes
the line break and indentation of a sibling (or, in a container on one line, the blanks a sibling
followed a comma with), a first child the layout the container's first child had; with no sibling to
follow, its own line one indentation unit in, when the document (or the empty container, `[\n]`) is on
several lines. `test-roundtrip.sh` checks every accepted suite input and corpus file byte for byte
(from memory and a stream) and random edits of each (`JsonTester -mutate`), whose output must read back
into the edited document; `JsonPreserveTests` pin the exact output of edits, including ports of
jsonc-parser's `edit.test.ts` cases whose semantics JsonBeef shares. Deliberate differences: removing an
array's only element keeps its lines (`[\n]`), a trailing comma stays when the last element is removed,
and a container on one line stays on one line when it grows.

`Write(output, options)` writes any document plainly (strict JSON: comments are not kept).

## 5. Typed mapping (`[JsonObject]`)

KdlBeef's and XmlBeef's generator, with JSON's shapes and reading straight from the reader's tokens:
no document in between, so the typed track costs one pass.

### Generation

`[JsonObject]`'s `ApplyToType` adds `IJsonSerializable` and emits three method shells whose bodies are
`Compiler.Mixin(JsonSerializerCodeGen.Body(typeof(T), n))`: the bodies are planned and written when
the methods are compiled, once every type is complete. Planning at type-initialization time made a
self-referencing type (`List<Node> children`, twitter's `Status retweeted_status`) a data cycle in its
own initialization, which crashed the compiler in the benchmark project. A class's methods are
virtual (override in `[JsonObject]` subclasses) and each covers its whole `[JsonObject]` chain, base
fields first, since a reader is read once and cannot hand an object to a base's method midway.

`JsonSerializerPlan.bf` plans each field as a `ValueSpec`, recursively: scalars (bool, integers,
float, double, String, enums), `[JsonObject]` types, `T?`, `List<T>`, `Dictionary<K, T>` (String,
integer or enum keys) to any depth, converter types. Member names come from the field through the
naming policy, `[JsonName]` and `[JsonAlias]`; two members of one name in the chain (the discriminator
included), an unsupported field type or an abstract field type without a discriminator stop the build
with the field named.

### Reading

The generated `JsonRead` is one loop over the object's members:

- **Matching** a name: the slot after the last one matched first (members usually come in the
  declared order: a `switch` on the slot and one byte compare), else a `switch` on the name's length
  and byte compares within it. Never a hash alone (plan §4.6: DSL-JSON and DAW match on hashes).
- **Each slot has a bit**: a member that comes again is `DuplicateName` (a typed field holds one value;
  aliases count as the same member), unless `DuplicateNames` is FirstWins or LastWins; `[JsonRequired]`
  members missing at the end are `MissingValue`, located at the object. A member no field maps is
  skipped with `SkipValue` (so it is checked), or is `UnknownMember` in a Strict type.
- **Values** go through `JsonBind`'s helpers. They return bool and keep their error in the reader
  (`mBindError`), so the hot path carries no large `Result`. Kinds and ranges are strict: an integer
  field takes an integer token within its type's range (not `1.0` or `1e2`), a float parses the text
  as binary32 directly (not through a double, which would round twice), a double is never an infinity.
  `null` sets a reference or `T?` field to null and is `TypeMismatch` for the others.
- **Filling**: an existing String is set, an existing object read into, an existing List or Dictionary
  emptied (what it owns deleted, nested containers too) and refilled; a new object is handed to its
  owner before it is read, so an error leaves nothing unowned. An allocator, when given, makes every
  new object and nothing is deleted.
- **Error paths**: an error leaving a nested value gets the member name or index put in front of
  `JsonParseError.mPath` (a JSON Pointer), built only on the way out, so success pays nothing for it:
  `config.json:3:12: /servers/1/port: Expected an integer, found the string "80"`.
- **Polymorphism**: a field whose class (or a base) has a `Discriminator` peeks at the object for it
  (`PeekMember`: anywhere in the object; the reader comes back to the `{`), then a `switch` over the
  visible concrete `[JsonObject]` subclasses, generated when the method is compiled
  (`TypeDispatch`), creates the type it names and reads it from the start. The subtype's own loop
  checks the discriminator's value against its `TypeName`.

`JsonSerializer.Read(JsonNode)` binds a document's value through the same code: the subtree is written
compactly with a map from offsets to node IDs (values and member names), numbers as their source text
when the document kept it and it still reads as the node's value (so a float field gets the float of
the text), and read with a reader. An error is moved to the node's source range when the document has
positions; otherwise its path says where.

### Writing

`JsonWrite(JsonWriter)` writes the members in declared order (the discriminator first), floats as
their own shortest digits (`WriteFloat`); `JsonSerializer.Write` with `Canonical` goes through a
document to sort them. `JsonWrite(JsonNode)` updates a node in place, for documents read with
PreserveStyle: a value equal to what is there is not touched (a number of the same value in any
spelling, `1.50` for 1.5, stays), array elements are updated by position (`JsonArrayCursor`: extra
ones removed, new ones appended; an element node keeps the members no field maps, whichever item is
written into it), dictionary members by key (`JsonMemberWriter` removes keys that are gone), members
no field maps stay, a member under an alias is renamed. A converter's output is compared as compact
text and parsed into the node when it differs.

## 6. Writing

`JsonWriter` appends compact or indented JSON to a String. Misuse (a value where a name is needed, a
mismatched end, a second root) and bad data (invalid UTF-8, a malformed number text, NaN with
`NonFiniteNumbers.Error`) are recorded as the first error, later calls write nothing, and `Finish`
returns it, so writing code needs no checks between calls. Escaping is minimal (`"`, `\`, controls as
`\b \t \n \f \r` or lowercase `\u00xx`, JCS's spelling), found 8 bytes at a time; options add
`EscapeNonAscii` (surrogate pairs above U+FFFF), `EscapeHtml` (`<`, `>`, `&`) and
`EscapeLineSeparators`. Strings are checked as UTF-8 as they are written. Indented output puts each
element and member on its own line (`"name": value`), keeps empty containers as `[]`/`{}`, and is
O(depth²) by nature.

`JsonDocument.Write` walks the tree iteratively and drives the writer: integers exactly (`-0` as
`-0`), doubles in the plain layout, big integers and out-of-range floats as their text. With
`JsonWriteOptions.Canonical` (RFC 8785) each object's members are sorted by their names' UTF-16 code
units (`CompareUtf16`: code point order except that a supplementary character's high surrogate sorts
below U+E000), every number is written as ECMAScript writes its double (big integers rounded, `-0` as
`0`), and duplicate names, numbers beyond a double and non-finite values are errors; output has no
whitespace and no final newline. The canonical walk keeps each open object's sorted member list on one
shared stack, so it is iterative too.

## 7. Testing

- `test-json-suite.sh` runs JSONTestSuite (parsing and transform), JSON_checker, simdjson-data's
  jsonchecker and adversarial files, nativejson's round-trip files and json5-tests (strict) through
  `JsonTester` in each mode of `MODES`: the document, the reader's tokens, a document from 1-byte stream
  reads and tokens from 16-byte reads (through a 16-byte buffer, `TrickleStream`), tokens from a
  JsonPushReader fed 1 and 7 bytes at a time (`-push N`), and the compact and
  indented rewrites (written, read back). Accepted cases must print their canonical form exactly as the
  independent oracle (`tests/tools/json-canonical.py`, Python's `json` with hooks that keep number text
  and member order) computes it; rejected ones must print their golden first error line
  (`tests/errors/<suite>/<case>.err`) in every mode. The nst `i_` stance is `tests/nst/i-accept.txt`
  (test-suites.md §1.2); the transform expectations are JsonBeef's own (`tests/nst/transform/`). Then
  the compact writer must reproduce the 27 nativejson files byte for byte, and `-jcs` the 6 RFC 8785
  vectors.
- `test-json-corpus.sh` runs the 14 real-world files the same ways, checks that the compact writer is
  a fixed point, that twitter.json and twitterescaped.json hold the same strings, that mesh.json and
  its sorted, pretty-printed copy give the same RFC 8785 output, and 27 JSON Pointer lookups against
  the oracle's: on the document (`-pointer`) and on demand (`-select`, the reader's `Find`), from memory
  and from 7-byte stream reads.
- `test-json-numbers.sh` runs `JsonTester -fxx` (each fxx string read by `JsonReader` as a whole
  document, its acceptance checked against an independent grammar matcher, then f64 and f32 bits) and
  `-es6` (ECMAScript output of each double, and the text read back). Both run every line in Debug
  too: about 4 seconds, so test-suites.md §3.1's Debug subsampling is not needed.
- `test-json-fuzz.sh` first reads every suite input through streams fed 1 to 31 bytes per read (the
  memory read's outcome every time), then mutates every input at random and requires one outcome from
  the fast build, the reader, a 1-byte stream, a push reader fed 1 byte at a time, collect-errors from
  memory and from a stream, and
  SkipValue (its fast loop from memory, the token loop from a stream); each document read is also
  copied into another (`SetValue`), which must print the same, be `ValueEquals` to it and pass a JSON
  Patch that tests and replaces it with the original. `test-roundtrip.sh` writes every
  accepted input back with PreserveStyle (byte for byte) and checks random edits (`-mutate`).
- The `[Test]`s: `JsonEdgeCaseTests` (spec-reference §16), `JsonReaderTests`, `JsonDocumentTests`,
  `JsonCollectTests`, `JsonPreserveTests` (with ported jsonc-parser edit cases), `JsonObjectTests`
  (every field shape, names, errors with paths, duplicates, polymorphism, converters, allocators,
  files, documents in place), `JsonOnDemandTests` (SkipValue, ReadRaw, Find, from memory and
  streams), `JsonPushTests` (every chunk size against the memory read, waiting for whole tokens,
  limits) and `JsonPatchTests` (RFC 6902's and RFC 7396's Appendix A, every operation's errors, the
  rollback, PreserveStyle, exact number equality, deep values; JsonTester's `-patch FILE` and
  `-merge-patch FILE` apply a patch before printing). They run in Debug and TestRelease on Linux and Windows (the Windows Debug runtime's leak
  check at exit catches what LeakSanitizer can miss), and under LeakSanitizer (`test-leaks.sh`).
- `bench/compare` checks every JsonBeef column's check line against `reference.py` (all four tracks),
  and `bench/instructions.sh` counts instructions per byte, which the load does not change.
