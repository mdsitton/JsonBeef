# JsonBeef Architecture

How JsonBeef works today and why. It is not a task list: open work is in [status.md](status.md), the
phases still to come in [plan.md](plan.md), the JSON rules in [spec-reference.md](spec-reference.md),
the suites in [test-suites.md](test-suites.md). Code conventions and Beef gotchas are in `AGENTS.md`.

## 1. Overview

- A JSON (RFC 8259) library for Beef. Today it has a **pull reader** (`JsonReader`) over UTF-8 bytes in
  memory or a `Stream`, number conversion and formatting (`JsonNumber`), a **document** built on the
  reader (`JsonDocument` with `JsonNode` handles, lookups, JSON Pointer), and **writers**: the streaming
  `JsonWriter` (compact or indented) and the document's `Write`, also in RFC 8785 canonical form.
  JSONC, typed mapping and the rest follow `plan.md` §6.
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
| `JsonWriter.bf` | `JsonWriteOptions`, `JsonNonFiniteNumbers`, `JsonWriteError`; `JsonWriter`: the streaming writer, escaping, number output |
| `JsonValueKind.bf` | `JsonValueKind` |
| `JsonTextArena.bf`, `JsonStack.bf` | Internal: XmlBeef's chunked byte arena (kept across reads) and growable array with inlined `Add` |
| `JsonReader.bf` | `JsonToken`; `JsonReader` (public: tokens, depth, offsets, strings, number conversions), dispatching to one core per cursor type |
| `JsonReaderCore.bf` | `JsonFailure`; `JsonReaderCore<TCursor>`: the state machine, the container bit stack, literals, numbers, strings and escapes, whitespace, the window helpers, `Fail` |
| `JsonCursor.bf` | `IJsonCursor`, `JsonLineCounter`, `JsonInputStart` (UTF-16/32 detection, the BOM), `JsonByteCursor` (in memory) |
| `JsonStreamCursor.bf` | `JsonBufferedStreamCursor` (a `Stream` through a bounded buffer) and its `JsonStreamState` |
| `JsonNumber.bf` | `JsonNumberKind`, `JsonFloatFormat`; `JsonNumber`: double/float parsing (Clinger, then corlib's fast_float), int64/uint64 parsing, classification, shortest round-trip output in the plain and ECMAScript layouts |
| `JsonChar.bf` | Byte classes, SWAR word tests, UTF-8 validation (`FindInvalid`), decode/encode, line and column, character descriptions for messages |
| `JsonError.bf`, `JsonReadConfig.bf` | `JsonErrorKind`, `JsonParseError` (KdlBeef's model); `JsonReadConfig` (dialect, limits, stream buffer) |

Tests are in `src/JsonBeef/tests/`: `JsonEdgeCaseTests` (spec-reference §16, one test per edge case,
numbered as there; each input is read from memory and through 1-byte stream reads, which must agree),
`JsonReaderTests` (API, limits, streams, number layouts) and `JsonDocumentTests` (the document, the
writers), with `JsonTestUtil` (the trace helpers and a trickling test stream). The CLI is
`JsonTester/src/` (`Program.bf`, `Canonical.bf`, `Numbers.bf`, `TrickleStream.bf`); the scripts are
`test-json-suite.sh`, `test-json-corpus.sh`, `test-json-numbers.sh` and `test-leaks.sh`, and
`tests/tools/json-canonical.py` is the independent oracle of the canonical form.

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

### Tokens

- **Literals** compare the bytes and require that no ASCII letter, digit or `_` follows (`nulll`,
  `truefalse`); the error names the whole word.
- **Numbers** are scanned once: the grammar (leading zeros, digits after `.` and in the exponent), the
  magnitude of an integer accumulated in a uint64 (19 digits always fit; the 20th is checked), and the
  kind: `Integer` (fits int64; `-0` is one, with value 0), `UInteger` (2^63 to 2^64 − 1), `Float` (a
  fraction or an exponent), `BigInteger` (more than 64 bits). A number that runs into a letter, `.`,
  `+` or `-` is an `InvalidNumber` (`0x1F`, `1.2.3`), not a missing comma. `MaxNumberLength` bounds the
  token.
- **Strings** are scanned 8 bytes at a time for `"`, `\` and bytes below 0x20 (`JsonChar.StringStops`,
  exact per byte; the first stop is found by counting the bytes below the lowest set bit, Beef having
  no trailing-zero count). A string without escapes is a view of the input. At the first `\` the text
  so far is copied into the reader's buffer and the rest is decoded there: the eight one-character
  escapes, `\uXXXX` (hex in either case) and surrogate pairs, which must be a high `\uD800`–`\uDBFF`
  immediately followed by an escaped low one; a lone or inverted surrogate is an `InvalidSurrogate`
  error (`plan.md` §9 item 5). `RawValue` is the text between the quotes as written, `StringValue` the
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

Not done: Eisel–Lemire (decided against), a stream path as close to memory as XmlBeef's (the stream
column is 1.3–1.5× the event pass), a 32-byte record (its gain is memory traffic, which only a timed
run shows).

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

### JSON Pointer

`JsonNode.Find` (and `At`) evaluate RFC 6901 pointers: tokens decoded `~1` before `~0`, array indexes
`0` or a nonzero digit and digits (`01`, `-1`, `1e0` are `InvalidIndex`; `-` and past-the-end are
`NotFound`), names resolved like lookups (the last duplicate). Errors carry the failing token's offset.

## 5. Writing

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

## 6. Testing

- `test-json-suite.sh` runs JSONTestSuite (parsing and transform), JSON_checker, simdjson-data's
  jsonchecker and adversarial files, nativejson's round-trip files and json5-tests (strict) through
  `JsonTester` in each mode of `MODES`: the document, the reader's tokens, a document from 1-byte stream
  reads and tokens from 16-byte reads (through a 16-byte buffer, `TrickleStream`), and the compact and
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
  the oracle's.
- `test-json-numbers.sh` runs `JsonTester -fxx` (each fxx string read by `JsonReader` as a whole
  document, its acceptance checked against an independent grammar matcher, then f64 and f32 bits) and
  `-es6` (ECMAScript output of each double, and the text read back). Both run every line in Debug
  too: about 4 seconds, so test-suites.md §3.1's Debug subsampling is not needed.
