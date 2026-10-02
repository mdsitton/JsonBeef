# Survey of existing JSON implementations

This survey covers what the Beef JSON libraries and about forty JSON libraries in other languages do, how they do it, and what JsonBeef should take or avoid. The sources were read from shallow clones made on 2026-10-01 (last-commit dates are in the tables). The clones were scratch copies under `/tmp`, not pinned; the pinned copies for benchmarking live in `bench/compare/`. File references are relative to each clone.

The Beef libraries were built with BeefBuild 0.43.6 (the installed `/opt/BeefLang`, matching `~/development/Beef` at 226397fc, 2026-09-27) and run against a set of tricky inputs, in Debug and Release (the results were the same). The Rust libraries were also run against the same inputs. Everything else is from reading the code and docs. "Speed" figures are the published numbers from the cited sources unless marked as measured here. The KdlBeef, TomlBeef and XmlBeef techniques this survey refers to are described in their `docs/architecture.md`.

## At a glance

| | architecture | document | strings | numbers | duplicates | depth default | invalid UTF-8 | errors | typed mapping |
|---|---|---|---|---|---|---|---|---|---|
| **yyjson** (C) | one pass, goto state machine, 256-entry tables, 16-wide unrolled scans; no SIMD | 16 B values in one preorder array, sibling offsets; separate mutable doc (circular lists) | unescaped in a padded copy of the input | eager; Clinger, 128-bit pow10, bigcomp; Schubfach writer | kept; lookup finds first | none (non-recursive) | rejected | byte offset + `yyjson_locate_pos` | no |
| **simdjson** (C++) | stage 1 SIMD structural index + UTF-8 check, stage 2 tape | 64-bit tape words, string buffer | copied to string buffer | Clinger, Eisel-Lemire, `from_chars` fallback; BIGINT error | kept; find first | 1024 | rejected | pointer only | add-on (reflection) |
| **RapidJSON** (C++) | SAX reader, DOM as a handler, optional SSE2/4.2 | 16 B `GenericValue`, contiguous members | in situ or pool | not correctly rounded by default; Grisu2 writer | kept; first | **none** (recursive) | **accepted** (flag off) | byte offset | no |
| **Boost.JSON** (C++) | resumable SAX (`write_some`) | object table + hash past 18 | SBO 14 | imprecise by default | last wins | 32 | rejected | consumed count | `value_to`, `parse_into` |
| **serde_json** (Rust) | recursive descent into visitors | `Value`, BTreeMap (or IndexMap) | borrowed or scratch | u64/i64/f64; default float path misrounds | last wins (Value), error (derive) | 128 | rejected | line/col on error | serde derive |
| **sonic-rs** (Rust) | one pass, SIMD strings/skip | 16 B nodes in bump arena, pair arrays | SIMD unescape | Eisel-Lemire; `-0` loses sign | kept; first | **none** in DOM (stack overflow at 100k) | rejected | line/col + snippet | serde |
| **Go encoding/json v2** | `jsontext` token decoder, resumable | (none: reflection) | buffer views | lexeme, converted on bind | **error** | 10,000 | **error** | byte offset + JSON Pointer | struct tags |
| **System.Text.Json** (C#) | `Utf8JsonReader` ref struct, vectorized string scan | `JsonDocument` 12 B rows over the source | views, escape flag, lazy decode | lazy `TryGet*` | last wins (Strict: error) | 64 | rejected **on access** | line/byte + path | source generator |
| **Jackson 3** (Java) | streaming parser, quad symbol table | `ObjectNode` (LinkedHashMap) | char buffer | lazy, FastDoubleParser | last wins | 500 | rejected | line/col/offset | databind |
| **Zig std.json** | byte state machine, `BitStack`, streaming partial tokens | `Value` (ArrayHashMap) | slices or allocated | number strings | **error** | none | rejected | opt-in diagnostics | comptime reflection |
| **hujson** (Go) | AST with raw trivia on both sides of every value | AST | raw literal bytes | raw literal bytes | kept | — | via `json.Valid` | — | via `Standardize` + encoding/json |
| **BJSON** (Beef) | recursive descent over `Stream.Peek` per byte, SAX `IHandler` | struct `JsonValue` + heap `Dictionary`/`List` | SSO 14 B, else `String` | int64/uint64/double via `double.Parse` | last wins (configurable) | 200 (const) | rejected | line/col | comptime `[JsonObject]`, DOM first |

## The existing Beef libraries

GitHub searches (`json language:beef`, `serializer language:beef`, `parser language:beef`, `beef json`) find six JSON libraries, two binding packages, and JSON code embedded in two other projects. Beef's IDE has its own reader.

| | last commit (commits) | size | design | builds with 0.43.6? | verdict |
|---|---|---|---|---|---|
| **M0n7y5/BJSON** | 2026-08-27 (100) | 6,784 lines (library), 17,282 with tests and schema tools | `JsonReader` recursive descent over a `Stream` → `IHandler` (SAX) → `Deserializer` builds a `JsonValue` tree; `[JsonObject]` comptime codegen binds from that tree; JSON Pointer, JSON Schema validator, schema → Beef codegen | yes; its 104 + 27 tests pass (Debug Test config) | **the only serious one**: correct on nearly every tricky input, but slow by design; a baseline, not a base |
| **Beefy.utils.StructuredData** (Beef IDE) | 2026-09-21 | 2,790 lines (JSON, TOML and XML in one class) | one scanner loop per container, recursive; boxed values in a flat `List<Object>` with `mNextValues` index links | yes (needs `DisposeProxy.bf`) | a lenient config reader; wrong on many inputs; benchmark baseline only |
| **EinScott/json** | 2024-04-06 (6) | 690 lines | recursive descent over a shrinking `StringView`; `JsonElement` enum, `Dictionary<StringView, …>`, `BumpAllocator` tree | yes | small and tidy, but no UTF-8 validation, imprecise number parsing, crashes on a bad escape |
| **Zorbn/Json** | 2023-11-29 (1) | 356 lines | recursive descent; no `null` type; root must be an object | yes | a toy; crashes on any `\u` escape and on a duplicate key |
| **xposure/Atma.Json** | 2021-11-05 (21) | 3,136 lines | tokenizer into a token list + runtime-reflection converters | library yes; its tests do not (2 errors in `Nullable<int>` specialization) | no `\u` escapes at all; accepts `'a'`, `+1`, trailing commas and garbage |
| **RogueMacro/json** + **serialize** | 2023-08-26 (6 + 27) | 676 + 2,055 lines | serde-like `[Serializable]` (`IOnTypeInit`) framework; JSON as one format | no: `[Serializable]` no longer makes the type satisfy `ISerializable`; the README names a `Serialize<Json>` type that does not exist | not usable today |
| **Vendinois/JSON_Beef** | 2020-10-01 (85) | 4,092 lines | separate validator pass, then parse into `Variant` dictionaries | no: 5 errors (`Variant.Create<T>` constraints, `AttributeChecker.bf:12` enum payloads) | not usable |
| **beef-wrap/cjson-beef**, **jsonc-beef** | 2026-07-21, 2025-03-28 | bindings | cJSON (static musl libs for Linux) and json-c (Windows libs only) | not tested | C libraries, not Beef implementations |
| embedded: Fusioon/BeefLSP `src/Json`, Rune-Magic/BeefXml `src/Json` | 2025-12-26, 2025-10-21 | 505, 690 lines | LSP message parser; pull reader + builder | — | BeefLSP's never reports errors (`Log.Error` only), keeps escapes undecoded and has no exponents; BeefXml's fails in Release (see XmlBeef's survey) |

### Results on the tricky inputs

StructuredData and Zorbn/Json were fed `{"v": <input>}`: StructuredData picks JSON only when the text starts with `{`, or `[` followed by `{` or `"` (`StructuredData.bf:2705-2716`), so `[1e400]` is parsed as a TOML table header, and Zorbn requires an object root. Atma.Json was run through its tokenizer, since its converters need a typed target. "—" means accepted when it should have been rejected, or the value was wrong without an error.

| input | expected | BJSON | StructuredData | EinScott/json | Zorbn/Json | Atma (tokens) |
|---|---|---|---|---|---|---|
| `[1e400]` | error, or a kept lexeme | — `Infinity` | — `float` Infinity | — Infinity | — Infinity | rejected (an exponent without a fraction fails) |
| `["\uD800"]` | error (or U+FFFD by option) | error (correct) | — bytes `ED A0 80` (invalid UTF-8) | — same | **crash** (unhandled `Result`) | rejected (no `\u` support) |
| `{"a":1,"a":2}` | accepted; a stated policy | last wins (option: first, error) | both kept | last wins (option: error) | **crash** (`Dictionary.Add` assert) | both tokens |
| `[01]`, `[1.]` | errors | errors (correct) | — `1`, — `1` (float32) | — `1`, error | — `1`, — `1` | — `01`, error |
| `["\u0000"]` | one NUL | correct | correct | correct | **crash** | rejected |
| `["\xFF"]`, `["\xC0\xAF"]`, `["\xED\xA0\x80"]` | errors | errors (correct) | — all accepted | — all accepted | — all accepted | — all accepted |
| 100,000 nested `[` … `]` | error, no crash | error at depth 200 | **segfault** | error at 256 | **segfault** | **segfault** |
| `[-0]` | −0.0 | −0.0 | — int 0 | −0.0 | −0.0 | text |
| `[9223372036854775808]` | exact | uint64 (correct) | — parse error | — `9.223372036854778e18` (nearest double is …776e18) | double | text |
| `[18446744073709551616]` | double or big number | double | — **int 0** (wrapped silently) | double | double | text |
| `[1.7976931348623157e308]`, `[5e-324]` | exact | correct | — float32 Infinity, 0 | — **Infinity, 0** (own parser) | correct | text, rejected |
| `"😀"` (U+1F600) | 4 UTF-8 bytes | correct | correct | correct | **crash** | rejected |
| `[1,]`, `{"a":1,}` | errors | errors | — `[1,]` accepted, `{"a":1,}` accepted | errors | — array accepted | — both accepted |
| `[1]//c`, `/*c*/[1]` | errors (JSONC: accepted) | errors; both accepted with `EnableComments` | errors | errors | errors | — `//` passes as trailing garbage |
| `1`, `"x"`, `null` at top level | accepted | accepted | — impossible (sniffing) | accepted | — no `null` type | accepted |
| UTF-8 BOM + `[1]` | policy (most reject or skip) | rejected as invalid UTF-8 | rejected | rejected | rejected | rejected |
| raw tab in a string | error | error | — accepted | error | — accepted | error |
| `[1]x`, empty input | errors | errors | error, — `{"v":}` accepted | errors | errors | — `[1]x` accepted |
| `[+1]`, `[.5]`, `[0x10]` | errors | errors | — `1`, `0.5`, `16` | errors | — `1`, `0.5` | — `+1` |
| `["\x"]` | error | error | — `"x"` | **crash** (unhandled `Result`) | **crash** | error |
| `['a']` | error | error | error | error | error | — accepted |

A rough speed check (Release, a 16.7 MB synthetic twitter-like file, best of 7; measured here under a load average of 27, so only the ratios mean anything): StructuredData 152 MB/s (with its leniency and float32 numbers), EinScott/json 62, CPython `json` 47, BJSON 33.

### BJSON (M0n7y5)
- `JsonReader` (`BJSON/src/JsonReader.bf`) reads through `Stream.Peek<char8>()` / `Skip(1)` per byte, 26 call sites: a virtual call per byte even for `Deserialize(StringView)`, which wraps the text in a `StringStream`. It counts line and column on every byte.
- Recursive descent with `MaximumDepth = 200` as a `const` (`JsonReader.bf:24`, checked at :510, :581). The limit is not configurable.
- Numbers (`JsonReader.bf:620-998`): the token is copied into a 1024-char stack buffer (`NumberTooLong` past it); integers accumulate into a uint64 with overflow detection; otherwise `double.Parse`. That is correctly rounded today because Beef's runtime switched to fast_float (see the next section). `-0` is reported as the double −0.0, `-9223372036854775808` as int64.MinValue, larger magnitudes as doubles. `1e400` becomes Infinity, which its own writer then refuses to write (`JsonWriter.bf:168-171`).
- UTF-8 is validated as it is read; lone surrogate escapes are an error.
- The model (`Models/JsonValue.bf:12-33`) is a tagged struct with a 14-byte inline string (SSO), else a `String`; objects are `Dictionary<String, JsonValue>`, arrays `List<JsonValue>`, keys from a `BumpAllocator`. Copies share heap pointers and exactly one may be disposed. Lookup is hashed; insertion order survives only because Beef's `Dictionary` iterates in insertion order when nothing was removed.
- `DeserializerConfig`: `EnableComments` (`//`, `/* */`), `DuplicateBehavior { ThrowError, Ignore, AlwaysRewrite }` with `AlwaysRewrite` the default. No trailing commas, no BOM, no limits besides depth and number length.
- `[JsonObject]` (`Attributes/JsonObjectAttribute.bf`) is an `IComptimeTypeApply` that emits `JsonDeserialize(JsonValue)` / `JsonSerialize` (the pattern TomlBeef's `[TomlObject]` copied). The attribute set is System.Text.Json's: `[JsonPropertyName]`, `[JsonIgnore(Condition)]`, `[JsonInclude]`, `[JsonRequired]`, `[JsonOptional]`, `[JsonExtensionData]`, `[JsonConverter]`, `[JsonNumberHandling]`. Names are field names as written; unknown members are ignored; null leaves a field unchanged; enums are written as names and read from names or numbers. Typed reads always build the whole `JsonValue` tree first.
- Writer: minimal escaping, doubles through `Double.ToString` (zmij) with `.0` added to integral values, NaN and infinity rejected; `Indented` with `IndentString`.
- Extras: RFC 6901 pointers, a JSON Schema validator, and `BJSON.SchemaCodeGen` (Beef types from a schema).
- Verdict: correct, well tested and actively maintained, but per-byte virtual input, a heap container per object and DOM-first typed mapping cap it far below the siblings' speeds. Nothing to reuse as code. It is the conformance cross-check and the Beef baseline for `bench/compare`. Its attribute names (`[JsonObject]`, `[JsonIgnore]`) will collide with JsonBeef's in any file that imports both namespaces (TomlTester imports BJSON today).

### StructuredData (Beef IDE, `BeefLibs/Beefy2D/src/utils/StructuredData.bf`)
- `LoadJSONHelper` (:1710) is one character loop that remembers token start and end indices and recurses on `{` and `[`. Tokens are classified only when a `,`, `}` or `]` arrives, so anything between delimiters that is not whitespace becomes a value: numbers go through `int64.Parse(.AllowHexSpecifier)` or `(float)float.Parse` (:1898-1913), so every fraction is a **float32**.
- Values are boxed into `mValues` with `mNextValues` index links (a linked list over a flat array: the node-ID idea, crudely), keys are views or decoded `String`s, all from a `BumpAllocator`.
- No UTF-8 validation, escapes are decoded without checking, errors are a line number at best.
- Verdict: fine for the IDE's own files, wrong for general JSON. Keep it as a benchmark baseline, as TomlBeef does.

### EinScott/json, Zorbn/Json, Atma.Json
- EinScott/json: a clean recursive descent with `readerMaxDepth` (256) and `readerDuplicateKeyBehavior` as **static** fields. Its number parser multiplies digits into a double and applies `Math.Pow(10, exponent)` (`Read.bf:353-435`), so large and small values are wrong. Surrogate pairs go through `UTF16.Decode` of a hand-packed `char32` (`Read.bf:116-123`). An invalid escape reaches a discarded `Result` and aborts the process.
- Zorbn/Json: `Result` values are discarded inside the string parser (any `\u`, `\x` aborts), `Dictionary.Add` asserts on duplicates, there is no null.
- Atma.Json: `ReadString` reports "Unicode escape is not supported" (`JsonParser.bf:428`); single quotes and `+` are accepted (`:65-67`); trailing input is ignored; converters use runtime reflection over `void*` targets.

### Minimal parse-and-walk code, for the benchmark

These are the snippets the harnesses used here. StructuredData's sniffing means a benchmark must not feed it a top-level array whose first element is a number or literal.

```bf
// BJSON (namespaces BJSON, BJSON.Models)
var result = scope Deserializer(DeserializerConfig()).Deserialize(text); // or Json.Deserialize(text)
defer result.Dispose();
static int Count(JsonValue v)
{
	int n = 1;
	switch (v.type)
	{
	case .OBJECT: for (let (key, val) in v.As<JsonObject>()) n += Count(val);
	case .ARRAY: for (let val in v.As<JsonArray>()) n += Count(val);
	default:
	}
	return n;
}
if (result case .Ok(let root)) count = Count(root);

// StructuredData (namespace Beefy.utils; copy StructuredData.bf and DisposeProxy.bf as TomlBeef's fetch.sh does)
let sd = scope StructuredData();
sd.LoadFromString(text);
static int Count(StructuredData sd)
{
	int n = 1;
	let v = sd.GetCurrent();
	if (v is StructuredData.Values) // NamedValues (objects) derive from Values
		for (let keyOrIndex in sd.Enumerate()) n += Count(sd); // Enumerate moves the cursor
	return n;
}

// EinScott/json (namespace Json)
let tree = scope JsonTree();
Json.ReadJson(text, tree);
static int Count(JsonElement e)
{
	int n = 1;
	switch (e)
	{
	case .Object(let o): for (let (k, v) in o) n += Count(v);
	case .Array(let a): for (let v in a) n += Count(v);
	default:
	}
	return n;
}
count = Count(tree.root);
```

## What Beef itself offers

**Numbers.** Since 2026-08-25 (in 0.43.6) the runtime parses doubles with fast_float and formats them with zmij (`BeefRT/rt/Internal.cpp:1240-1320`, `rt/fast_float.h`, `rt/zmij.c`).
- `double.Parse` (`corlib/src/Double.bf:194-225`) is correctly rounded, but it is lenient: it accepts `1.`, `.5`, `+1`, `Infinity`, `nan` (case-insensitive) and the culture's decimal separator, and returns ±Infinity or 0 on overflow and underflow (`1e400` → Infinity, `1e-400` → 0). A JSON reader must check the grammar itself, pass a fixed `NumberFormatInfo` (KdlBeef's `sNumberFormat`) and decide what overflow means. Each call is an extern call after a few string compares, so the siblings' inline Clinger fast path (`TryParsePlainNumber`) still pays.
- `double.ToString` gives the shortest round-trip digits in a C `%g`-like layout: `1000000000000000`, `1e+16`, `1e+21`, `1e-05`, `0.1`, `1`, `-0`, `5e-324`. All of that is valid JSON, but it is not the ECMAScript layout (JCS: `1e+21` but `0.00001`), and integral doubles lose their `.0`. The digits are right, so a writer can re-layout them without porting zmij.

**SIMD.** Measured here with small test programs:
- corlib has only `float2`, `float4`, `int32_4`, `bool2`, `bool4` and a `v128` union (`corlib/src/Numerics/`); `SSE.bf` is mostly unimplemented `extern` stubs.
- A user type with `[UnderlyingArray(typeof(uint8), 16, true)]` and `[Intrinsic("eq")]`, `[Intrinsic("or")]`, `[Intrinsic("and")]` operators compiles to `pcmpeqb`/`por` (16 bytes), and with `BfSIMDSetting = "AVX2"` in the workspace config to `vpcmpeqb ymm` (32 bytes). The default setting is SSE2 (`IDE/src/Workspace.bf:322`). `Runtime.Features` reports SSE2/AVX/AVX2/AVX-512 at run time, but there is no per-function target, so AVX2 is a whole-build choice.
- There is no movemask. Comparison lanes are 0/1 bytes; a mask comes from two `(word & 0x0101…) * 0x0102040810204080 >> 56` multiplies, which LLVM keeps as multiplies (checked: correct in Debug and Release).
- Platform intrinsics (`[Intrinsic("x86:__builtin_ia32_pmovmskb128")]`) **crash the compiler** (exit 139): `BfIRCodeGen.cpp:3455` looks the intrinsic up and then passes `intrinsics[intrinId].mID` (−1 for platform intrinsics) instead of the ID it found. Indexing an element of a bool vector fails codegen with "BfIRTypeEx GetTypeMember OOB". No `pshufb`, `pclmulqdq`, `tzcnt` or `popcnt` is reachable (the intrinsic list, `BfIRCodeGen.cpp` `BfIRIntrinsic_*`, has none), which XmlBeef also found.
- So simdjson's stage 1 (nibble-table classification with `vpshufb`, prefix-XOR with carry-less multiply, bit extraction with `tzcnt`/`blsr`) cannot be written in Beef as designed. Byte compares at 16 or 32 lanes can, and 8-byte SWAR (the siblings' `ScanRun`, `FindInvalid`) works everywhere.

## Notes per implementation

### C

**yyjson** (`src/yyjson.c` 11,480 + `yyjson.h` 8,467 lines, 2026-09-09) is the design to beat without SIMD.
- Immutable document: `yyjson_val { u64 tag; union uni; }`, 16 bytes (`yyjson.h:4980`). The tag holds the type (3 bits), subtype (2 bits: UINT/SINT/REAL, NOESC for strings without escapes) and a 56-bit length (string bytes or child count). All values sit in one preorder array; a container's `uni.ofs` is the byte offset to its next sibling, so `get_next` is `ptr + (is_ctn ? ofs : 16)` (`yyjson.h:5203`) and the first child is `ctn + 1`. Object keys and values are adjacent slots. Flat arrays (no nested containers) index in O(1) (`yyjson.h:5148`). Key lookup is a linear memcmp scan returning the first match.
- Building needs no separate stack: while a container is open, `uni.ofs` points back to its parent and `tag` counts children; closing rewrites both (`yyjson.c:5547`).
- The value array is preallocated at `input_len / 6` values (16 for pretty input; `yyjson.c:326, 5414`) and grows ×1.5. The input is copied once into a buffer with 4 bytes of zero padding; strings are unescaped in place there and NUL-terminated over the closing quote (`yyjson.c:4847, 6276`). `INSITU` skips the copy.
- Mutable document: 24-byte values with circular child lists where the parent points to the tail (O(1) append and prepend). Converting needs a copy.
- Strings: 256-entry class tables, a 16× unrolled ASCII loop, and non-ASCII runs looped by sequence length (3-byte, then 2, then 4) for the branch predictor (`yyjson.c:4808-4890`).
- Numbers: a 19-digit unrolled integer path; Clinger when exact; a 64×128-bit multiply against `pow10_sig_table` (668 × 16 B, shared with the writer); DiyFp + bigint "bigcomp" as the slow path (`yyjson.c:3855-4480`). Writer: Schubfach (`yyjson.c:7635-7800`).
- Read flags (`yyjson.h:816-910`): `INSITU`, `STOP_WHEN_DONE`, `ALLOW_TRAILING_COMMAS`, `ALLOW_COMMENTS`, `ALLOW_INF_AND_NAN`, `NUMBER_AS_RAW`, `BIGNUM_AS_RAW`, `ALLOW_INVALID_UNICODE`, `ALLOW_BOM`, and JSON5 pieces. The default is strict: BOM, lone surrogates, invalid UTF-8 and `1e400` are errors; integers beyond u64 become doubles. No depth limit (non-recursive).
- `yyjson_incr` is not real streaming: the whole buffer must exist up front. Errors are a code, message and byte position, with `yyjson_locate_pos` for line/column. JSON Pointer, Patch and Merge Patch are built in.

**cJSON** (2026-09-16): ~64-byte malloc'd nodes with `prev`/`next`/`child` (`child->prev` is the tail). Numbers go through locale `strtod` over `[0-9+-eE.]` (so `01`, `+1`, `1.` pass), `valueint` saturates at INT_MAX, `%1.15g` then `%1.17g` on output. No UTF-8 validation, `\u0000` truncates, default lookup is case-insensitive, trailing garbage accepted, `CJSON_NESTING_LIMIT` 1000, errors through a **global** pointer. Everything to avoid in one file.

**json-c** (2026-09-30): ref-counted objects, `lh_table` linkhash (insertion order kept), a true byte-at-a-time incremental tokener (`json_tokener_parse_ex` returns `continue` for partial input). The non-strict default accepts comments, single quotes, NaN, trailing commas, raw control characters and clamps integer overflow silently. Default depth **32**; duplicate keys last-wins; lone surrogates become U+FFFD. Doubles keep their source text for output.

**Jansson** (2026-07-09): hashtable plus ordered list; strict (UTF-8 always validated, lone surrogates, integer and real overflow are errors; `JSON_REJECT_DUPLICATES`, `JSON_DECODE_ANY` for scalars, `JSON_ALLOW_NUL`). `json_error_t { line, column, position, source, text }` is the best located error among the C libraries. `json_pack`/`json_unpack` format strings are its typed extraction. Slowest in yyjson's benchmark (0.05 GB/s).

**YAJL** (dead since 2015) is still the cleanest push design: callbacks, `yajl_parse(chunk)` repeatedly, partial tokens carried over in a buffer, a `number` callback that delivers raw text (lossless), a byte stack instead of recursion. `yajl_tree` grows arrays by one element per realloc (quadratic).

### C++

**simdjson** (2026-10-01).
- Stage 1 (`src/generic/stage1/`) processes 64-byte blocks: escaped characters from backslash runs with an add/XOR trick and a cross-block carry (`json_escape_scanner.h:50-140`); the in-string mask is `prefix_xor(quote & ~escaped)` via `pclmulqdq` (`haswell/bitmask.h:18`); whitespace and operators are classified with one `vpshufb` each (`src/haswell.cpp:43-90`); unescaped controls in strings accumulate into an error mask; the bits are flattened into a `uint32` index array with `popcount` and unrolled `tzcnt`/`blsr` writes that overrun into slack (`json_structural_indexer.h:93-120`). UTF-8 is validated in the same pass (Keiser-Lemire lookup, ASCII blocks skipped).
- Stage 2 is a goto state machine over the indexes that writes a tape of 64-bit words (8-bit type tag + 56-bit payload). Containers store the index of their closing word (O(1) skip) and a saturated child count; numbers take two words; strings go to a separate buffer with a length prefix.
- On-Demand: `iterate()` runs stage 1 in full, then a forward-only cursor parses only what is asked. Values are consumed once; `find_field` is forward-only and `operator[]` wraps once; only one field value per object is live; misuse is detected only in development builds. Skipped values are skipped by bracket depth and **not validated** ("validate what you use"; `doc/ondemand_design.md`), trailing content must be checked by the caller (`at_end()`), and there are no line numbers.
- 64 bytes of readable padding are required after the input. Defaults: depth 1024, duplicates kept, `1e400` and integers ≥ 2^64 are errors (`BIGINT_ERROR` unless numbers as strings), BOM skipped (the docs say rejected). `raw_json()` returns a value's source text.

**RapidJSON** (2025-02-05, no release since 2016): SAX `Reader` with the DOM as a handler that pops each container's children into one allocation; 16-byte values with 13-char SSO on x86-64; `MemoryPoolAllocator` (64 KiB chunks); in-situ parsing. Defaults to remember as warnings: UTF-8 validation off, a not-correctly-rounded `strtod`, Grisu2 output (round-trips, not always shortest), no depth limit in the recursive parser, linear member lookup. SIMD (SSE4.2 `cmpistri` whitespace, 16-byte `cmpeq` string scan with alignment to avoid crossing pages) only with a define.

**Boost.JSON** (2026-09-23): `basic_parser::write_some(more, data, size)` is resumable anywhere; on running out of input each function pushes its state onto a stack and resumes by popping; every function is templated on "stack empty" so the common no-suspend path has no resume checks, and options are template parameters too. Objects are an insertion-ordered table with linear search up to 18 entries and an appended hash index beyond. Defaults: depth **32**, imprecise numbers (`1e400` → infinity silently), last-wins duplicates. `parse_into<T>` binds without a DOM through a tree of handlers.

**nlohmann/json** (2026-10-01): one heap allocation per container and string, `std::map` objects (sorted keys; `ordered_json` is a vector of pairs), virtual SAX. Now iterative, with `from_chars` floats and optional simdutf. The reference for ergonomics and the floor for speed (0.05–0.14 GB/s).

**glaze** (2026-09-29): aggregate reflection via structured bindings and member names from `__PRETTY_FUNCTION__`. Struct keys are dispatched with a per-type hash chosen at compile time (a single distinguishing character position, front bytes, length, small mod tables; `core/reflect.hpp:1594`) and **confirmed with a memcmp** of the key and closing quote. Defaults: `error_on_unknown_keys = true`, `validate_utf8 = true`, depth 256, zmij output. Its out-of-order test (Glaze 1219 MB/s vs simdjson On-Demand 89) is the cost of On-Demand's forward-only lookup.

**DAW JSON Link** (2026-09-09): typed contracts with no DOM; out-of-order members are remembered as source ranges and parsed later; `json_value` is a lazy pull view. By default names are matched **by hash and length only** (full compare only after a compile-time collision), `IEEE754Precise::no` allows 0–2 ulp errors, trailing data is unchecked, and the event parser has no depth limit. Fast and unsafe defaults; its lazily computed line/column with 50 characters of context is worth copying.

### Rust

**serde_json** (1.0.151, 2026-08-07): recursive descent straight into serde visitors. `SliceRead` computes line/column only on error (memchr over the prefix); `IoRead` pulls a byte at a time (≈0.28 vs 0.83 GB/s). Strings without escapes are borrowed, others decoded into a reused scratch buffer; `skip_to_escape` is SWAR. Recursion limit 128. Integers u64/i64, beyond that f64; `-0` → −0.0. The **default float path is two roundings** (`2.2250738585072011e-308` misrounds, probed); `float_roundtrip` fixes it at about 2× float cost. Writes floats with zmij (replacing ryu). `Value` maps are BTreeMap (`preserve_order` → IndexMap), last wins; derive errors on duplicate fields and missing non-Option fields, ignores unknown fields. `RawValue` captures a value's text; `arbitrary_precision` keeps numbers as strings.

**simd-json** (0.18.1): simdjson 0.2 port that needs `&mut [u8]` (strings unescaped into the input), tape nodes carry subtree counts. Probed bug: a lone high surrogate `"\uD800"` silently becomes NUL. Duplicates kept by default ("undefined behavior" per its README). Errors are byte indexes, often 0.

**sonic-rs** (0.5.10): single pass with SIMD for long strings, whitespace (a cached 64-bit non-space bitmap per window) and container skipping (bracket counting over the in-string mask, JSONSki-style). 16-byte nodes in one bump arena; objects are pair arrays with linear lookup. `LazyValue` / `get(path)` / `get_many` with a pointer tree read only what they need; probed: checked `get` does not validate input after the target. Probed: `-0` and `-0.0` lose their sign, and the DOM recurses without a limit (100k levels abort with a stack overflow). Errors carry line, column and a snippet.

**jiter** (pydantic, 0.17): a pull API (`peek()` returns the first byte's class; `next_object` / `next_key` / `array_step`; `known_*` after a peek) and an iterative value builder that shares one element stack and one member stack across all containers, copying each closed container's slice into an exact-size allocation. `LazyIndexMap` is gone (objects are plain pair vectors). Big integers up to 4,300 digits, correctly rounded floats, but `1e400` → infinity (probed). Partial-JSON parsing for LLM streams. Its Python string cache is direct-mapped by hash.

### Go

**encoding/json v1** (legacy): per-byte state machine through a function pointer, a full validation pass before decoding, case-insensitive field matching, invalid UTF-8 replaced by U+FFFD, last-wins duplicates, `Decoder` buffers a whole top-level value, errors are byte offsets. 0.08–0.10 GB/s.

**encoding/json/v2 and jsontext** became the default in **Go 1.27** (August 2026; `internal/buildcfg/exp.go:87`, opt-out `GOEXPERIMENT=nojsonv2`), and v1 is now `v2.Unmarshal` with `DefaultOptionsV1()`.
- `jsontext.Decoder`: `PeekKind`, `ReadToken`, `ReadValue` (raw bytes), `SkipValue`, `InputOffset`, `StackDepth`, `StackIndex(i)` and `StackPointer()` (RFC 6901 pointer of the current position). One buffer is split into consumed, previous-token and unread regions with an absolute base offset. Fast inlinable `consumeXXX` functions return "unexpected EOF" when the buffer looks truncated, and the slow path refills and resumes (`internal/jsonwire/decode.go:117-123, 465-472`): the cost of streaming stays off the common path.
- `Token` is allocation-free: it refers to the decoder's buffer and is valid only until the next call (checked by offset); `Clone()` copies.
- Defaults follow RFC 7493 (I-JSON): invalid UTF-8 and duplicate names are errors (`AllowInvalidUTF8`, `AllowDuplicateNames`), lone surrogate escapes too. Duplicate detection is a linear search per object switching to a map past 64 names or 1 KiB of names. Depth limit 10,000. Errors: byte offset + JSON Pointer.
- v2 semantics: case-sensitive names, unknown members ignored (`RejectUnknownMembers`), `omitzero`, nil slices as `[]`, `1e400` into float64 is `ErrRange`, `Value.Canonicalize` implements RFC 8785. `v2/doc.go:154-233` gives the security rationale (duplicates and case folding cause cross-parser disagreement).

**bytedance/sonic** JITs per-type codecs and uses C SIMD kernels translated to Go assembly (amd64/arm64 only); its default config does not validate UTF-8. **goccy/go-json**: opcode VM, NUL-sentinel buffer, SWAR string scan. **json-iterator** is unmaintained since 2022 and its "fastest" config writes 6-digit floats.

### Java

**Jackson** (3.x, `tools.jackson`, released 2025-10-03): streaming `JsonParser` with zero-copy text access, lazily parsed numbers (FastDoubleParser, on by default in 3.x), `ByteQuadsCanonicalizer` for names (UTF-8 packed into int quads, hash-flooding check), and in 3.x `nextNameMatch(PropertyNameMatcher)` that maps a name to a property index inside the parser. `StreamReadConstraints` (3.x): depth 500 (1000 in 2.x), number length 1000, string length 100 M (20 M in 2.x), name length 50,000, document length and token count unlimited. Every leniency is an opt-in `JsonReadFeature`; `STRICT_DUPLICATE_DETECTION` is off. Databind 3.x flipped `FAIL_ON_UNKNOWN_PROPERTIES` to false, `FAIL_ON_TRAILING_TOKENS` to true, enums to `toString()`. Locations carry line, column and offsets.

**fastjson2** hashes names while scanning (≤8 bytes packed into a long, else FNV-1a), generates readers with ASM that compare quoted names as one or two word loads, and is lenient by default (comments always skipped, single quotes, NaN). **DSL-JSON** generates codecs at compile time but matches names **by hash only** by default. **Gson** silently upgrades readers to lenient in `fromJson`, depth 255, nulls omitted on write, in maintenance mode.

### C#

**System.Text.Json** (.NET 10/11, `src/libraries/System.Text.Json/src/System/Text/Json/`).
- `Utf8JsonReader` is a `ref struct` over a span or a segmented sequence: `TokenType`, `ValueSpan` (or `ValueSequence` when a token straddles segments), `ValueIsEscaped`, lazy `GetString`/`CopyString`/`TryGetInt64`/`TryGetDouble`. Streaming is caller-driven: `isFinalBlock: false`, `Read()` returns false on an incomplete token, the caller saves `CurrentState` (`JsonReaderState`) and refeeds from `BytesConsumed`. Depth is a `BitStack` (64 levels in a ulong, then an array); `MaxDepth` 64. Options: `CommentHandling { Disallow, Skip, Allow }` (Allow reports comment tokens), `AllowTrailingCommas`, `AllowMultipleValues`. The string scan is one vectorized `IndexOfQuoteOrAnyControlOrBackSlash`. **UTF-8 and surrogates are validated only when a string is read**, so `JsonDocument.Parse` accepts invalid text.
- `JsonDocument` is the closest existing design to an ID-based read-only document. `MetadataDb` is a flat array of 12-byte `DbRow`s (`Document/JsonDocument.DbRow.cs:12-70`): source offset; length for scalars or member/element count for containers, its sign bit meaning "needs unescape" or "has complex children"; a 4-bit token type and 28-bit row count (subtree size, so skipping is `index += 12 * rows`). Arrays without nested containers index in O(1). Nothing is copied: values are parsed from the source on access. Rows come from `ArrayPool` (sized at input length + 12, i.e. one row per 12 bytes) and must be returned by `Dispose`. `JsonElement` is a (document, row offset) handle. Property lookup scans backwards (last duplicate wins) with a length pre-filter and no hash. Closing a container scans back for its open row (`FindIndexOfFirstUnsetSizeOrLength`), O(n·depth) in the worst case; keeping the open index on the stack avoids it.
- `JsonNode` is a separate mutable DOM (`JsonObject` materializes an `OrderedDictionary` lazily, so duplicates throw on first access, not on parse).
- Serializer defaults: names as declared (PascalCase), `JsonSerializerDefaults.Web` for camelCase and case-insensitive; unknown members skipped; `AllowDuplicateProperties = true` (last wins); enums as numbers; `[JsonDerivedType]` with a `$type` discriminator that must come first; `JsonSerializerOptions.Strict` (.NET 10) disallows unmapped members and duplicates. Property matching packs the first 7 bytes and the length into a ulong and starts at the next declared property (speculating that keys arrive in declaration order). The source generator emits a fast path for **writing only**.
- `Utf8JsonWriter` escapes HTML characters and all non-ASCII by default (`JavaScriptEncoder.Default`): a default to avoid. Doubles are shortest round-trip; NaN and infinity throw.

**Newtonsoft.Json**: UTF-16 reader, lenient by default (comments, single quotes, unquoted names, NaN, constructors), `DateParseHandling.DateTime` turns date-like strings into dates even in the DOM, big integers as `BigInteger`, MaxDepth 64 since 13.0.1, last-wins duplicates, errors with line, position and path.

### Python, JavaScript, Perl, Lua

- **CPython `json`**: C recursive scanner over a decoded `str`; NaN and Infinity accepted by default, lone surrogates accepted, big integers exact (capped at 4,300 digits), `1e400` → inf; `JSONDecodeError` computes line and column from the offset only when raised. Per-call key memo dict.
- **orjson** (3.12.0): parses with a vendored yyjson 0.12 (its own UTF-8 check first, depth 1024, one pool allocation sized from the input), then walks the yyjson array with its O(1) sibling skip to build Python objects. A 2,048-entry key cache indexed by xxh3 **without a byte compare**. Rejects NaN, lone surrogates and `1e400`. 4.2× CPython on twitter.json.
- **msgspec**: decodes straight into typed `Struct`s with no dict; key lookup starts at the slot after the previous match (`StructMeta_get_field_index`, `_core.c:5551`); unknown fields skipped unless `forbid_unknown_fields`; validation errors carry a path (`$.items[0].id`); rename policies lower/upper/camel/pascal/kebab; tagged unions.
- **pysimdjson**: "95% of the time spent loading a document into Python is spent creating Python objects" (`docs/performance.rst`); **simdjson_nodejs** is slower than `JSON.parse` once results cross into JS. A fast parser is wasted behind an expensive materialization boundary: the typed binding must be as fast as the reader.
- **V8 `JSON.parse`** (`src/json/json-parser.cc`): the previous array element's hidden class is feedback for the next object; keys are compared with memcmp against the expected key at each descriptor index, and an object whose keys all match in order is allocated directly with the final map. Strings are scanned with Highway SIMD, keys always internalized, short values internalized within a budget. Recursive with a fallback to an explicit stack on native stack overflow, so no depth limit. Last-wins, lone surrogates accepted, big integers lose precision silently (the reviver's `source` argument, shipped in Chrome 114, exists for this). `JSON.stringify` (2025) has a side-effect-free fast path, Dragonbox, and a segmented output buffer.
- **Cpanel::JSON::XS**: duplicate keys are an **error by default**, depth 512, big numbers become strings or Math::BigInt, SIMD UTF-8 validation (the `utf8_range` code protobuf uses), all five BOMs detected, `relaxed` = trailing commas + `#` comments + bare keys + single quotes, `incr_parse` splits a stream into documents by brace counting.
- **lua-cjson**: `encode_number_precision` 14 (`%.14g`, doubles do not round-trip), invalid UTF-8 passed through, `decode_invalid_numbers` on (inf, nan, hex), depth 1000, probably silent saturation of integer overflow.

### Zig

- **std.json** (Codeberg master, 0.18.0-dev): a byte state machine whose only allocation is a `BitStack` (no depth limit); `initCompleteInput` or `initStreaming` with `feedInput`/`endInput` and `error.BufferUnderrun`; tokens include `partial_string`, `partial_string_escaped_1..4` and `partial_number` so values can span buffers, with `nextAlloc` joining them up to 4 MiB. Strict: no comments, no trailing commas, no lone surrogates. Numbers are source text; `Value` keeps integers that fit i64, otherwise the text (`number_string`), so `1e400` survives losslessly. `parseFromSlice` (comptime reflection, linear `inline for` name match) defaults to **error on duplicate fields and on unknown fields**; tagged unions are `{"tag": payload}`. Diagnostics (line, column) are opt-in because counting lines costs.
- **zimdjson** (2025-04-28, Zig 0.14): simdjson port with DOM, On-Demand and typed schemas over a full slice or a reader. Streaming uses a "magic" ring buffer (the same memfd mapped twice so a wrapped window is contiguous); a token longer than one 64 KiB chunk fails. Schema options: `rename_all`, `assume_ordering`, `on_unknown_field = .ignore`, `on_duplicate_field = .error`, unions externally tagged by default; unordered keys go through a comptime hash with a searched seed. Its chart: typed twitter parse 1.07 GB/s (schema) vs 0.23 GB/s for unordered On-Demand lookups.

### JSONC, JSON5 and style-preserving editors

- **microsoft/node-jsonc-parser** (what VS Code uses): the scanner reports comments and line breaks as tokens; the parser is fault-tolerant and collects errors with offsets; `parseTree` nodes have offset, length and `colonOffset` but no trivia. `modify(text, path, value, options)` returns text edits: replacing a value replaces its span only; inserting puts `,"key": value` right after the previous member (before a comment on that line), so an existing trailing comma survives; deleting removes from the end of the previous member, taking comments between them along. `withFormatting` widens the edit to whole lines and runs `format()` on just that range. VS Code's JSONC: comments allowed, trailing commas a warning (none in settings files), formatting options taken from the open editor.
- **dprint/jsonc-parser** (Rust, 0.34): every parse option defaults to **lenient** (comments, trailing and missing commas, single quotes, hex, `+`, `.5`, Infinity/NaN, loose keys). Its CST (`src/cst/mod.rs`, 5,571 lines; `Rc<RefCell>` nodes with whitespace, newline and comment nodes) supports `append`, `insert`, `set_value`, `remove`, `sort_properties` (comments travel with their properties) and infers style for new content: newline kind from the first newline, trailing commas from the first multi-line container, indent unit by stripping the parent's indent from a child's (`compute_indents`, :3737). Removal deletes the value's own comma (or the previous one) and same-line trivia, and collapses an emptied container to `{}`.
- **tailscale/hujson** (JWCC: JSON with commas and comments only): every `Value` has `BeforeExtra` and `AfterExtra` (raw whitespace and comments) around a `Literal` (raw bytes for strings and numbers, decoded only on request), `Object`/`Array` carry an `AfterExtra` before the closing bracket, and a trailing comma is encoded as "the last value has an `AfterExtra`". `Pack()` reproduces the input byte for byte. `Standardize` overwrites comments and trailing commas with spaces (keeping newlines), so a strict parser then reports positions in the original file. Its patch code documents comment ownership (`patch.go:281-327`): comments before a member and on the same line after it move with it; comments around the colon are lost. About 570 lines of types for a lossless model.
- **JSON5** (spec 1.0, 2018): unquoted identifier keys, single quotes, line continuations, all JS escapes, hex, leading/trailing decimal points, `+`, Infinity/NaN, comments, trailing commas, extra whitespace. Rust `json5`/`serde_json5` and Python `json5`/`commentjson` drop comments on round-trip.
- **jsoncons** (C++): the kitchen sink (JSONPath, JMESPath, Pointer, Patch, Schema, CBOR and others, a pull cursor). Allows comments by default, and an `err_handler` callback can swallow recoverable errors. Depth 1024; Grisu3 with `%.17g` fallback.
- **RFC 8785 (JCS)**: I-JSON input (no duplicates), no whitespace, minimal string escaping (`\b \t \n \f \r \" \\`, lowercase `\u00hh` for other controls, everything else literal), numbers in ECMAScript `Number::toString` layout (integer digits up to 21, `0.000001`, `1e+21`, `-0` as `0`), keys sorted by UTF-16 code units recursively.

## Defaults in the wild

| | duplicate keys | depth | integers > int64 | `1e400` | `"\uD800"` | invalid UTF-8 | BOM | comments / trailing commas |
|---|---|---|---|---|---|---|---|---|
| yyjson | kept, first | none | u64, then double | error | error | error | error (flag) | flags |
| simdjson | kept, first | 1024 | u64, then error | error | error (WTF-8 opt) | error | skipped | no |
| RapidJSON | kept, first | none | u64, then double | error | error | **accepted** | stream wrapper | flags |
| Boost.JSON | last | 32 | u64, then double | **inf** | error | error | error | options |
| serde_json | last (Value) / error (derive) | 128 | u64, then double | error | error | error | error | no |
| sonic-rs / simd-json / jiter | kept / kept / kept | none / 1024 / 200 | f64 / error / BigInt | error / error / **inf** | error / **NUL** / error | error | error | no |
| Go v2 | **error** | 10,000 | lexeme, `ErrRange` on bind | `ErrRange` | error | **error** | error | no |
| System.Text.Json | last (Strict: error) | 64 | lazy `TryGet` | inf (lazy, unverified) | error on access | error on access | skipped (unverified) | options |
| Jackson 3 | last | 500 | BigInteger | inf (unverified) | passes (unverified) | error | skipped | features |
| CPython / V8 | last / last | C stack / none | exact / lossy | inf / inf | **accepted** / accepted | error / n/a | str: error | no |
| orjson / msgspec / Cpanel | last / last / **error** | 1024 / C stack / 512 | double (unverified) / exact / string | error / error / not checked | error | error | error (unverified) / not checked / detected | no / no / relaxed |
| Zig std.json | error (typed and Value) | none | number string | number string | error | error | — | no |
| BJSON | last (option) | 200 | u64, then double | **inf** | error | error | error | comments option |

## Number algorithms

- **Parsing.** Clinger's fast path (significand ≤ 2^53, |exp| ≤ 22: one exact multiply or divide) covers most real data; Eisel-Lemire (Lemire, "Number Parsing at a Gigabyte per Second", SP&E 2021, <https://arxiv.org/abs/2101.11408>) handles up to 19 digits with a 64×128-bit multiply and a 651 × 128-bit table (10,416 B in fast_float); a big-integer comparison is needed only for long, near-halfway inputs (Mushtak & Lemire 2023 removed the other fallback). fast_float claims ≈1 GB/s on random doubles vs 191 MB/s for `strtod`. Beef's `double.Parse` already is fast_float, so JsonBeef needs only the inline Clinger path in front of it.
- **Shortest writing.** Grisu2 is not always shortest (RapidJSON); Grisu3 needs a fallback (≈1 KB table); Ryu (Adams 2018) 10.7 KB or ≈0.8 KB small tables; Schubfach (Giulietti; JDK 19+, yyjson) ≈10 KB; Dragonbox (Jeon; {fmt}, V8's stringify, DAW) 9.9 KB or ≈0.6 KB compressed; **zmij** (Zverovich, December 2025, <https://vitaut.net/posts/2025/faster-dtoa/>) is a reduced Schubfach, formally verified, about 2× Schubfach and 68% faster than Dragonbox by its author's figures, with a 10 KB table or a table-free mode, already adopted by serde_json, glaze, .NET and Beef's runtime. JsonBeef should use the runtime's zmij digits and do its own layout.
- **Integers**: accumulate in a uint64 with an overflow check (8 digits at a time with SWAR is an option: simd-json, sonic-rs); write with the runtime's `int64.ToString`.

## Speed references for the benchmark

The standard corpus is nativejson-benchmark's `twitter.json` (631,515 B), `citm_catalog.json` (1,727,204 B) and `canada.json` (2,251,051 B). Machines, compilers and years differ, so compare ratios within one source.

| source (machine) | library | twitter | citm | canada |
|---|---|---|---|---|
| Langdale & Lemire 2019, Table 10, <https://arxiv.org/abs/1902.08318> (i7-6700, GCC 9), GB/s | simdjson DOM | 2.2 | 2.5 | 1.1 |
| | sajson / RapidJSON / RapidJSON in situ | 1.0 / 0.45 / 0.72 | 1.2 / 0.86 / 1.0 | 0.76 / 0.43 / 0.43 |
| | cJSON / nlohmann | 0.33 / 0.10 | 0.36 / 0.14 | 0.07 / 0.05 |
| yyjson report, <https://ibireme.github.io/yyjson_benchmark/reports/EC2_c5a.large_gcc_9.html> (EPYC 7R32, 2020), GB/s | yyjson / simdjson / RapidJSON | 1.67 / 1.52 / 0.26 | 1.70 / 1.65 / 0.52 | 0.74 / 0.60 / 0.15 |
| sonic-rs README, <https://github.com/cloudwego/sonic-rs#benchmark> (Xeon 8260), GB/s from its times | sonic-rs DOM / struct | 1.14 / 0.76 | 1.02 / 1.26 | 0.45 / 0.56 |
| | simd-json DOM / serde_json Value / serde_json struct | 0.53 / 0.22 / 0.46 | 0.52 / 0.21 / 0.66 | 0.19 / 0.14 / 0.24 |
| serde-rs/json-benchmark README (i7-6600U, 2021), MB/s | serde_json DOM / struct | 300 / 550 | 420 / 710 | 320 / 580 |
| | simd-json DOM / RapidJSON | 810 / 440 | 720 / 890 | 380 / 390 |
| go-json-experiment/jsonbench (Ryzen 9 9950X), GB/s | Go v1 / v2 / sonic, concrete types | 0.10 / 0.55 / 0.65 | 0.08 / 0.87 / 0.80 | (its canada is a 270 KB file) |
| Boost.JSON `bench/results.txt` (i7-7700K), MB/s presumably | Boost pool / Boost / RapidJSON pool / nlohmann | 682 / 329 / 603 / 137 | 1120 / 476 / 1200 / 140 | 642 / 385 / 506 / 55 |
| DAW `json_bench_results.json` (i9-9980HK, 2022), MB/s | DAW checked | 984 | 1270 | 1132 |
| simdjson-java README (Xeon E5-2686, JDK 21), twitter only | Jackson 2.17 DOM / typed; simdjson-java | ≈0.16 / ≈0.21; ≈0.48 GB/s | | |

- On-Demand (Keiser & Lemire 2024, <https://arxiv.org/abs/2312.17149>, Ice Lake, GiB/s, task throughput over twitter-based workloads): partial_tweets On-Demand 4.8–5.2, simdjson DOM 2.9–3.1, yyjson 0.96–2.0, RapidJSON 0.38–0.48; instructions per byte 2.3 / 3.5 / 4.5 / 22.2 (nlohmann 104).
- glaze README (670-byte synthetic struct, M1): read MB/s Glaze 1200, simdjson On-Demand 1163, yyjson 1106, DAW 479, RapidJSON 416, Boost 308, nlohmann 81.
- orjson: 4.2× CPython `json` deserializing twitter.json. No credible current per-file figures were found for System.Text.Json.
- Beef (measured here, loaded machine, synthetic 16.7 MB): StructuredData 152 MB/s, EinScott 62, CPython 47, BJSON 33. The siblings: KdlBeef's event pass 294–336 MB/s and document read 227–297 MB/s (`KdlBeef/docs/status.md`).

Credible targets: the reader and document in yyjson's class (scalar C, 0.7–1.7 GB/s on the three files); at minimum well above RapidJSON's default (0.26–0.86) and serde_json's Value (0.14–0.22). `canada.json` is bound by float conversion and should land near fast_float's speed. Put yyjson, simdjson (DOM and On-Demand), RapidJSON, serde_json and sonic-rs in `bench/compare` with BJSON and StructuredData as the Beef baselines.

## Typed mapping in other ecosystems

| role | serde | System.Text.Json | Jackson 3 | Go v2 | Zig std.json | glaze | BJSON | proposed JsonBeef |
|---|---|---|---|---|---|---|---|---|
| member names | as written; `rename_all` | as declared; Web: camelCase | as written; `PropertyNamingStrategies` | as written, case-sensitive | as written | as written; key transformers | as written; `[JsonPropertyName]` | `JsonNaming` on `[JsonObject]`, default as written (Beef public fields are camelCase); `[JsonName]`, `[JsonAlias]` |
| unknown members | ignored; `deny_unknown_fields` | skipped; `Disallow` | ignored (2.x: error) | ignored; `RejectUnknownMembers` | **error** | **error** | ignored; `[JsonExtensionData]` | ignored; strict option; `[JsonExtensionData] Dictionary<String, …>` |
| missing members | error unless `Option`/`default` | default; `[JsonRequired]` | default | zero value kept | error unless default | ok | kept; `[JsonRequired]` | kept (the siblings); `[JsonRequired]` |
| `null` | `Option::None` | null / default | null | zeroes | only into optionals | skip on write | leaves field | `T?` → null; otherwise absent |
| duplicate members | **error** | last wins (Strict: error) | last wins | **error** | **error** | last? | last | error by default (decision) |
| enums | variant names | **numbers**; `JsonStringEnumConverter` | `toString()` | — | name or int | `meta` | names; reads numbers | names through the naming policy; numbers accepted on read |
| polymorphism | externally tagged; `tag`, `content`, `untagged` | `[JsonDerivedType]`, `$type` first | `@JsonTypeInfo` | — | `{"tag": payload}` | auto or tagged variants | — | internally tagged, discriminator property configurable, any order |
| name matching | generated match | ordered speculation, 7-byte key | per-POJO matcher | map | linear | compile-time hash + memcmp | dictionary lookup | ordered speculation, then a generated switch on length and leading bytes, always confirmed by a byte compare |
| from | the token stream | the reader | the stream | the token stream | tokens | the bytes | the DOM | the reader **and** a document node |

## Conclusions for JsonBeef

### Layering
Four layers, the KdlBeef/XmlBeef shape plus one:
1. **Input**: the siblings' generic cursor. `JsonByteCursor` over memory (the window is the input, `Fill` folds to `false`) and `JsonBufferedStreamCursor` with absolute offsets, `mRetain`, `MaxTokenBytes` and the per-refill UTF-8 check. The internal `Result<T, JsonFailure>` with an empty error token (KdlBeef: 225 → 330 MB/s).
2. **Reader** `JsonReader`: a pull tokenizer in the style of `Utf8JsonReader` and `jsontext.Decoder`: tokens are views valid until the next call, numbers are lexemes with a kind, strings carry an "escaped" flag and decode on request. Iterative, with depth as a bit stack (STJ, Zig) plus a small frame stack for counts. `Skip()` validates what it skips.
3. **Document** `JsonDocument` built from the reader, mutable, with PreserveStyle (below).
4. **Typed binding** generated by `[JsonObject]`, reading from the reader directly (msgspec, glaze, serde) and from a document node (the siblings' document-first design, needed for in-place writes that keep comments).

**On-demand extraction** is the reader plus `Skip`, not a fifth engine. simdjson On-Demand's speed comes from stage 1 doing the scanning; without stage 1 a forward-only "lazy value" API is the pull reader with extra lifetime rules (values consumed once, one live field per object), which Beef cannot enforce at compile time and simdjson checks only in development builds. Its "validate what you use" (and sonic-rs's checked `get` that stops validating after the target) contradicts "fully correct". So offer:
- `reader.SkipValue()` with a fast validating skip (string bodies with the SWAR/vector scan, brackets counted, numbers and literals checked);
- `reader.ReadRaw(String)` / `JsonRawValue` (serde's `RawValue`, simdjson's `raw_json`) to capture a subtree's text;
- `JsonReader.Find(text, "/statuses/0/id")` and a multi-path variant (sonic-rs `get_many`) built on Skip, with a JSON Pointer of the current position (`jsontext.StackPointer`) for errors;
- typed binding straight from the reader, which is where On-Demand's real wins come from (zimdjson schema 1.07 GB/s, glaze).
A `Trusted` read option (skip validation in skipped values) can come later if measurement asks for it.

### Scanning, validation and SIMD
- **No stage 1.** yyjson reaches 75–110% of simdjson DOM with scalar code; Beef lacks the instructions stage 1 is built on (above). Use one pass.
- **Validate UTF-8 once, before the reader** (KdlBeef's `FindInvalid`, XmlBeef's 32-bytes-per-step version): over the whole input for memory, per refill for streams. Then string scans only look for `"`, `\` and bytes below 0x20.
- String bodies: the siblings' 8-byte SWAR scan, and measure a 16-byte `u8x16` compare + multiply-movemask variant (works at the default SSE2 setting; AVX2 is a build option). Whitespace: an inline fast path for zero or one space, then the SWAR loop (sonic-rs's observation that most gaps are 0–1 bytes in minified data, longer runs in pretty data).
- Structural dispatch on the first byte through a 256-entry class table generated at comptime (yyjson, XmlBeef).
- Keep 8+ readable bytes of slack after the window (pugixml, simdjson padding) so word scans need no tail loop; the in-memory cursor copies only when the input lacks it, or the document copies the input once anyway (XmlBeef, yyjson).
- Bit tricks Beef lacks (`tzcnt`) are a de Bruijn multiply or a byte loop over the flagged word, as the siblings do. File the two compiler bugs found here upstream (platform intrinsic ID; bool-vector element access).

### Document representation
Three candidates:
- **STJ `MetadataDb`**: 12-byte rows that point into the source, values decoded on access, subtree row counts. The smallest and fastest to build, but read-only (STJ needs a second DOM, `JsonNode`, for mutation), the source must stay alive, and every access re-parses.
- **yyjson's immutable array**: 16-byte values in preorder with sibling offsets, decoded strings and numbers. The fastest to read, but also read-only (yyjson has a second, linked, mutable document).
- **The siblings' node IDs with links**: a record table with parent, first/last child, next/previous sibling, generation-checked 16-byte handles, removal flags, Positions and PreserveStyle side tables indexed by ID. Mutable in place, one model for everything, and the typed binding and PreserveStyle designs from KdlBeef/XmlBeef carry over unchanged.

Recommendation: **node IDs with links, built in preorder**, with records kept as small as possible because JSON documents are dominated by scalars (canada.json is about 330,000 numbers):
- payload, 8 bytes: int64, uint64 or double bits; or a string's (offset, length) in the text store; or a container's (count, last child);
- member name, 8 bytes: (offset, length) in the text store, unused in arrays;
- first child, next, previous and parent IDs, 4 bytes each; kind and flags (number kind, escaped, has lexeme, removed, member-of-object).
That is 40 bytes against yyjson's 16 and STJ's 12 per value. Building in preorder means `firstChild == id + 1` for every container that has children until something is edited, which keeps the cache behavior close to yyjson's. KdlBeef measured a packed record slower than a plain one, so the plan should measure a 32-byte variant (dropping `previous`, found by a sibling scan on removal) against this rather than assume. Preallocate records from the input size (yyjson's `len / 6`; STJ's `len / 12` rows) and reuse the store's pools across reads (TomlBeef found fresh pools costing up to 40% of parse time).

### Strings
- The document copies its input once into its store (XmlBeef) and keeps unescaped strings and member names as (offset, length) views of that copy; strings with escapes are decoded into the store. The reader returns raw views with `ValueIsEscaped` (STJ) and decodes into a caller buffer or reusable buffer on request.
- Decoding validates escapes and pairs surrogates; a lone surrogate escape is an error by default (yyjson, simdjson, serde, Go v2, STJ on access), with a `JsonInvalidUnicode { Error, Replace }` option. WTF-8 (simdjson's `get_wobbly_string`) only if a real use appears.
- `\u0000` is legal and strings are length-based throughout.
- No interning by default. A per-document key table (CPython's memo, V8's internalization) is worth measuring for arrays of same-shaped objects, where keys repeat thousands of times; any cache must confirm with a byte compare (orjson's hash-only cache and DSL-JSON's hash matching are the counterexamples).

### Numbers
- The reader classifies each number: `Integer` (fits int64), `UInteger` (2^63 to 2^64−1), `Float` (fraction or exponent, or `-0`), `BigInteger` (more digits than uint64), each with its lexeme view. Grammar is checked by the scanner itself (leading zeros, `1.`, `.5`, `+1`, `1e`); conversion never sees non-JSON text.
- Integers accumulate in a uint64 with overflow detection during the scan (free). Floats: the inline Clinger path, then `double.Parse` with a fixed `NumberFormatInfo` on the validated lexeme.
- **Overflow is not an error at read time and never becomes infinity silently.** `1e400` stays a `Float` whose conversion reports out-of-range: `GetDouble` fails (an option may map it to ±infinity), the lexeme is kept, and the canonical writer writes it back as written. Integers beyond uint64 are `BigInteger` with their lexeme (Zig's `number_string`, yyjson's `BIGNUM_AS_RAW`, simdjson's numbers-as-strings). This passes JSONTestSuite's `i_number_*` cases either way and loses nothing.
- `-0` keeps its sign (as the double −0.0), unlike sonic-rs and simd-json.
- The document stores converted values (int64/uint64/double bits) plus a "has lexeme" flag; whether every lexeme is kept in plain reads (KdlBeef drops integer lexemes) is a plan decision: keeping them costs 8 bytes per number but makes `1.0` vs `1` and `1E2` survive canonical writes.
- Writing: integers through `ToString`; doubles through `double.ToString` (zmij digits) re-laid out into the chosen format: JsonBeef's canonical form (shortest digits, `.0` on integral values so the type survives, exponent without zero padding) and the ECMAScript layout for JCS. Port zmij only if profiling shows the extern call matters.

### Object members and duplicates
- Members stay in document order; lookup scans from the end so the last duplicate wins (STJ, KdlBeef). KdlBeef measured 28–64 ns at 4–16 entries; JSON objects can be much larger (dictionaries keyed by IDs), so add a per-object hash index built lazily on the first lookup in an object past about 32 members, stored in a side table by node ID and dropped on mutation of that object (Boost.JSON switches at 18, jsontext's duplicate check at 64 names).
- Duplicates: JSONTestSuite requires accepting `{"a":"b","a":"c"}` (`y_object_duplicated_key*.json`), so the default must accept. Keep all members (round-trip, PreserveStyle), resolve lookups to the last, and offer `DuplicateMembers { Keep, Error }` on read (Error uses jsontext's linear-then-hash check). Typed binding errors on a duplicate field by default (serde, Go v2, Zig, zimdjson, Cpanel; duplicate-key smuggling is .NET 10's stated reason for `Strict`).

### Streaming and multiple documents
- The KdlBeef stream cursor: a fixed window retained from the current token, refilled with a memmove, doubled for long tokens up to `MaxTokenBytes`. Scans resume at the old end after a refill (expat's quadratic re-tokenization, CVE-2023-52425). jsontext's split between inlinable fast paths and a refill-and-resume slow path is the pattern for keeping the in-memory path free of stream checks; the siblings' `Grow` that folds to `false` already does this.
- A push front end (`Feed(bytes)` + `Finish()`, YAJL, Boost.JSON, STJ's `isFinalBlock`) is cheap on top of the window and serves sockets; decide whether it is in the first version.
- `AllowMultipleValues` / `ReadMany` for NDJSON and concatenated values (STJ, yyjson `STOP_WHEN_DONE`, simdjson `iterate_many`, serde's `StreamDeserializer`).

### Errors, positions, limits
- TomlBeef/KdlBeef's `JsonParseError`: kind enum, message, line, column, offset, length, source name; line and column computed from the offset on demand (CPython, serde `SliceRead`, DAW, the siblings' `Locate`), plus the JSON Pointer of the failing value (jsontext, STJ's path, msgspec's `$.items[0]`), which the reader's frame stack makes cheap. Typed binding errors name the field and are located at the value.
- `JsonReadConfig` limits with documented defaults: `MaxInputBytes`; `MaxDepth` (the survey spans 32 to unlimited; the reader is iterative, so depth costs a frame: 1024 matches simdjson, yyjson's orjson build and zimdjson); `MaxStringBytes` and `MaxNameBytes` (Jackson 100 M / 50,000); `MaxNumberDigits` (Jackson 1,000; CPython caps big-integer conversion at 4,300 digits as a DoS guard); `MaxTokenBytes` for streams; `MaxNodes`. Errors are sticky; collect-errors with recovery is optional, as in KdlBeef (jsonc-parser's fault-tolerant parse shows the recovery points: resync at `,` `}` `]`).
- Strict by default, one config for every entry point: no comments, no trailing commas, no NaN/Infinity, no BOM unless `AllowBom` (yyjson rejects, simdjson and Jackson skip; TomlBeef and KdlBeef skip one BOM, which is a reasonable default if the plan wants consistency with them), top-level scalars accepted (RFC 8259).

### Style-preserving mode (PreserveStyle) and JSONC
- **Dialect**: `JsonDialect { Json, Jsonc }` presets over `AllowComments` and `AllowTrailingCommas` (VS Code's JSONC and hujson's JWCC are exactly these two). JSON5 (unquoted keys, single quotes, hex, Infinity) is a separate decision; nothing in the target use (hand-edited config files: VS Code settings, tsconfig, devcontainer.json) needs it.
- **Mechanism**: KdlBeef's per-event source slices copied into sidecar records only in this mode, which is hujson's model: per value and member, the leading trivia (whitespace and comments since the previous `{ [ , :`), the raw text of the key and of the value (string escapes as written, `é` vs `é`, `\/`; number lexemes `1.50e+03`), the trivia around `:`, and the trailing trivia up to `,` or the closing bracket; per container, the trivia before the closing bracket and whether it had a trailing comma; plus the BOM, the text after the root and the newline kind. An unchanged document writes back byte for byte; only dirty pieces are regenerated.
- **Edits**: a changed value keeps its key's slice and surrounding trivia and is written in its original style (a number in its original format family, a string with the same escaping choices). A new member follows dprint's inference: the newline kind of the file, the indent unit derived from the parent's and a sibling's indent, a trailing comma if that container (else the file) uses them, and the inline-or-multiline form of the container (a single-line object stays single-line). Comment ownership follows hujson: comments before a member and on its line after it belong to it and move or disappear with it. Removing the last member keeps or drops the trailing comma consistently with the container.
- **Typed binding** writes into a PreserveStyle document in place (the siblings), so a settings object bound, changed and saved keeps every comment.

### Writer
- Compact by default; pretty with an indent string (two spaces by default: `JSON.stringify(x, null, 2)`, Jackson, STJ) and LF, never the platform newline; optional final newline.
- Minimal escaping (`"`, `\`, and controls as `\b \f \n \r \t` or `\u00XX`); non-ASCII written raw; options for `EscapeNonAscii` and HTML-safe output, off by default (STJ's default is the one to avoid). Strings set through the API are validated as UTF-8 when set.
- NaN and infinity are errors (an option may write `null`, as yyjson, serde and orjson do).
- `JsonCanonical` / JCS (RFC 8785): sorted keys by UTF-16 code units, ECMAScript number layout, no whitespace, error on duplicates.

### Typed mapping (`[JsonObject]`)
- KdlBeef's and XmlBeef's generator (`IComptimeTypeApply`, `ScanChain`, `FieldPlan`, emitted read and write methods, converters, inheritance and mapping checks, `ShowGenerated`), with the defaults in the table above.
- Emit two read paths: `JsonRead(ref JsonReader)` binding straight from tokens (members dispatched by a generated matcher: the next declared field first, as STJ, msgspec and V8 do, then a switch on length and the first 8 bytes compared as a word, confirmed by a byte compare) and `JsonRead(JsonNode)` for documents; writing goes to a `JsonWriter` or updates a node in place.
- Containers: `List<T>` as arrays, `Dictionary<String|integer|enum, T>` as objects (TomlBeef's recent change), sized arrays, `T?`; nested `[JsonObject]`s; polymorphism through an internally tagged discriminator resolved with `Type.TypeDeclarations` (KdlBeef's `[KdlChildren]` lookup), readable in any member order (DAW remembers out-of-order members as ranges; with a document it is a lookup).
- Numbers are range-checked into the field type (a `Float` lexeme into an integer field is an error; serde, Go v2). Strings are never auto-typed (Newtonsoft's dates).
- The build stops on colliding names, unsupported field types and reserved names, as in the siblings.

### API naming worth copying
- Reader: `Next()` returns a `JsonToken` (`StartObject`, `EndObject`, `StartArray`, `EndArray`, `PropertyName`, `String`, `Number`, `True`, `False`, `Null`, `Comment` in JSONC with comments reported, `EndOfDocument`); `TokenKind`, `Depth`, `Offset`, `EndOffset`, `RawValue`, `ValueIsEscaped`, `GetString(String)`, `NumberKind`, `TryGetInt64`, `TryGetUInt64`, `TryGetDouble`, `NumberLexeme`, `SkipValue()`, `ReadRaw(String)`, `GetPointer(String)`, `Locate(offset)`.
- Document: KdlBeef's `JsonNode` handle with `Kind`, `Count`, `this[StringView]`, `this[int]`, `TryGet…`, `Get…(fallback)`, `Members`, `Elements`, `Find(pointer)`; mutation `Add`, `Insert`, `Set`, `Remove`, `Move*`.
- Config: `JsonReadConfig` with `MetadataMode { None, Positions, PreserveStyle }`, the dialect flags and the limits.

### What to avoid (merged from all of the above)
- Lenient defaults (json-c, Newtonsoft, Gson's silent upgrade, dprint's all-true options, fastjson2) and defaults that depend on the entry point.
- Unchecked UTF-8 (RapidJSON, cJSON, sonic's default, lua-cjson) or validation deferred to access (STJ).
- Silent number damage: infinity for `1e400` (CPython, V8, Boost, jiter, BJSON), wrapped integers (StructuredData), float32 (StructuredData), non-correctly-rounded defaults (RapidJSON, serde_json, DAW), lost `-0` (sonic-rs, simd-json), `%.14g` output (lua-cjson), Grisu2.
- Silent string damage: lone surrogates to NUL (simd-json) or CESU bytes (StructuredData, EinScott).
- Recursion without a limit (RapidJSON, sonic-rs DOM, StructuredData, Zorbn, Atma) and fixed limits that cannot be configured (BJSON).
- Hash-only name matching (DSL-JSON, DAW, orjson's cache) and case-insensitive matching by default (Go v1, cJSON).
- Per-byte virtual reads and a heap container per object (BJSON), per-element realloc (YAJL tree).
- Global or static configuration and error state (cJSON, EinScott's static options).
- On-Demand-style partial validation presented as parsing.
- Aggressive or platform-dependent writer defaults (STJ escaping, platform newlines).

## Decisions the plan must make

1. **Document record layout.** The linked 40-byte record recommended above, a measured 32-byte variant, or a separate read-only flat document (yyjson/STJ style) beside a mutable one? The siblings use one linked model.
2. **Number lexemes.** Keep every number's lexeme in plain reads (exact canonical output of `1.0`, `1E2`; 8 bytes per number) or only in PreserveStyle (KdlBeef drops integer lexemes)? And is float conversion eager in the document (recommended) or lazy (STJ)?
3. **Out-of-range numbers.** Keep `1e400` and big integers as lexemes with a failing `GetDouble` (recommended), or reject them at read time (yyjson, simdjson, serde)?
4. **Duplicate members.** Keep all with last-wins lookup (recommended, required by JSONTestSuite) or keep only the last? Is typed binding's default error (recommended) or last-wins?
5. **Default limits**, especially `MaxDepth` (1024 recommended; the siblings use 256) and whether a BOM is skipped (siblings) or rejected (yyjson, serde).
6. **Dialects.** JSONC (comments, trailing commas) only, or JSON5 too? Are comments reported as reader tokens in plain reads, or only in PreserveStyle?
7. **SIMD.** Ship SWAR only, or a `u8x16` string and whitespace scan as well, after measuring it at the default SSE2 setting? AVX2 builds stay a user choice.
8. **Streaming scope.** Pull over a `Stream` (the siblings) only, or also a push `Feed`/`Finish` API and NDJSON `ReadMany` in the first version?
9. **On-demand surface.** `SkipValue`, `ReadRaw`, pointer `Find` and typed binding from the reader (recommended), or also a lazy value type over a validated buffer?
10. **Typed-mapping defaults.** Naming default (as written vs camelCase), unknown members (ignore vs error), enums (names vs numbers), discriminator property name, null into non-nullable fields.
11. **Float output format.** JsonBeef's canonical layout (with `.0` on integral doubles) vs the ECMAScript layout everywhere; JCS as a separate writer mode.
12. **BJSON overlap.** Does TomlTester move from BJSON to JsonBeef once JsonBeef reads JSON, and are the attribute names chosen to avoid colliding with BJSON's for users of both?
