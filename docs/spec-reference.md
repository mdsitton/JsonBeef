# JSON implementer's reference

A checklist of the exact rules, the implementation-defined points and the edge cases that trip JSON
implementations, compiled from the documents themselves (fetched 2026-10-01):

- **RFC 8259** (STD 90, December 2017, <https://www.rfc-editor.org/rfc/rfc8259>), cited as `§n`. It
  obsoletes RFC 7159 (2014), which obsoleted RFC 4627 (2006).
- **ECMA-404** 2nd edition (December 2017,
  <https://ecma-international.org/publications-and-standards/standards/ecma-404/>), cited as `E404 §n`.
- **RFC 7493** I-JSON (`I-JSON §n`), **RFC 8785** JSON Canonicalization Scheme (`JCS §n`), **RFC 6901**
  JSON Pointer (`JP §n`), **RFC 7396** JSON Merge Patch, **RFC 6902** JSON Patch, **RFC 7464** JSON text
  sequences (`RS §n`).
- Extensions: **JSON5** 1.0.0 (March 2018, <https://spec.json5.org/>, `J5 §n`), Microsoft's
  **jsonc-parser** (`microsoft/node-jsonc-parser` at commit `164a8e9e`, 2026-09-29) and the draft JSONC
  specification at <https://jsonc.org/>, **JSON Lines** (<https://jsonlines.org/>), **NDJSON** 1.0.0
  (<https://github.com/ndjson/ndjson-spec>).
- ECMA-262 for number formatting (`Number::toString`, ES2025 §6.1.6.1.20; ES2019 §7.1.12.1 as cited
  by JCS), and the Unicode Standard §3.9 for UTF-8 well-formedness and U+FFFD substitution.

"section N" means a section of this document. **error** = the input must be rejected with a located
error; **OK** = accepted with the stated result; **policy** = implementation-defined, the choice is
JsonBeef's (recommendations are marked **Recommend**).

## 1. Grammar (§2 – §7)

```
JSON-text       = ws value ws
begin-array     = ws %x5B ws  ; [        begin-object    = ws %x7B ws  ; {
end-array       = ws %x5D ws  ; ]        end-object      = ws %x7D ws  ; }
name-separator  = ws %x3A ws  ; :        value-separator = ws %x2C ws  ; ,
ws              = *( %x20 / %x09 / %x0A / %x0D )
value           = false / null / true / object / array / number / string
false = %x66.61.6c.73.65    null = %x6e.75.6c.6c    true = %x74.72.75.65
object          = begin-object [ member *( value-separator member ) ] end-object
member          = string name-separator value
array           = begin-array [ value *( value-separator value ) ] end-array
number          = [ minus ] int [ frac ] [ exp ]
int             = zero / ( digit1-9 *DIGIT )      frac = decimal-point 1*DIGIT
exp             = e [ minus / plus ] 1*DIGIT      e = %x65 / %x45
string          = quotation-mark *char quotation-mark
char            = unescaped / escape ( %x22 / %x5C / %x2F / %x62 / %x66 / %x6E / %x72 / %x74 / %x75 4HEXDIG )
unescaped       = %x20-21 / %x23-5B / %x5D-10FFFF
```

- **A JSON text is any single value** (§2), including a bare scalar: `42`, `"a"`, `null` are complete
  documents. RFC 4627 allowed only an object or array; RFC 7159 dropped that, and I-JSON §4.1 only
  advises protocol designers against top-level scalars. Nothing may follow the value except `ws`:
  `[1]x`, `{}}`, `[][]` and `1 2` are errors (a multi-value reader is an extension, section 12.4).
- **Whitespace is exactly four bytes**: space, TAB, LF, CR (§2, E404 §4). Form feed, vertical tab,
  NBSP (U+00A0), U+2028/2029, U+FEFF and every other Unicode space are errors outside strings (nst
  `n_structure_whitespace_formfeed`, `n_structure_whitespace_U+2060_word_joiner`). `ws` may be empty
  everywhere it appears; a document of only whitespace has no value and is an error.
- **Literals are lowercase and exact** (§3): `True`, `NULL`, `nul`, `nulll` are errors. Because the
  token must end where the grammar says, `[truefalse]` and `[true1]` are errors (no separator), while
  `[true,false]` is fine. A tokenizer that reads "an identifier" and compares it accepts nothing wrong
  but must report the right position.
- **Structural rules**: exactly one `,` between elements/members, no leading, trailing or doubled
  comma (`[1,]`, `[,1]`, `[1,,2]`, `{"a":1,}`); a member is `string : value` with exactly one colon;
  names must be strings (`{a:1}`, `{1:1}`, `{null:1}`, `{'a':1}` are errors). Empty containers `[]`,
  `{}` and the empty name `""` are fine.
- **Arrays** may mix types (§5). **Objects** are unordered collections (§1, §4) but member order is
  observable, and the RFC notes implementations differ in exposing it; preserving document order costs
  nothing and is required for a style-preserving round trip.
- `/` may be escaped (`\/`) but never needs to be; the writer should not escape it except as an
  opt-in for embedding in HTML `<script>` (`</` → `<\/`).

## 2. Encoding, BOM, size (§8.1, §9)

- **UTF-8 is mandatory for interchange** (§8.1: "JSON text exchanged between systems that are not part
  of a closed ecosystem MUST be encoded using UTF-8"). RFC 7159 still allowed UTF-16/UTF-32 (default
  UTF-8); RFC 4627 §3 described detecting them from the NUL-byte pattern of the first four bytes. ECMA-404
  defines JSON over code points and says nothing about bytes. **Recommend**: UTF-8 only. A UTF-16 or
  UTF-32 file (with or without BOM) is an error (`i_string_utf16LE_no_BOM`, `i_string_UTF-16LE_with_BOM`);
  callers that must read one transcode first. Report it as an encoding error, not a syntax error at
  byte 1 (a leading `FF FE`/`FE FF` or a NUL as the second byte is a cheap, specific diagnostic).
- **BOM**: generators "MUST NOT add a byte order mark" to networked JSON; parsers "MAY ignore" one rather
  than treating it as an error (§8.1). **Recommend**: skip exactly one leading `EF BB BF` by default
  (Windows editors write it into config files; `i_structure_UTF-8_BOM_empty_object` accepted), remember it
  in the style-preserving mode so the file round-trips, never emit it from the plain writer, and offer
  a strict option that rejects it. `EF BB BF` alone (no value), `EF BB` + `{}` (truncated BOM) and two BOMs
  are errors: a second U+FEFF is not whitespace.
- **Invalid UTF-8 anywhere is an error** (RFC 3629 §3; Unicode §3.9 conformance clause C10). The
  ill-formed sequences: bytes `C0`, `C1`, `F5`–`FF` anywhere; a continuation byte (`80`–`BF`) with no
  lead; a lead byte not followed by the right number of continuations (truncation, including at end of
  input); overlong forms (`E0 80`–`E0 9F ..`, `F0 80`–`F0 8F ..`); encoded surrogates `ED A0`–`ED BF ..`
  (U+D800–DFFF); anything above U+10FFFF (`F4 90`–`F4 BF ..`). Outside strings any non-ASCII byte is
  already a syntax error; inside strings it must be validated (section 5.3).
- Limits: "An implementation may set limits on the size of texts that it accepts", on "the maximum
  depth of nesting", on "the range and precision of numbers", and on "the length and character
  contents of strings" (§9). Every limit JsonBeef applies (section 13) is therefore conforming, as long
  as it is reported as a limit, not as a syntax error.

## 3. Objects: names, duplicates, order (§4, §8.3)

- **Duplicate names**: "The names within an object SHOULD be unique." When they are not, "the
  behavior of software that receives such an object is unpredictable. Many implementations report the
  last name/value pair only. Other implementations report an error or fail to parse the object, and
  some implementations report all of the name/value pairs, including duplicates" (§4). ECMA-404 §6
  imposes nothing. I-JSON §2.3 forbids them. A duplicate is decided **after unescaping**: `{"a":1,"a":2}`
  has a duplicate; NFC `"é"` and NFD `"é"` are different names (§8.3, I-JSON §2.3: "identical
  sequences of Unicode characters").
  - `{"a":1,"a":2}` is a `y_` case in the nst suite (`y_object_duplicated_key`), so the default must
    accept it. **Recommend** a `DuplicateNames` policy: `KeepAll` (default for the document: every member
    is kept in order, so the style-preserving mode and `Count` are faithful; name lookup returns the
    **last** one, matching JavaScript, Python, serde_json's `Value` and Go), `LastWins` (earlier
    duplicates dropped while parsing), `FirstWins`, and `Error` (I-JSON; reported at the second
    occurrence with its location). Typed mapping: a duplicate member for a field follows the same policy
    (serde_json reports "duplicate field" for structs; Go and System.Text.Json take the last).
  - Security: parsers that disagree (first vs last wins, or one that truncates a name at an invalid
    character) let an attacker show two programs different data (Bishop Fox, "An Exploration of JSON
    Interoperability Vulnerabilities", 2021). `Error` is the safe choice for signatures and
    authorization data; JCS §3.1 requires unique names.
  - Duplicate detection must not be quadratic: hash names (seeded, section 13) once an object passes a
    small member count, or check on lookup instead of on insert for `KeepAll`.
- **Comparison** is by code units/points after unescaping, no normalization, no case folding (§8.3);
  `"a\\b"` and `"a\b"` are equal. JsonBeef stores names as UTF-8, so byte comparison after
  unescaping is exactly code point comparison.
- The empty name `""` is a normal name (JSON Pointer `/` addresses it, section 11.1). `__proto__`,
  `constructor` and similar are ordinary names (jsonc-parser and JSON.parse go out of their way to keep
  `__proto__` an own property); nothing in a Beef document model is special about them.

## 4. Numbers: the rules (§6)

- Grammar: optional `-` (never `+`), then `0` or a nonzero digit followed by digits, then optional
  `.` + at least one digit, then optional `e`/`E` + optional sign + at least one digit. Errors: `+1`,
  `-`, `01`, `-01`, `00`, `.5`, `-.5`, `1.`, `1.e3`, `1e`, `1e+`, `1E-`, `0x1F`, `1_000`, `- 1`, `1.2.3`,
  `Infinity`, `-Infinity`, `NaN`, fullwidth or other Unicode digits (`１`, `٣`). Exponent digits may have
  leading zeros (`1e007` is `1e7`, `0.4e00669999...` is a valid number), and `-0`, `-0.0`, `0e5` are
  valid.
- "Numeric values that cannot be represented in the grammar below (such as Infinity and NaN) are not
  permitted" (§6, E404 §8). They are an extension (section 12.5).
- **Range and precision are implementation-defined** (§6, §9). The RFC's interoperability guidance:
  binary64 is "generally available and widely used"; `1E400` or `3.141592653589793238462643383279`
  "may indicate potential interoperability problems"; integers in `[-(2**53)+1, (2**53)-1]` are exactly
  interoperable. I-JSON §2.2 turns this into "SHOULD NOT include numbers that express greater magnitude
  or precision than an IEEE 754 double precision number provides" and RECOMMENDS strings for exact
  larger values ("An example would be 64-bit integers").
- What this means for a parser: every grammar-valid number must be **accepted by the syntax layer**
  (the nst `i_number_*` cases, section 9.6 for values), and conversion is where policy lives. Section 9
  has the conversion rules and the recommendations.

## 5. Strings (§7, §8.2)

### 5.1 Escapes

- Must be escaped: `"` (U+0022), `\` (U+005C) and **U+0000–U+001F** (all C0 controls, including TAB,
  LF, CR). A raw control character inside a string is an error (`n_string_unescaped_tab`,
  `n_string_unescaped_newline`, `n_string_unescaped_ctrl_char`). **U+007F (DEL), C1 controls
  (U+0080–009F), U+2028/U+2029, noncharacters (U+FFFE, U+FFFF, U+FDD0–FDEF) and unassigned code points
  are all legal raw** (`y_string_unescaped_char_delete`, `y_string_u+2028_line_sep`,
  `y_string_nonCharacterInUTF-8_U+FFFF`; E404 §9: "the JSON grammar permits code points for which
  Unicode does not currently provide character assignments").
- The escape set is exactly `\" \\ \/ \b \f \n \r \t \uXXXX` (§7). Errors: `\a`, `\v`, `\0`, `\x41`,
  `\'`, `\U0041`, `\u004` (fewer than 4 hex digits), `\u00G1`, `\` + raw TAB/LF, `\` + a non-ASCII
  byte, `\` at end of input. Hex digits are case-insensitive (`é` = `é`); the `u` is
  lowercase only.
- `\u0000` is legal and produces a NUL inside the string (`y_string_null_escape`,
  `y_object_escaped_null_in_key`). Beef `String`/`StringView` carry a length, so this is safe; any API that
  hands out a C string (`CStr()`) truncates there and must say so.
- A non-BMP character is escaped as a UTF-16 surrogate pair: `"𝄞"` is U+1D11E (§7). The pair
  must be adjacent escapes: high (`D800`–`DBFF`) immediately followed by `\u` + low (`DC00`–`DFFF`).
  The two halves may differ in hex case (`"𝄞"`, `y_string_surrogates_U+1D11E_MUSICAL_SYMBOL_G_CLEF`).
- ECMA-404 §9: "whether a processor of JSON texts interprets such a surrogate pair as a single code
  point or as an explicit surrogate pair is a semantic decision". For a UTF-8 library it is a single
  code point (4 UTF-8 bytes); anything else would not be valid UTF-8.

### 5.2 Unpaired surrogates (§8.2)

"The ABNF in this specification allows member names and string values to contain bit sequences that
cannot encode Unicode characters; for example, `"\uDEAD"`... The behavior of software that receives
JSON texts containing such values is unpredictable" (§8.2). The cases: a lone high (`"\uD800"`), a lone
low (`"\uDC00"`), a high followed by a non-low escape (`"\uD800A"`, `"\uD800\uD800"`), a high
followed by a non-escape (`"\uD800abc"`, `"\uD800\n"`), inverted (`"\uDD1E\uD834"`), and a high at the
end of the string. What implementations do:

| Behavior | Who |
|---|---|
| **Error** | serde_json (`"lone leading surrogate in hex escape"`), simdjson `get_string()` (default), RapidJSON, nlohmann/json, Perl JSON::XS, PHP `json_decode`, I-JSON §2.1, JCS §3.2.2.2 ("MUST cause a compliant JCS implementation to terminate with an appropriate error") |
| **Replace with U+FFFD** | Go `encoding/json` (documented: "invalid UTF-8 or invalid UTF-16 surrogate pairs are not treated as an error. Instead, they are replaced by the Unicode replacement character"), simdjson `get_string(true)` (`allow_replacement`) |
| **Keep the code unit** (UTF-16 runtimes) | JavaScript `JSON.parse`, Java (Jackson, Gson), .NET System.Text.Json (accepted in the nst results), Python (`str` holds lone surrogates) |
| **WTF-8** (encode the surrogate's code point as a 3-byte sequence `ED A0 80`...) | simdjson `get_wobbly_string()`, serde_json when deserializing into bytes (`ByteBuf`, `RawValue`); WTF-8 spec <https://simonsapin.github.io/wtf-8/> |

**Recommend**: error by default (JsonBeef strings are UTF-8 `String`s and a lone surrogate is not
representable in valid UTF-8; §9 allows limits on "character contents of strings"), with a
`InvalidSurrogates` option `Error | Replace | Wtf8`. `Replace` substitutes one U+FFFD per unpaired
escape; `Wtf8` stores `ED A0 80`-style bytes, and the writer turns them back into `\udXXX` escapes (as
ES2019's well-formed `JSON.stringify` does), so a WTF-8 document round-trips. Note that the nst
`i_string_*surrogate*` cases (9, plus `i_object_key_lone_2nd_surrogate`) all exercise this option.

### 5.3 Invalid UTF-8, normalization, validation speed

- Raw bytes in a string must be well-formed UTF-8 (section 2). Errors: `"\xFF"`, `"\xC0\xAF"`
  (overlong `/`), `"\xED\xA0\x80"` (encoded U+D800), `"\xF4\x90\x80\x80"` (U+110000),
  `"\xE2\x82"` (truncated), `"\x80"`, Latin-1 `"\xE9"`. The `i_string_*` UTF-8 cases are these.
- **Recommend**: reject by default (serde_json, simdjson, nlohmann and RapidJSON-with-validation agree;
  Go v1 and PHP's `JSON_INVALID_UTF8_SUBSTITUTE` replace). An opt-in `InvalidUtf8 = Replace` must follow
  Unicode §3.9 "U+FFFD Substitution of Maximal Subparts" (also the WHATWG Encoding Standard): one U+FFFD
  per maximal ill-formed subpart, so `ED A0 80` → three U+FFFD (ED is not a valid prefix of anything
  with A0), `E2 82` + `"` → one, `C0 AF` → two, `F4 90 80 80` → four.
- **No normalization** (§8.3, JCS §3.1, I-JSON §2.3): strings are passed through as code points.
  `object_key_nfc_nfd` in the nst transform tests checks this.
- Speed: validation is a hot path for string-heavy input. ASCII runs can be checked 8 bytes at a time
  (`(word & 0x8080808080808080) == 0`) together with the scan for `"`, `\` and controls (bytes < 0x20:
  `(word - 0x2020..20) & ~word & 0x8080..80` style tests). Full SIMD validation: Keiser and Lemire,
  "Validating UTF-8 In Less Than One Instruction Per Byte", Software: Practice and Experience 51(5),
  2021 (the lookup algorithm in simdjson and simdutf). A scalar DFA (Höhrmann) or the "range table"
  method is the portable fallback. Validate once, while copying/unescaping, not in a separate pass.

## 6. Parsers and generators (§9, §10)

- "A JSON parser MUST accept all texts that conform to the JSON grammar" and "MAY accept non-JSON forms
  or extensions" (§9). ECMA-404 §2 is stricter in tone: "A conforming processor of JSON texts should not
  accept any inputs that are not conforming JSON texts." **Recommend**: strict by default; every
  extension opt-in and named (section 12.6).
- "A JSON generator produces JSON text. The resulting text MUST strictly conform to the JSON grammar"
  (§10): a writer must not emit `NaN`, `Infinity`, comments, trailing commas, unescaped controls, or
  invalid UTF-8 in its default mode, whatever the document holds (section 14).
- §12: JSON is not quite a JavaScript subset (U+2028/2029 were illegal in JS string literals before
  ES2019's "JSON superset" change); never `eval` it.

## 7. ECMA-404 vs RFC 8259 (and the history)

The grammars are identical by agreement (§1.2; E404 §3). The differences are in what each says
beyond the grammar:

| Topic | RFC 8259 | ECMA-404 (2nd ed.) |
|---|---|---|
| Unit of definition | Octets in UTF-8 for interchange (§8.1) | Sequence of Unicode code points; no encoding |
| BOM | Generators MUST NOT add; parsers MAY ignore (§8.1) | Silent |
| Duplicate names | SHOULD be unique; behavior unpredictable (§4) | Not restricted; "semantic considerations" (§6) |
| Member order | Implementations differ (§4) | No significance (§6) |
| Number range/precision | binary64 interoperability guidance (§6) | Agnostic: "a sequence of digits" (Introduction) |
| Surrogate pairs | Unpaired ones make behavior unpredictable (§8.2) | Pair vs. code point is a "semantic decision" (§9) |
| Extensions | Parsers MAY accept non-JSON forms (§9) | Processors "should not accept" non-conforming input (§2) |
| Limits | Size, depth, number range/precision, string length/content (§9) | "may impose semantic restrictions" (§2) |

History that still shows up in the wild: RFC 4627 (2006) required an object or array at the top level
and allowed UTF-16/32 with autodetection (old JSON_checker `fail1.json` and `fail18.json` encode
4627-era assumptions: a top-level string and a depth limit of 20); ECMA-404 1st edition (2013) already
allowed any value; RFC 7159 (2014) aligned with it and still allowed UTF-16/32; RFC 8259 (2017)
mandated UTF-8 and made ECMA-404 normative.

## 8. I-JSON (RFC 7493)

An I-JSON message is a JSON text that additionally (§2):

- is UTF-8 (§2.1);
- contains no surrogate or **noncharacter** code points in names or strings, "both to characters
  encoded directly in UTF-8 and to those which are escaped" (§2.1). Noncharacters: U+FDD0–FDEF and the
  last two code points of every plane (U+FFFE, U+FFFF, U+1FFFE, ..., U+10FFFF). Note the nst suite has
  `y_` cases with noncharacters (`y_string_unicode_U+FFFE_nonchar`, `y_string_nonCharacterInUTF-8_U+10FFFF`,
  ...): an I-JSON check must be an option, never the default;
- SHOULD NOT have numbers beyond binary64 magnitude or precision; integers beyond ±(2^53−1) are not
  exact (§2.2);
- MUST NOT have duplicate names after unescaping (§2.3); member order carries no meaning.

§3 lets receivers reject non-I-JSON. §4 recommends objects at the top level, "Must-Ignore" for unknown
members (MUST NOT treat them as errors: the default for typed mapping), RFC 3339 timestamps with
uppercase `T`/`Z` and explicit offset, and base64url for binary. **Recommend**: an `IJson` validation
option (or a `Strict` preset) that rejects duplicates, surrogates, noncharacters and numbers that do not
fit a finite binary64; JCS mode implies it.

## 9. Numbers in depth

### 9.1 What must be exact

- **Decimal → binary64 must be correctly rounded** (round to nearest, ties to even, as IEEE 754
  §5.12.2 requires of conversions within the supported range). Anything less breaks round trips: a
  writer that prints the shortest digits that identify a double relies on the reader mapping those
  digits back to the same double. Truncating accumulation (`value = value*10 + digit` in double) or
  `mantissa * pow(10, exp)` is wrong by an ulp or more for many inputs.
- **Integers are not doubles**: values beyond 2^53 lose precision as doubles. A JSON library must keep
  `int64`/`uint64` exactly (IDs: Twitter's `id` vs `id_str`, database keys, nanosecond timestamps).
- **binary64 → decimal must round-trip and should be shortest**: print the fewest significant digits
  that read back to the same double; when several shortest candidates exist choose the closest, and
  on a tie the even one (ECMA-262 Note 2 to `Number::toString`, the rule JCS requires).

### 9.2 Integers: the boundaries

| Value | Text | Notes |
|---|---|---|
| 2^53 − 1 | `9007199254740991` | Largest I-JSON-interoperable integer (`Number.MAX_SAFE_INTEGER`) |
| 2^53 | `9007199254740992` | Exact as double; `9007199254740993` reads as double `9007199254740992` (tie, even) |
| 2^63 − 1 | `9223372036854775807` | `int64` max; as double it becomes 2^63 (`9223372036854775808`, printed `9223372036854776000` by ECMAScript) |
| −2^63 | `-9223372036854775808` | `int64` min: the magnitude does not fit `int64`, so accumulate in `uint64` and negate |
| 2^63 | `9223372036854775808` | Fits `uint64` only |
| 2^64 − 1 | `18446744073709551615` | `uint64` max |
| 2^64 | `18446744073709551616` | Beyond every native integer: double `1.8446744073709552e19` or exact text |

- 19 decimal digits always fit `uint64` (10^19 − 1 < 2^64); a 20-digit integer needs an overflow check
  on the last step. Count digits while scanning (TomlBeef's `TryParsePlainInteger` takes 1–18 digits
  for `int64` without any check).
- **Recommend**: the reader classifies each number token as *integer* (no `.`/exponent) or *float*;
  integers are stored as `int64` when they fit, else `uint64` when they fit, else as a big integer
  whose double approximation is available and whose **source text is kept** (simdjson reports
  `big_integer` with `raw_json_token()`, serde_json has `arbitrary_precision`, Python's `json` makes an
  arbitrary `int`, PHP has `JSON_BIGINT_AS_STRING`). `-0` is an integer token with value zero whose
  double value is `-0.0` (serde_json's `test_parse_negative_zero`): keep the sign bit so the writer
  can reproduce `-0`.
- Typed mapping (policy): an integer field should require an integer token by default (`1.0`, `1e2` are
  type errors in serde_json and Go; Jackson's default coerces and truncates), with range checks for
  narrower types (`300` into `uint8` → range error), and no string-to-number coercion unless asked.

### 9.3 Floats: the boundaries

| Input | Result (binary64 bits) | Why it matters |
|---|---|---|
| `0.1` | `3FB999999999999A` | Inexact; writes back as `0.1` |
| `1e23` | `44B52D02C7E14AF6` = 9.999999999999999e22 | Shortest form is `1e+23`; naive `1 * 10^23` in double gives the neighbor |
| `9007199254740993` (as double) | `4340000000000000` | Exact tie between 2^53 and 2^53+2 → even |
| `9007199254740993.000000000000000000001` | `4340000000000001` | Just above the tie: needs digits beyond the 19th |
| `1.00000000000000011102230246251565404236316680908203125` | `3FF0000000000000` | Exactly halfway between 1 and 1+2^-52 → even |
| same with last digit `6` | `3FF0000000000001` | One digit past the tie decides |
| `2.2250738585072011e-308` | `000FFFFFFFFFFFFF` | Largest subnormal |
| `2.2250738585072012e-308` | `0010000000000000` | Smallest normal; hung Java (CVE-2010-4476) and PHP on x87 (CVE-2010-4645) |
| `4.9406564584124654e-324`, `5e-324` | `0000000000000001` | Smallest subnormal |
| `2.4703282292062327e-324` | `0000000000000000` | Below half the smallest subnormal → +0 |
| `2.4703282292062328e-324` | `0000000000000001` | Above half → smallest subnormal |
| 2^-1075 written out exactly (752 significant digits) | `0000000000000000` | Exact tie → even (zero); adding a nonzero digit anywhere after it gives `...0001` |
| `1e-400`, `-1e-400` | `0000000000000000`, `8000000000000000` | Underflow to signed zero, not an error |
| `1.7976931348623157e308` | `7FEFFFFFFFFFFFFF` | Largest finite |
| `1.7976931348623158e308` | `7FEFFFFFFFFFFFFF` | Still below MAX + half ulp (1.797693134862315807937...e308) |
| `1.7976931348623159e308`, `1e309`, `1E400` | `7FF0000000000000` (+∞) | Overflow: IEEE rounding gives ±∞ (section 9.6 for policy) |
| `0e999999999999999999` | `0000000000000000` | A zero significand with a huge exponent is zero, not overflow (simdjson `pass27`) |
| `1e0000000000000000000000000000001` | `4024000000000000` (10) | Exponent with leading zeros; must not overflow the exponent accumulator |
| `123e-10000000`, `1e-2147483649` | `0000000000000000` | Exponent beyond `int32`: saturate while accumulating |
| `0.0000000000000000000000000000000000000000000000000123e50` | 1.23 | Leading zeros of the fraction do not count as significant digits |
| `3.5e-2147483647` | +0 | serde_json `test_parse_f64` |
| `2.638344616030823e-256` | `0ADFB11E2ADB03C3` | serde_json issue 536 regression |

- **Long mantissas**: up to **767 significant digits** can matter for the correctly rounded result
  (the exact decimal values of halfway points near the subnormal/normal boundary); fast_float keeps 768
  and folds the rest into a nonzero "sticky" flag. So an 800- or 10,000-digit mantissa needs bounded
  work: scan all digits (they must be validated anyway), but feed at most ~768 significant digits to
  the slow path. Leading zeros (`0.000...0001`) and trailing zeros (`1000...000e-500`) must be skipped
  when counting significant digits but still adjust the exponent.
- **Exponents**: accumulate with saturation (stop adding digits once the magnitude exceeds, say,
  100,000; any such exponent already means ±∞ or 0 unless the significand is zero). Never let
  `int32`/`int64` wrap (`1e-9223372036854775808`, fxx `more-test-cases.txt`).
- **float32**: parsing `float` fields via double then narrowing double-rounds: `7.038531e-26` is
  `0x15AE43FD` as float but `0x15AE43FE` via double (serde_json `test_roundtrip_f32`). Parse directly to
  `float` (corlib `Float.Parse` uses fast_float's `float` path) or accept a documented 1-ulp error. The
  fxx corpus has float32 bits for every line (test-suites.md section 3.1).

### 9.4 Decimal → binary64 algorithms

1. **Clinger's fast path** (W. D. Clinger, "How to Read Floating Point Numbers Accurately", PLDI 1990):
   if the decimal significand `w` ≤ 2^53 and the decimal exponent `q` is in [−22, 22], then `w` and
   `10^|q|` are exact doubles and one IEEE multiply or divide is correctly rounded. Extension: if `q` > 22
   but `w · 10^(q−22)` is still ≤ 2^53 (few digits, e.g. `1e30`), multiply the integer first. Requires
   real binary64 arithmetic (SSE2), not x87 extended precision, which double-rounds. TomlBeef already
   has this path: `TryParsePlainFloat` in TomlBeef's `src/TomlBeef/TomlParser.Values.bf`
   (≤ 19 digits, mantissa ≤ 2^53, exponent within ±22, else falls through), next to `TryParsePlainInteger`
   (1–18 digits into `int64`). Both port directly; JSON's grammar is simpler (no `_`, no `+`, no
   leading zeros) and the scanner already knows the token's digit count and exponent.
2. **Eisel–Lemire** (D. Lemire, "Number Parsing at a Gigabyte per Second", Software: Practice and
   Experience 51(8), 2021, arXiv:2101.11408; the idea is Michael Eisel's, 2020; Nigel Tao's write-up
   "The Eisel-Lemire ParseNumberF64 Algorithm", 2020): for `w` < 2^64 (≤ 19 digits) and `q` in
   [−342, 308], multiply the normalized `w` by a 128-bit truncated approximation of `5^q` from a table
   (~10 KB), take the top bits, and detect the rare ambiguous cases. N. Mushtak and D. Lemire, "Fast
   Number Parsing Without Fallback" (SPE 53(6), 2023) show the 128-bit product never needs a fallback
   for ≤ 19-digit inputs. `q` < −342 → ±0, `q` > 308 → ±∞ (for nonzero `w`). Used by Go (1.16+), Rust
   core (1.55+), C++ `from_chars` in libstdc++ (GCC 12+) via fast_float, simdjson, and the Beef
   runtime.
3. **More than 19 significant digits**: truncate to 19, run Eisel–Lemire on `w` and `w+1`; if both give
   the same double it is the answer (almost always). Otherwise a **slow path**: big-decimal
   ("Simple Decimal Conversion", Nigel Tao / Wuffs, the multiprecision-decimal method of Go's
   `strconv`) or a bignum comparison of the input against the halfway point between the two
   candidates (fast_float's "digit comparison", from Alex Huszagh's Rust `dec2flt` rewrite). Older
   references: David Gay, "Correctly Rounded Binary-Decimal and Decimal-Binary Conversions" (1990,
   `dtoa.c`, used by Python), Ryu-parse (`s2d` in ulfjack/ryu, limited to 17 digits). Implementation:
   <https://github.com/fastfloat/fast_float>.
4. **What the Beef runtime already provides**: `Double.Parse(StringView)` in corlib calls BeefRT's
   bundled **fast_float** (`BeefRT/rt/fast_float.h`, upstream Beef commit `90ccf552`, 2026-08-25;
   present in the released BeefBuild 0.43.6's `libBeefRT.a`): correctly rounded, overflow → ±∞ and
   underflow → ±0 count as success. Caveats: corlib's wrapper accepts `+`, `Infinity`/`NaN` (culture
   symbols, case-insensitive), leading `.` and other non-JSON forms, so JsonBeef must validate the JSON
   grammar itself and only hand over a validated token; it looks up `NumberFormatInfo.CurrentInfo` on
   every call; with `BF_RUNTIME_REDUCED` it falls back to C `strtod` (correctly rounded in glibc and
   musl and the current MSVC UCRT). **Recommend**: fast path in Beef (integers, Clinger), then corlib
   `Double.Parse` for the rest; port Eisel–Lemire only if profiling shows the call overhead matters on
   float-heavy input (`canada.json`: 111,080 floats).

### 9.5 Binary64 → decimal algorithms and output formats

- Algorithms, oldest first: Steele & White, "How to Print Floating-Point Numbers Accurately" (Dragon4,
  PLDI 1990, bignum); Gay's `dtoa` mode 0 (1990); Loitsch, "Printing Floating-Point Numbers Quickly and
  Accurately with Integers" (Grisu2/Grisu3, PLDI 2010; Grisu3 rejects ~0.5% of inputs and needs a
  fallback; V8 and double-conversion); Adams, "Ryū: Fast Float-to-String Conversion" (PLDI 2018) and
  "Ryū Revisited: printf Floating Point Conversion" (OOPSLA 2019); Giulietti, "The Schubfach way to
  render doubles" (2018–2021, in the JDK's `Double.toString` since Java 19); Jeon, Grisu-Exact (2020)
  and Dragonbox (2020, used by {fmt}); **zmij** (Victor Zverovich, 2025,
  <https://github.com/vitaut/zmij>), which the Beef runtime now bundles.
- **What the Beef runtime already provides**: `double.ToString(String)` (and the `"R"` format) calls
  zmij's shortest round-trip writer (`BeefRT/rt/zmij.c`). Its layout: fixed notation when the decimal
  exponent is in [−4, 15] (`0.0001`, `123.5`, `1e+16` starts scientific), otherwise `d[.ddd]e±XX` with
  a sign and at least two exponent digits (`1e-05`, `1.5e+300`), `-0` for negative zero, and `NaN`,
  `Infinity`, `-Infinity`. Every finite output is valid JSON number text (exponent leading zeros are
  allowed), but it is neither the ECMAScript nor the ryu/serde layout. **Recommend**: take the shortest
  digits and exponent from it and lay them out in JsonBeef's own format; check it against the RFC 8785
  number file (test-suites.md) before relying on it.
- **ECMAScript `Number::toString`** (ES2025 §6.1.6.1.20, ES2019 §7.1.12.1; what JCS §3.2.2.3 and
  `JSON.stringify` use). Let `n`, `k`, `s` be integers with `k` ≥ 1, 10^(k−1) ≤ `s` < 10^k, `s`·10^(n−k)
  = the value and `k` minimal (`s` = the shortest digits). Then:
  - `k` ≤ `n` ≤ 21: the `k` digits followed by `n−k` zeros (`1e20` → `100000000000000000000`);
  - 0 < `n` ≤ 21: the first `n` digits, `.`, the remaining `k−n` digits (`123.456`);
  - −6 < `n` ≤ 0: `0.`, `−n` zeros, the digits (`0.000001`);
  - otherwise, `k` = 1: the digit, `e`, `+` or `-`, `|n−1|` (`1e+21`, `1e-7`, `5e-324`);
  - otherwise: first digit, `.`, the other `k−1` digits, `e`, sign, `|n−1|` (`1.7976931348623157e+308`).
  - `-0` → `0`; NaN and ±∞ are not representable (`JSON.stringify` writes `null`, JCS requires an error).
- **The "ryu/serde" layout** (serde_json via the `ryu` crate, RapidJSON's `Writer`): integers-valued
  doubles keep `.0` (`0.0`, `-0.0`, `1.0`), exponent without `+` and without padding (`1e308`,
  `1.7976931348623157e308`, `5e-324`), fixed notation for decimal exponents roughly in [−5, 16). The
  nativejson-benchmark round-trip cases (`[0.0]`, `[-0.0]`, `[5e-324]`, `[1.7976931348623157e308]`)
  are written in this style, and a parse → write round trip reproduces them only if the writer keeps
  int/float distinction and this layout.
- **Recommend** for JsonBeef's writer: integers (int64/uint64/big) exactly as integers; doubles as the
  shortest round-trip digits, in a documented layout (ECMAScript is the most widely understood and is
  needed anyway for JCS; optionally keep a `.0` on integral doubles so a float stays a float through
  a round trip, as TomlBeef does); `-0.0` as `-0` (or `-0.0`), never `0`, outside JCS mode. The
  style-preserving mode writes unchanged numbers from their source text, so `1.0`, `1E2`, `-0`,
  `0.10` survive untouched.

### 9.6 The implementation-defined cases and a recommended stance

| Input class | serde_json | simdjson | Go | JS / Python | Recommend for JsonBeef |
|---|---|---|---|---|---|
| Integer > `uint64` (`100000000000000000000`) | f64 (or exact with `arbitrary_precision`) | error `BIGINT_ERROR` in DOM; raw token in On-Demand | float64 (or `json.Number`) | double / exact `int` | Accept; big integer with exact source text and a double approximation |
| Overflow (`1e400`, `-1e400`) | error "number out of range" | error | error at unmarshal | ±Infinity | Accept at parse; conversion to double reports `NumberOutOfRange` by default (option: return ±∞) |
| Underflow (`1e-400`) | ±0 | ±0 | ±0 | ±0 | ±0, no error |
| `-0` | −0.0 | −0.0 | −0.0 (float) / 0 (int) | −0 | Keep the sign; writes back `-0` |
| > 19 significant digits | correctly rounded | correctly rounded | correctly rounded | correctly rounded | Correctly rounded (bounded slow path) |

Reasoning for overflow: ±∞ is the correctly rounded IEEE result (fast_float, `strtod` and the fxx data
all agree), but a document holding ±∞ cannot be written back as JSON, and config values like `1e400` are
almost certainly mistakes. Reporting the range error at the conversion keeps the parse lossless (the
token is kept), lets `IJson`/strict modes reject at parse time, and leaves an explicit opt-in for
callers who want ±∞.

### 9.7 Number tokens in the document model

Keep the validated token span (offset + length, or the text in the style-preserving arena) and convert
lazily, or convert eagerly to a tagged `int64 | uint64 | double | big` and keep the span only when
asked. Lazy conversion is what On-Demand parsers do and makes skipped numbers free; eager conversion
makes repeated reads cheap. Either way a number is validated exactly once, during scanning.

## 10. RFC 8785: JSON Canonicalization Scheme

A deterministic serialization of I-JSON data for hashing and signing; also a good writer target and
test oracle.

- Input MUST be I-JSON (§3.1): no duplicate names, strings expressible as Unicode (lone surrogates are
  an error), numbers expressible as binary64. "Parsed JSON string data MUST NOT be altered during
  subsequent serializations" and no Unicode normalization.
- **No whitespace** between tokens (§3.2.1).
- **Literals** `null`, `true`, `false` (§3.2.2.1).
- **Strings** (§3.2.2.2, = ECMAScript `JSON.stringify`): U+0008, 0009, 000A, 000C, 000D as `\b \t \n \f
  \r`; other U+0000–001F as `\u00XX` with **lowercase** hex (`\u000f`); `"` and `\` as `\"` and `\\`;
  everything else literally, including `/`, DEL, U+2028/2029 and all non-ASCII. Lone surrogates: error.
- **Numbers** (§3.2.2.3): ECMAScript `Number::toString` of the binary64 value (section 9.5): `-0` → `0`,
  `4.50` → `4.5`, `2e-3` → `0.002`, `1E30` → `1e+30`, `0.000000000000000000000000001` → `1e-27`,
  `333333333.33333329` → `333333333.3333333`. NaN/∞: error. Big integers lose precision
  (`9223372036854775807` → `9223372036854776000`); Appendix D suggests strings for them.
- **Member order** (§3.2.3): sort recursively by the names' **UTF-16 code units** compared as unsigned
  integers (not UTF-8 bytes, not code points, no locale), shorter prefix first; array order unchanged.
  UTF-8 byte order differs from UTF-16 order only when a name contains a supplementary character
  (UTF-16 `D800`–`DFFF` sorts below `E000`–`FFFF`, UTF-8 `F0..` above `EE..`). The RFC's test: names
  `"€"`, `"\r"`, `"דּ"`, `"1"`, `"😀"`, `"\u0080"`, `"ö"` sort as `\r`, `1`,
  `\u0080`, `ö`, `€`, `😀`, `דּ`.
- Output is UTF-8 with no BOM and **no trailing newline** (§3.2.4; the `testdata/output` files end in `}`).
- Appendix B lists 26 number samples (24 finite values plus NaN and Infinity; most are in section 16);
  the full test vector is a
  100-million-line file (test-suites.md section 3.2).

## 11. JSON Pointer, Merge Patch, Patch

### 11.1 RFC 6901 JSON Pointer (the natural path syntax for on-demand access)

- Syntax (§3): `json-pointer = *( "/" reference-token )`; `~` is written `~0` and `/` is `~1`; any other
  `~` sequence is an error. `""` is the whole document; `"/"` is the member with the empty name.
- Evaluation (§4): decode each token by replacing `~1` with `/` **first** and then `~0` with `~` (so `~01`
  becomes `~1`, not `/`). On an object, select the member whose name equals the token code point by code
  point (no normalization); "if a referenced member name is not unique in an object, the member that is
  referenced is undefined, and evaluation fails". On an array the token must be `0` or a nonzero digit
  followed by digits (no leading zeros, no sign): `/01` is an error, `/1e0` is an error; `-` names the
  nonexistent element after the last (an error for reading; "append" for JSON Patch).
- A pointer written inside a JSON string is unescaped as a JSON string first (§5); in a URI fragment it
  is percent-encoded UTF-8 (§6: `#/c%25d`).
- Errors (§7) "include, but are not limited to" invalid syntax and nonexistent values; the application
  defines handling. **Recommend**: `Result` with distinct kinds (`InvalidPointer`, `NotFound`,
  `IndexOutOfRange`, `NotAContainer`, `DuplicateName`), and a `KeepAll` document resolving duplicates the
  same way name lookup does (last), documented as such.
- On-demand use: a pointer can drive a single forward pass over the text, skipping every value not on
  the path (skip strings by scanning for `"`/`\`; skip containers by bracket depth). Policy: whether a
  skipped value is fully validated. simdjson On-Demand validates only what it visits plus structure
  ("On-Demand JSON: A Better Way to Parse Documents?", Keiser and Lemire, SPE 2024); a strict mode must
  validate everything (UTF-8, number grammar, escapes) even in skipped subtrees, or document clearly
  that `Select("/a")` on `{"a":1,"b":[1,}` may succeed.

### 11.2 RFC 7396 JSON Merge Patch and RFC 6902 JSON Patch (scope notes)

- **Merge Patch**: a patch object is merged recursively; a member whose value is `null` deletes that
  member; a non-object patch replaces the target entirely; arrays are replaced, never merged; there is
  no way to set a value to `null`. Media type `application/merge-patch+json`. Simple to provide on the
  document model (and useful for layered config files).
- **JSON Patch**: an array of operations `add`, `remove`, `replace`, `move`, `copy`, `test`, each with a
  `path` (JSON Pointer), applied in order and atomically (all or nothing); `-` appends to arrays; `test`
  compares by JSON value equality (numbers by value, objects ignoring member order). Media type
  `application/json-patch+json`. Out of scope for the first version; the pointer API should not
  preclude it.

## 12. Extensions people expect from a config-file parser

### 12.1 JSONC (JSON with Comments): what jsonc-parser actually does

Microsoft's `jsonc-parser` (the parser behind VS Code's `settings.json`, `launch.json`, `tasks.json`,
`.code-workspace`, and the format `tsconfig.json`/`jsconfig.json` users know) is the reference; the
draft spec at <https://jsonc.org/> formalizes "what jsonc-parser considers valid while using its default
configurations". From `src/impl/scanner.ts` and `src/impl/parser.ts` at the pinned commit:

- **Comments**: `//` to the end of the line (stops before CR or LF; at end of input is fine) and `/* */`
  (may span lines, **does not nest**: `/* /* */ */` leaves ` */` as garbage). Allowed wherever
  whitespace is (between any two tokens, before the value, after it). An unterminated `/* ...` is an
  error (`UnexpectedEndOfComment`). `/` followed by anything else is an invalid symbol. `#` comments are
  not JSONC (Hjson/YAML only). Comments inside strings are text.
- **Options**: `disallowComments` (default false: comments are on), `allowTrailingComma` (default
  **false**), `allowEmptyContent` (default false: an empty or comment-only document is an error).
- **Trailing commas**: with `allowTrailingComma`, exactly one comma before `]` or `}` is accepted.
  `[1,,]`, `[,]`, `[,1]`, `{,}` are errors regardless. VS Code accepts trailing commas in its own
  settings files and TypeScript's own `tsconfig.json` parser accepts them, so users expect
  them in "JSONC"; the jsonc.org draft says parsers "MAY support trailing commas".
- **Whitespace**: space and TAB only, plus line breaks LF, CR and CRLF (a lone CR counts as a line
  break for line numbering). Form feed, VT, NBSP and U+FEFF are invalid symbols (the editor strips a BOM
  before parsing).
- **Strings and numbers are plain JSON**: the escape set is JSON's (`"\v"` is `InvalidEscapeCharacter`),
  a raw control character inside a string is `InvalidCharacter`, a raw LF/CR ends the string with
  `UnexpectedEndOfString`; numbers follow the JSON grammar (`01` scans as two numbers, `.5` and `-` are
  invalid symbols, `NaN`/`Infinity` are invalid symbols) and are converted with `Number()`. Lone
  surrogate escapes are accepted (JavaScript strings).
- **Error tolerance**: `parse()` never throws; it records `ParseError`s (with offset and length) and
  keeps building a best-effort value (`[ 1 2, 3 ]` → `[1, 2, 3]` plus a `CommaExpected` error). This is
  editor behavior; for JsonBeef it corresponds to an optional collect-errors mode (as XmlBeef has), not
  the default.
- **Editing**: `modify()` + `applyEdits()` and `format()` (tests in `src/test/edit.test.ts`, 20, and
  `format.test.ts`, 38) are the prior art for style-preserving edits: inserting a member computes the
  comma and indentation from the surroundings; removing the last member removes the preceding comma;
  comments stay attached to their lines.
- Media type `application/jsonc` and extension `.jsonc` (jsonc.org draft); a `.json` file can declare
  itself with a mode line `// -*- mode: jsonc -*-`.

### 12.2 JSON5 1.0.0 (spec.json5.org)

A superset of JSON "that aims to make it easier for humans to write and maintain by hand", adding
ECMAScript 5.1 productions (J5 §1.1). The grammar defers to ES5.1 for `IdentifierName`, `NumericLiteral`,
`EscapeSequence`, `LineTerminator` (J5 §9).

- **Objects** (J5 §3): keys may be an ES5.1 `IdentifierName` (start: `$`, `_`, Unicode letters
  Lu/Ll/Lt/Lm/Lo/Nl, or a `\uXXXX` escape of one; continue: also Mn/Mc/Nd/Pc, ZWNJ, ZWJ). Reserved words
  are fine (`{while: true}`), `{a-b: 1}` and `{10twenty: 1}` are errors. Keys may be single-quoted.
  One trailing comma allowed. Names "should be unique" (same wording as RFC 8259).
- **Arrays** (J5 §4): one trailing comma allowed; `[,]` and `[,null]` are errors.
- **Strings** (J5 §5): single or double quotes (the other quote is plain inside). Must be escaped: the
  delimiting quote, `\`, and line terminators (LF, CR); **other control characters, including TAB, may
  appear raw** (`JSON5DoubleStringCharacter :: SourceCharacter but not one of " or \ or LineTerminator`).
  U+2028/U+2029 are allowed raw, "parsers should produce a warning" and generators "should escape"
  them (J5 §5.2). Escapes (J5 §5.1, table 1): `\' \" \\ \b \f \n \r \t \v \0` (`\0` must not be followed by a
  decimal digit), `\xHH` (exactly two hex digits), `\uXXXX` (exactly four; pairs for non-BMP), a
  **line continuation** (`\` + LF, CR, CRLF, U+2028 or U+2029, which contribute nothing), and any other
  character after `\` stands for itself (`'\A\C\/\D\C'` is `AC/DC`) **except** `1`–`9`, which are
  errors (legacy octal).
- **Numbers** (J5 §6): an optional `+` or `-` before any numeric literal; decimal with optional leading
  or trailing point (`.5`, `5.`, `5.e4`) but **no leading zeros** (`010`, `00`, `080` are errors: ES5
  strict has no octal); hexadecimal `0x`/`0X` + hex digits (no fraction or exponent: `0xC8e4` is just
  hex 0xC8E4; `0x` alone is an error); `Infinity`, `-Infinity`, `+Infinity`, `NaN`, `+NaN`, `-NaN`.
  Hex literals are integers of any length (convert like a decimal integer: exact if they fit, else
  double); `-0x0` is negative zero.
- **Comments** (J5 §7): `//` to a `LineTerminator` (LF, CR, U+2028, U+2029) or end of input, `/* */` not
  nested; allowed before and after any token. A document of only comments is an error.
- **Whitespace** (J5 §8, table 3): TAB, LF, VT, FF, CR, space, NBSP, U+2028, U+2029, **U+FEFF**, and any
  other `Zs` character.
- Parsers "must accept all texts that conform to the JSON5 grammar" and "may accept non-JSON5 forms or
  extensions"; the same limits as RFC 8259 §9 (J5 §10). Generators must produce strict JSON5 (J5 §11).
- Test suite: json5/json5-tests (test-suites.md section 4.1).

### 12.3 JSON Lines / NDJSON

- **JSON Lines** (jsonlines.org): UTF-8; no BOM; each line is a valid JSON value ("a blank line is not");
  the line terminator is `\n` and `\r\n` works because trailing whitespace is ignored; a terminator after
  the last value is "strongly recommended but not required" and, if present, must be the last byte.
  Extension `.jsonl`; `application/jsonl` is not registered.
- **NDJSON 1.0.0**: each JSON text "MUST NOT contain newlines or carriage returns" and is followed by
  `\n`, optionally preceded by `\r`; parsers "MUST accept" `\n` and `\r\n`, "SHOULD raise an error" on an
  unparsable line, and "MAY silently ignore empty lines" (documented and configurable). Media type
  `application/x-ndjson`, extension `.ndjson`.
- Implementation: a line-oriented reader (find `\n` with a fast byte search, parse the slice as one
  document with the normal parser, report errors with the line number and the 1-based record index),
  plus a writer that writes compact JSON (no raw newlines can occur: LF in strings is always escaped)
  and `\n`. Options: skip blank lines, continue after a bad line (collect errors). Do not split inside
  strings: a raw LF cannot occur inside a valid JSON string, so splitting on LF first is safe.

### 12.4 RFC 7464 JSON text sequences and concatenated JSON

- `application/json-seq` (RS §2): each element is `RS` (0x1E) + JSON text + `LF`. Parsers split on RS
  (any octet string between RSes is "possible-JSON"; consecutive RSes are not empty elements), SHOULD
  continue after an element that fails to parse (RS §2.1, §2.3), and **MUST check that a top-level number,
  `true`, `false` or `null` is followed by whitespace**, dropping the element otherwise (it may have been
  truncated: `<RS>123<RS>` might have been `1234`, RS §2.4). UTF-8 only.
- Concatenated JSON (`{"a":1}{"a":2}`, `1 2`, the yajl `allow_multiple_values` mode, Jackson's
  `MappingIterator`, Go's `Decoder` loop): values separated by optional whitespace; numbers and literals
  need whitespace between them (`12` is one value). **Recommend**: one `JsonSequenceReader` with modes
  `Lines` (default), `Concatenated` and `RecordSeparated`, sharing the single-value parser.

### 12.5 Other non-standard things parsers accept

- `NaN`, `Infinity`, `-Infinity` tokens: Python's `json` accepts and **emits** them by default
  (`allow_nan=True`); Jackson `ALLOW_NON_NUMERIC_NUMBERS`; System.Text.Json
  `JsonNumberHandling.AllowNamedFloatingPointLiterals` (as strings `"NaN"`); RapidJSON
  `kParseNanAndInfFlag`; JSON5. Variants seen in the wild: `-NaN`, `+Infinity`, `inf`, `nan`, `Inf`
  (nst `n_number_+Inf`, `n_number_-NaN`). **Recommend** an `AllowNonFiniteNumbers` flag accepting exactly
  `NaN`, `Infinity`, `-Infinity` (Python's set; JSON5 mode adds `+Infinity`, `+NaN`, `-NaN`), and a
  writer option to emit them, else non-finite values are a write error (or `null`, as JavaScript and
  serde_json do, if the caller asks).
- Big numbers as strings: `"9223372036854775807"` for 64-bit IDs (I-JSON §2.2's recommendation;
  `JsonNumberHandling.AllowReadingFromString`, Jackson coercion). For typed mapping: an opt-in
  "number from string" attribute per field, never implicit.
- Others to recognize and reject with a good message (not implement): single-quoted strings, unquoted
  keys, `#` comments, hex/octal numbers, leading `+`, `undefined`, raw control characters in strings
  (Jackson `ALLOW_UNESCAPED_CONTROL_CHARS`), `\x` escapes, `\'`, top-level ellipsis, JavaScript
  `new Date(...)`. These are all JSON5 or JavaScript-isms; JSON5 mode covers the legitimate ones.

### 12.6 Which extensions to offer, and how

| Flag (opt-in unless noted) | Accepts | Presets |
|---|---|---|
| `Comments` | `//` and `/* */` where whitespace is allowed | JSONC, JSON5 |
| `TrailingCommas` | One comma before `]`/`}` | JSONC, JSON5 |
| `AllowBom` (**default on**) | One leading UTF-8 BOM | all |
| `AllowNonFiniteNumbers` | `NaN`, `Infinity`, `-Infinity` | Python-compatible, JSON5 |
| `Json5` | The whole JSON5 grammar (implies the rows above) | JSON5 |
| `InvalidUtf8 = Replace` | Ill-formed UTF-8 → U+FFFD (maximal subparts) | none |
| `InvalidSurrogates = Replace / Wtf8` | Lone `\uD800`... | none |
| `DuplicateNames = KeepAll (default) / LastWins / FirstWins / Error` | Policy, section 3 | `Error` in `Strict`/`IJson` |
| `IJson` | Rejects duplicates, surrogates, noncharacters, non-finite or non-binary64 numbers | JCS |
| Sequence reader mode | Lines / concatenated / RS-separated | separate API |

Presets: `Strict` (RFC 8259, BOM rejected, duplicates rejected), `Default` (RFC 8259 + BOM skipped,
duplicates kept), `Jsonc` (Default + comments + trailing commas: what users mean by "JSON with
comments"), `Json5`. Comments and trailing commas should be separately switchable because jsonc-parser's
own default is comments without trailing commas. The style-preserving mode must keep comments and the
trailing comma, and writing must refuse to emit them when the output mode is strict JSON (or strip them,
on request).

## 13. Security and robustness

| Threat | What goes wrong | Mitigation |
|---|---|---|
| Deep nesting | Recursive descent overflows the stack (`[` × 100,000 is 100 KB: nst `n_structure_100000_opening_arrays`, `n_structure_open_array_object` is 50,000 levels in 250 KB); recursive **destructors**, deep-equality, writers and visitors overflow too (nlohmann/json had to make its destructor iterative; Jackson CVE-2020-36518 in databind) | `MaxDepth` checked on every open; parser state in an explicit stack; DOM free, compare, copy and write iterative or bounded by `MaxDepth`. Report "nesting depth limit N exceeded" at the offending bracket, not EOF |
| Huge strings/documents | Memory exhaustion, `int32` length overflow | `MaxInputBytes`, `MaxStringBytes`, `MaxNameBytes`; 64-bit offsets internally |
| Memory amplification | `[[],[],...]` or `{"":0,...}`: one or two input bytes per node, but 32–64 bytes per DOM node | `MaxNodes` (or `MaxValues`), arena allocation |
| Many/duplicate names, hash flooding | Attacker-chosen names collide in an unseeded hash table → O(n²) inserts (28C3 "Efficient Denial of Service Attacks on Web Application Platforms", Klink and Wälde 2011; oCERT-2011-003; CVE-2011-4885 PHP); naive duplicate check is O(n²) by itself | Seeded hash (SipHash-style or per-process random seed), linear scan only below a small threshold, `MaxMembersPerObject` |
| Number DoS | Slow big-decimal paths on 1 MB mantissas; quadratic `int(str)` (Python CVE-2020-10735 → 4,300-digit default limit since 3.11); `BigDecimal("1e999999999")` blowups; x87 double-rounding infinite loop on `2.2250738585072012e-308` (Java CVE-2010-4476, PHP CVE-2010-4645) | Bound the slow path to ~768 significant digits + sticky; saturate exponents; `MaxNumberLength` (Jackson: 1,000 chars); never build an arbitrary-precision integer without a digit limit |
| Quadratic parsing | Re-scanning a token from its start after every buffer refill in streaming mode; repeated string concatenation; error recovery that rescans; pretty-printing deep nesting (output is O(depth²) by nature) | Incremental token state across refills; one copy per token; a streaming test with 1- and 16-byte buffers |
| Unicode confusion | Parsers disagree on invalid UTF-8 / lone surrogates (one drops, one replaces, one truncates the name) → key confusion | Strict defaults (sections 5.2, 5.3); replacement only on request |
| Integer precision | 64-bit IDs silently rounded through double | Exact int64/uint64 path (section 9.2) |

Default limits elsewhere (checked in source where marked ✓):

| Library | Max depth | Other defaults |
|---|---|---|
| serde_json | 128 ✓ (`recursion limit exceeded`; feature `unbounded_depth` + `disable_recursion_limit`) | Overflow `1e400` → error ✓; lone surrogate → error ✓ |
| simdjson | 1024 ✓ (`DEFAULT_MAX_DEPTH`) | Max document 4 GB ✓ (`SIMDJSON_MAXSIZE_BYTES`); duplicates kept, all reported |
| System.Text.Json | 64 ✓ (`JsonReaderOptions.DefaultMaxDepth`) | Comments disallowed, no trailing commas; `AllowDuplicateProperties` (.NET 10) default `true` ✓, `false` in the `Strict` preset ✓ |
| Jackson 2.x (`StreamReadConstraints`, 2.15+) | 1,000 ✓ | Number length 1,000 ✓, string length 20,000,000 ✓, name length 50,000 ✓, document length and token count unlimited ✓; `STRICT_DUPLICATE_DETECTION` off |
| Jackson 3.x | 500 ✓ | Number length 1,000 ✓, string length 100,000,000 ✓, name length 50,000 ✓ |
| Go `encoding/json` | 10,000 ✓ (`maxNestingDepth`, since Go 1.15) | Duplicates: last wins (struct fields matched case-insensitively); invalid UTF-8 and surrogates → U+FFFD. The experimental `encoding/json/v2` (Go 1.25, `GOEXPERIMENT=jsonv2`) rejects duplicate names and invalid UTF-8 by default |
| Python `json` | interpreter recursion limit (~1,000) → `RecursionError` | NaN/Infinity accepted and emitted by default; integers limited to 4,300 digits (3.11+) |
| Ruby `json` | 100 (`max_nesting`) | `allow_nan` false |
| PHP `json_decode` | 512 (`depth`) | `JSON_BIGINT_AS_STRING`, `JSON_INVALID_UTF8_SUBSTITUTE` opt-ins |
| JavaScript `JSON.parse` | none (engine stack, `RangeError`) | Duplicates: last wins; lone surrogates kept |
| RapidJSON | none by default (`kParseIterativeFlag` for constant stack) | UTF-8 validation off unless `kParseValidateEncodingFlag`; default number parsing is not always correctly rounded without `kParseFullPrecisionFlag` |

**Recommend** for JsonBeef: `MaxDepth = 1024` (deeper than the siblings' 256 because JSON data such as
GeoJSON, ASTs and serialized trees nests deeper than config files, and so that nst
`i_structure_500_nested_arrays` is accepted; safe only if parsing, freeing and writing are iterative),
`MaxInputBytes = 0` (unlimited; callers set it for untrusted input), `MaxStringBytes = 0`,
`MaxNumberLength` (e.g. 10,000 digits; the slow path is bounded anyway), `MaxNodes = 0`, all in one
config struct as in `XmlReadConfig`, plus an `Untrusted` preset with finite values for everything.

## 14. Writer rules

- Output must satisfy the grammar (§10): escape `"`, `\`, U+0000–001F (as `\b \t \n \f \r` or
  `\u00XX`); write everything else as UTF-8. Options: escape everything non-ASCII (`\uXXXX`, surrogate
  pairs above U+FFFF, ASCII-safe output), escape U+2028/2029 (safe to embed in pre-ES2019 JavaScript;
  JSON5 generators "should"), escape `</` as `<\/` (HTML `<script>`), escape `/` never by default.
- Strings that are not valid UTF-8 (a Beef `String` can hold any bytes): error by default; with WTF-8
  enabled, encoded surrogates are written as `\udXXX` (lowercase hex, as ES2019 `JSON.stringify` and
  JCS-style escaping).
- Non-finite doubles: error by default; options `WriteNull`, `WriteNonFiniteTokens` (`NaN`,
  `Infinity`, `-Infinity`; produces JSON5/Python-compatible output, not JSON).
- Numbers: section 9.5. Integers exact; doubles shortest round-trip; negative zero preserved outside JCS.
- Layout: compact, or pretty with configurable indent (spaces/tabs, width), newline (`\n`/`\r\n`),
  space after `:`, empty containers as `[]`/`{}`, and a final newline. Pretty output is O(depth²) in
  size for deep nesting.
- Never emit a BOM (§8.1) unless the style-preserving mode read one. No trailing commas or comments in
  strict output.
- JCS mode: section 10 (sorting, number layout, escapes, no whitespace, no trailing newline, I-JSON
  input check).

## 15. Style-preserving round trip: what must survive

For the `PreserveStyle`-like mode (TomlBeef `PreserveStyle`, XmlBeef full metadata), reading and
writing an unchanged document must reproduce it byte for byte. Things that carry style in JSON:

- Whitespace between every pair of tokens (indentation, spaces around `:` and `,`, blank lines), line
  endings (LF, CRLF, mixed), presence or absence of a final newline, a leading BOM.
- Comments and their attachment (JSONC/JSON5): own-line comments before a member, end-of-line comments
  after a value or comma, comments before the root and after it, comments inside empty containers.
- Trailing commas (JSONC/JSON5), and in JSON5: quote style of keys and strings, unquoted keys, hex/
  leading-point/`+` numbers, line continuations.
- Number text exactly as written (`1.0`, `1E2`, `1e+02`, `-0`, `0.10`, `1e400`, 30-digit integers).
- String escapes as written (`"é"` vs `"é"`, `"\/"`, `"\u000A"` vs `"\n"`, uppercase vs lowercase
  hex), for unchanged strings.
- Member order and duplicate members.
- Edits: changing a scalar rewrites only its token; inserting a member infers indentation and comma
  placement from its siblings (and the trailing-comma convention of the container); removing a member
  removes its comma (and its owned comments) without leaving `,,` or a stray trailing comma in strict
  JSON; changing a container's shape regenerates only that container.

## 16. Edge cases worth a test

"OK:" = accepted, with the result; "error:" = rejected, with the reason; "ext(X):" = the result with
extension X enabled (in strict mode the input is an error unless stated). `\t \n \r \f \v` are control
characters, `U+XXXX` a literal code point, `xx` (two hex digits) a raw byte, `[...]×N` repetition.
Numbers in results are binary64 bit patterns or exact integers as stated.

### Document level, whitespace, BOM

1. `` (empty) → error: no value (nst `n_structure_no_data`).
2. ` ` → error: no value (`n_single_space`).
3. `null` → OK: top-level null. `true`, `false`, `"a"`, `42`, `-0.1` likewise.
4. ` \t\r\n[1]\r\n\t ` → OK: all four whitespace characters around the value.
5. `\f[]` and `[\f]` → error: form feed is not whitespace (`n_structure_whitespace_formfeed`).
6. `[\v1]` → error: VT not whitespace.
7. `U+00A0[]` → error: NBSP (ext(Json5): OK).
8. `[U+2060]` → error: word joiner (`n_structure_whitespace_U+2060_word_joiner`).
9. `EF BB BF {}` → OK: empty object, BOM skipped (`i_structure_UTF-8_BOM_empty_object`); error with
   `AllowBom` off.
10. `EF BB BF` → error: no value (`n_structure_UTF8_BOM_no_data`).
11. `EF BB {}` → error: invalid UTF-8 / unexpected byte (`n_structure_incomplete_UTF8_BOM`).
12. `EF BB BF EF BB BF {}` → error: U+FEFF is not whitespace.
13. `FF FE 5B 00 5D 00` (UTF-16LE `[]` with BOM) → error: UTF-16 not supported (report as encoding).
14. `[1]x`, `{}}`, `[1]]` → error: content after the value.
15. `[][]`, `{} {}`, `1 2` → error: more than one value (ext(Concatenated): two values).
16. `123` + byte 00, `[1]` + byte 00 → error: NUL is not whitespace (`n_multidigit_number_then_00`).
17. `[`×1024 + `]`×1024 → OK at `MaxDepth = 1024`; `[`×1025 + `]`×1025 → error: depth limit, located at
    the 1025th `[`.
18. `[`×100000 → error: depth limit (not end of input, no crash) (`n_structure_100000_opening_arrays`).
19. `["a"` → error: unexpected end of input, at line 1 column 5.
20. `{"a":1` + `\n` → error: unexpected end of input in object.

### Literals

21. `nul`, `tru`, `fals` (`[nul]`) → error: incomplete literal.
22. `True`, `NULL`, `FALSE` → error: literals are lowercase.
23. `nulll`, `truex` → error: trailing characters.
24. `[truefalse]` → error: missing separator; `[true,false]` → OK.
25. `[true false]` → error: missing comma.

### Arrays and objects

26. `[1,]` → error: trailing comma (ext(TrailingCommas): `[1]`).
27. `[1,,]` → error, also with TrailingCommas.
28. `[,]`, `[,1]` → error, also with TrailingCommas.
29. `[1,,2]` → error: missing value.
30. `{"a":1,}` → error (ext(TrailingCommas): `{"a":1}`).
31. `{,}` → error in every mode.
32. `{"a" 1}`, `{"a"::1}`, `{"a",1}` → error: colon expected / unexpected.
33. `{a:1}` → error: names must be strings (ext(Json5): `{"a":1}`).
34. `{1:1}`, `{null:1}`, `{[]:1}` → error (in JSON5 too).
35. `{'a':1}` → error (ext(Json5): `{"a":1}`).
36. `{"a":1 "b":2}` → error: comma expected.
37. `{"":0}` → OK: the empty name.
38. `{"a":1,"a":2}` → OK: `KeepAll` keeps both in order, lookup `a` → 2; `DuplicateNames = Error` →
    error at the second `"a"` (line 1 column 8); `FirstWins` → 1.
39. `{"a":1,"a":2}` → duplicate after unescaping (same as 38).
40. `{"é":1,"é":2}` → OK: two different names (no normalization).
41. `{"__proto__":{"x":1}}` → OK: an ordinary member.
42. `[{"":[{"":[...]}]}]` 50,000 levels unclosed (`n_structure_open_array_object`) → error: depth limit.

### Number grammar

43. `-` → error: digit expected after minus.
44. `-0` → OK: integer zero with negative sign; as double `8000000000000000`; writes back as `-0`.
45. `-0.0`, `-0e5` → OK: double −0.0.
46. `00`, `01`, `-01` → error: leading zero.
47. `0.`, `1.`, `-2.` → error: digit expected after point (ext(Json5): `0`, `1`, `-2`).
48. `.5`, `-.5` → error (ext(Json5): 0.5, −0.5).
49. `1e`, `1e+`, `1E-`, `0.3e` → error: digit expected in exponent.
50. `1E+2`, `1e+02`, `1e2` → OK: 100 (double; `1e2` is a float token).
51. `+1` → error (ext(Json5): 1).
52. `0x1F` → error (ext(Json5): 31; `-0x1F` → −31; `0x` → error).
53. `1_000`, `1 000`, `1.2.3`, `1e2.3`, `- 1` → error.
54. `１` (U+FF11), `٣` (U+0663) → error: not ASCII digits.
55. `NaN`, `Infinity`, `-Infinity` → error (ext(AllowNonFiniteNumbers): NaN, +∞, −∞).
56. `-NaN`, `+Infinity`, `Inf`, `nan` → error (`-NaN` and `+Infinity` OK in Json5 only; `Inf`/`nan` never).
57. `1e0000000000000000000000000001` → OK: 10 (exponent with leading zeros).
58. `[0.4e00669999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999969999999006]`
    → OK syntax (`i_number_huge_exp`); as double +∞ → `NumberOutOfRange` by default.

### Number values

59. `9007199254740993` → OK: int64 9007199254740993 exactly; as double `4340000000000000`.
60. `9223372036854775807` → OK: int64 max.
61. `-9223372036854775808` → OK: int64 min.
62. `9223372036854775808` → OK: uint64 2^63; as double `43E0000000000000`.
63. `18446744073709551615` → OK: uint64 max.
64. `18446744073709551616` → OK: big integer, text kept, double `43F0000000000000` (simdjson DOM rejects).
65. `-9223372036854775809` → OK: big integer, double `C3E0000000000000`.
66. `-237462374673276894279832749832423479823246327846` → OK: big integer (`i_number_very_big_negative_int`).
67. `0.1` → `3FB999999999999A`.
68. `1e23` → `44B52D02C7E14AF6`; writes back `1e+23` (ECMAScript layout).
69. `9007199254740993.000000000000000000001` → `4340000000000001` (needs > 19 digits).
70. `1.00000000000000011102230246251565404236316680908203125` → `3FF0000000000000` (tie → even); with a
    final `6` instead of `5` → `3FF0000000000001`.
71. `2.2250738585072011e-308` → `000FFFFFFFFFFFFF`.
72. `2.2250738585072012e-308` → `0010000000000000` (and it must terminate quickly).
73. `4.9406564584124654e-324` → `0000000000000001`.
74. `2.4703282292062327e-324` → `0000000000000000`; `2.4703282292062328e-324` → `0000000000000001`.
75. 2^-1075 written out in full (`2.4703282292062327208828439643411068618252990130716238221279284125033775363510437593264991818081799618989828234772285886546332835517796989819938739800539093906315035659515570226392290858392449105184435931802849936536152500319370457678249219365623669863658480757001585769269903706311928279558551332927834338409351978015531246597263579574622766465272827220056374006485499977096599470454020828166226237857393450736339007967761930577506740176324673600968951340535537458516661134223766678604162159680461914467291840300530057530849048765391711386591646239524912623653881879636239373280423891018672348497668235089863388587925628302755995657524455507255189313690836254779186948667994968324049705821028513185451396213837722826145437693412532098591327667236328125e-324`)
    → `0000000000000000` (exact tie, even); the same with `1` appended to the mantissa → `0000000000000001`.
76. `1` followed by 800 `0`s then `e-800` → `3FF0000000000000` (1.0; long mantissa, bounded work).
77. `0.` + 10,000 `0`s + `1` → OK: ≈ 0 → `0000000000000000` (underflow; fast).
78. `1e-400` → +0; `-1e-400` → −0 (`8000000000000000`); no error.
79. `123.456e-789`, `123e-10000000` → +0 (`i_number_double_huge_neg_exp`, `i_number_real_underflow`).
80. `1.7976931348623157e308`, `1.7976931348623158e308` → `7FEFFFFFFFFFFFFF`.
81. `1.7976931348623159e308`, `1e309`, `1.5e+9999`, `-1e+9999`, `123123e100000` → OK syntax; double
    conversion overflows → `NumberOutOfRange` by default (±∞ with the opt-in).
82. `0e999999999999999999999` → +0, not overflow.
83. `1e-2147483649`, `1e-9223372036854775808` → +0 (exponent saturation, no wraparound).
84. `0.0000000000000000000000000000000000000000000000000123e50` → 1.23 (`3FF3AE147AE147AE`).
85. `123456789012345678901234567890` → big integer; double `45F8EE90FF6C373E` (1.2345678901234568e29).
86. `7.038531e-26` into a `float` field → `0x15AE43FD` (not `0x15AE43FE` via double).
87. `{"x":1.0}` into an `int` field → type error (number is not an integer) by default; `{"x":1e2}` same.
88. `{"x":300}` into `uint8` → range error; `{"x":-1}` into `uint32` → range error.
89. `{"x":"12"}` into `int` → type error unless the field opts into numbers-from-strings.

### String escapes

90. `"\"\\\/\b\f\n\r\t"` → OK: `"\/` + BS FF LF CR TAB (`y_string_allowed_escapes`).
91. `"Aéé"` → OK: `Aéé` (hex case-insensitive).
92. `"\U0041"`, `"\x41"`, `"\a"`, `"\'"`, `"\0"`, `"\v"` → error: invalid escape (ext(Json5): `\x41` →
    `A`, `\'` → `'`, `\0` → NUL, `\v` → VT, `\a` → `a`).
93. `"\u004"`, `"\u00G1"`, `"\u"` → error: four hex digits required.
94. `"\` (end of input), `"\"` → error: unterminated string.
95. `"\` + TAB + `"` → error (`n_string_escaped_ctrl_char_tab`).
96. `"\u0000"` → OK: a one-character string holding NUL; `{"a\u0000b":1}` → name of 3 bytes.
97. `"𝄞"`, `"𝄞"` → OK: U+1D11E, UTF-8 `F0 9D 84 9E`.
98. `"\uD834"` → error: unpaired high surrogate (ext(Replace): U+FFFD; ext(Wtf8): bytes `ED A0 B4`, written
    back as `"\ud834"`).
99. `"\uDD1E"` → error: unpaired low surrogate.
100. `"\uDD1E\uD834"` → error: inverted pair (`i_string_inverted_surrogates_U+1D11E`).
101. `"\uD800A"`, `"\uD800\uD800"`, `"\uD800abc"`, `"\uD800\n"` → error: high surrogate not
     followed by a low one.
102. `"\uD800𐀀"` → error by default (ext(Wtf8): `ED A0 80 F0 90 80 80`).
103. `"￿"`, `"﷐"`, `"􏿿"` → OK: noncharacters are legal JSON (`IJson`: error).
104. `"﻿"` → OK: ZWNBSP inside a string is ordinary text.

### Raw characters in strings

105. `"a` TAB `b"` → error: unescaped control character (ext(Json5): OK).
106. `"a` LF `b"`, `"a` CR `b"` → error (Json5 too, unless preceded by `\` as a line continuation).
107. `"` 7F `"` → OK: DEL is legal raw.
108. `"U+0080 U+009F"` → OK: C1 controls are legal raw.
109. `"U+2028U+2029"` → OK raw; the writer keeps them raw by default.
110. `"é"` (`C3 A9`) → OK.
111. `"` FF `"`, `"` 81 `"`, `"` E9 `"` → error: invalid UTF-8 (ext(Replace): one U+FFFD each).
112. `"` C0 AF `"` → error: overlong (ext(Replace): two U+FFFD).
113. `"` ED A0 80 `"` → error: encoded surrogate (ext(Replace): three U+FFFD).
114. `"` F4 90 80 80 `"` → error: above U+10FFFF (ext(Replace): four U+FFFD); `"` F4 8F BF BF `"` → OK:
     U+10FFFF.
115. `"` E2 82 `"` → error: truncated sequence (ext(Replace): one U+FFFD).
116. `[` E5 `]` → error: invalid UTF-8 outside a string (in every mode: replacement applies to string
     contents only).
117. `"` FC 80 80 80 80 80 `"` → error: 6-byte form (`i_string_overlong_sequence_6_bytes_null`).

### Error locations (1-based line and column in code points, plus byte offset)

118. `[1,\n 2,\n x]` → error at line 3 column 2 (byte offset 9): unexpected `x`.
119. `[1,\r\n x]` → error at line 2 column 2: CRLF counts as one line break.
120. `["é", x]` → error at line 1 column 7, byte offset 7 (`é` is one column, two bytes).
121. `{"a":tru}` → error at line 1 column 6: invalid literal (point at the token start).
122. `"abc` → error: unterminated string, reported at the opening quote (1:1) or at end of input (1:5):
     pick one and keep it consistent.

### JSONC (Comments, TrailingCommas)

123. `// c\n{}` → ext(Comments): OK `{}`.
124. `{} // c` (no final newline) → ext(Comments): OK.
125. `[1 /* x */, 2]` → ext(Comments): `[1,2]`.
126. `{"a":/*c*/"b"}` → error strict (`n_structure_object_with_comment`); ext(Comments): `{"a":"b"}`.
127. `/* /* */ */ 1` → error in every mode: comments do not nest.
128. `/* unterminated` + `1` → error: unterminated comment.
129. `{"a":"b"}/**/` → ext(Comments): OK; `{"a":"b"}/**//` → error (lone `/`); `{"a":"b"}/` → error.
130. `{"a":"// not a comment"}` → OK in every mode: string content.
131. `# c\n{}` → error in every mode (`#` comments are Hjson/YAML, not JSONC or JSON5).
132. `// only a comment` → error even with Comments: no value (jsonc-parser `allowEmptyContent` off).
133. `{"a":1,}` → ext(Comments only): error (jsonc-parser default); ext(Jsonc preset): OK.

### JSON5

134. `{while: true, $_a1: 1, ünï: 2}` → ext(Json5): OK (reserved word, `$`/`_`, Unicode letters).
135. `{a-b: 1}`, `{10twenty: 1}` → error in Json5 too.
136. `{sigΣma: 1}` → ext(Json5): name `sigΣma`.
137. `'I can\'t'`, `"a'b"` → ext(Json5): `I can't`, `a'b`.
138. `'line 1 \` LF `line 2'` → ext(Json5): `line 1 line 2` (also with CR, CRLF, U+2028).
139. `'\A\C\/\D\C'` → ext(Json5): `AC/DC`; `'\1'`, `'\01'` → error.
140. `0xC8`, `0XC8`, `-0xC8`, `+0xC8` → ext(Json5): 200, 200, −200, 200; `0xC8e4` → 51428.
141. `.5`, `5.`, `+.5`, `-.0`, `5.e4` → ext(Json5): 0.5, 5, 0.5, −0.0, 50000.
142. `010`, `00`, `-00`, `+0123`, `080` → error in Json5 too (no octal, no leading zeros).
143. `Infinity`, `+Infinity`, `-Infinity`, `NaN`, `+NaN`, `-NaN` → ext(Json5): OK.
144. `[\v\f U+00A0 U+FEFF 1]` → ext(Json5): `[1]` (extra whitespace).
145. `/* comment only */` → error in Json5 (no value).

### Sequences

146. `{"a":1}\n{"a":2}\n` → ext(Lines): two values.
147. `1\n\n2` → ext(Lines): error at line 2 (blank line) unless "skip empty lines" (NDJSON MAY).
148. `1 2\n` → ext(Lines): error, two values on one line.
149. `{"a":1}\r\n{"a":2}` → ext(Lines): two values (CRLF, no final newline).
150. `1E 31 0A 1E 32 0A` → ext(RecordSeparated): 1, 2.
151. `1E 31 32 33 1E 34 0A` → ext(RecordSeparated): first element dropped (top-level number not followed by
     whitespace may be truncated), then 4.
152. `1E 7B 22 61 22 3A 1E 32 0A` → ext(RecordSeparated): first element fails, parsing continues: 2.
153. `{}{}[]` → ext(Concatenated): three values; `12` → one value.

### Writer

154. Double +∞ → write error by default (`null` or `Infinity` only on request).
155. String with U+0000, U+001F, U+007F → `"\u0000\u001f` + raw DEL + `"`.
156. String with `"`, `\`, `/` → `"\"\\/"`.
157. Double 1e21 → `1e+21`; 1e20 → `100000000000000000000`; 1e-7 → `1e-7`; 0.000001 → `0.000001`;
     5e-324 → `5e-324`; 0.1+0.2 → `0.30000000000000004` (ECMAScript layout).
158. Double −0.0 → `-0` (JCS mode: `0`).
159. int64 9007199254740993 → `9007199254740993` (not through double).
160. JCS: `{"€":1,"\r":2,"דּ":3,"1":4,"😀":5,"\u0080":6,"ö":7}` → keys in the order
     `\r`, `1`, U+0080, `ö`, `€`, U+1F600, U+FB33 (RFC 8785 §3.2.3).
161. JCS: `[333333333.33333329,1E30,4.50,2e-3,0.000000000000000000000000001]` →
     `[333333333.3333333,1e+30,4.5,0.002,1e-27]`.
162. JCS number samples (RFC 8785 Appendix B, bits → text): `0000000000000000` → `0`, `8000000000000000` →
     `0`, `7FEFFFFFFFFFFFFF` → `1.7976931348623157e+308`, `4340000000000000` → `9007199254740992`,
     `4430000000000000` → `295147905179352830000`, `44B52D02C7E14AF5` → `9.999999999999997e+22`,
     `444B1AE4D6E2EF4F` → `999999999999999900000`, `3EB0C6F7A0B5ED8C` → `9.999999999999997e-7`,
     `41B3DE4355555554` → `333333333.33333325`, `BECBF647612F3696` → `-0.0000033333333333333333`,
     `43143FF3C1CB0959` → `1424953923781206.2` (exact value ends in `.25`: ties to even).

### JSON Pointer

163. On RFC 6901 §5's document: `""` → whole; `/foo/0` → `"bar"`; `/` → 0; `/a~1b` → 1; `/m~0n` → 8;
     `/ ` → 7; `/i\j` (the JSON string `"/i\\j"`) → 5.
164. `/~01` → member `~1` (decode `~1` before `~0`).
165. `/foo/01`, `/foo/-1`, `/foo/1e0` → error: invalid array index; `/foo/-` → error for reading (append
     position for patch); `/foo/2` → not found.
166. `foo` (no leading `/`), `/~2`, `/~` → error: invalid pointer syntax.
167. `/0` on `{"0":1}` → 1 (numeric token on an object is a member name).
