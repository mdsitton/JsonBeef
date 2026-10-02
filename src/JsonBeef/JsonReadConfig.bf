using System;

namespace JsonBeef;

/// @brief What a JsonDocument does with an object member whose name an earlier member of the same
/// object already has (compared after unescaping, byte for byte: no normalization).
public enum JsonDuplicateNames : uint8
{
	/// @brief Keep every member in document order; a lookup by name finds the last one (as JavaScript,
	/// Python and Go do).
	KeepAll,
	/// @brief Keep only the last member of each name, in its own position.
	LastWins,
	/// @brief Keep only the first member of each name.
	FirstWins,
	/// @brief Reject the document at the second occurrence (I-JSON, RFC 7493 §2.3).
	Error
}

/// @brief What the reader does with bytes inside a string or member name that are not well-formed UTF-8.
public enum JsonInvalidUtf8 : uint8
{
	/// @brief An InvalidUtf8 error (RFC 8259 §8.1: JSON text is UTF-8).
	Error,
	/// @brief One U+FFFD per maximal ill-formed subpart (Unicode §3.9, the WHATWG Encoding Standard):
	/// `C0 AF` is two, `ED A0 80` three, `E2 82` one. Outside strings ill-formed bytes stay errors.
	Replace
}

/// @brief What the reader does with a `\u` escape of a surrogate that is not half of a pair (`"\uD800"`).
public enum JsonInvalidSurrogates : uint8
{
	/// @brief An InvalidSurrogate error (a lone surrogate is not Unicode text).
	Error,
	/// @brief One U+FFFD per unpaired escape (Go's encoding/json).
	Replace,
	/// @brief The surrogate's code point encoded as three bytes (`ED A0 80` for U+D800: WTF-8, as
	/// JavaScript strings hold it). Such a String is not valid UTF-8; the writers turn it back into a
	/// `\udxxx` escape, so the text round-trips.
	Wtf8
}

/// @brief What a JsonDocument records about the source while reading.
public enum JsonMetadataMode : uint8
{
	/// @brief Nothing beyond the content.
	None,
	/// @brief Where each value and member name came from (`JsonNode.TryGetSourceRange`,
	/// `TryGetNameRange`), for diagnostics such as "port at config.json:12:5".
	Positions,
	/// @brief Positions, plus the source text around and of every value (whitespace, comments, the
	/// commas, numbers and strings as written), so `JsonDocument.Write(output)` gives the document back
	/// as it was read, byte for byte, and regenerates only what was changed: for configuration files
	/// edited by programs (with JsonReadConfig.Jsonc, comments and trailing commas survive).
	PreserveStyle
}

/// @brief Settings for reading JSON: the dialect, the source name for errors, and resource limits for
/// untrusted input. The defaults read RFC 8259 JSON exactly (with a leading byte order mark skipped)
/// and limit only the nesting depth.
public struct JsonReadConfig
{
	/// @brief Name of the input for error messages and source ranges, typically its file path. Only
	/// viewed: it must outlive the read (JsonDocument keeps a copy).
	public StringView SourceName = default;
	/// @brief What a JsonDocument records about the source.
	public JsonMetadataMode MetadataMode = .None;

	/// @brief Report every error instead of stopping at the first (for editors and linters): after a
	/// syntax error the reader resynchronizes (a missing comma or colon is assumed, a broken value or
	/// member is skipped to the next `,` or closing bracket, a stray closing bracket closes the
	/// containers down to its own, the end of the input closes every open container) and goes on.
	/// JsonReader.Next returns each error once and continues on the next call; a JsonDocument keeps
	/// what it could read and lists the errors in `Errors`. Encoding (UTF-16/32), I/O and resource-limit
	/// errors still stop the read, as does MaxErrors.
	public bool CollectErrors = false;
	/// @brief With CollectErrors: stop after this many errors. 0 = no limit.
	public int MaxErrors = 100;

	/// @brief Skip one leading UTF-8 byte order mark (RFC 8259 §8.1 lets parsers ignore it). Off: a BOM
	/// is an error.
	public bool AllowBom = true;
	/// @brief JSONC: `//` line comments and `/* */` block comments (not nested) wherever whitespace may
	/// be, as VS Code's jsonc-parser reads them. A document of only comments is still an error.
	public bool Comments = false;
	/// @brief JSONC: one comma after the last element of an array or member of an object (`[1,]`,
	/// `{"a":1,}`). `[,]`, `[1,,]` and `{,}` stay errors.
	public bool TrailingCommas = false;
	/// @brief The number tokens `NaN`, `Infinity` and `-Infinity` (Python's json writes them by default;
	/// JSON5 has them). They are numbers of kind NonFinite whose doubles are NaN and ±∞; writers still
	/// refuse to write them unless JsonWriteOptions.NonFiniteNumbers says otherwise.
	public bool AllowNonFiniteNumbers = false;
	/// @brief Ill-formed UTF-8 inside strings and names: an error (the default) or U+FFFD.
	public JsonInvalidUtf8 InvalidUtf8 = .Error;
	/// @brief Unpaired surrogate escapes: an error (the default), U+FFFD, or WTF-8 bytes.
	public JsonInvalidSurrogates InvalidSurrogates = .Error;
	/// @brief Accept only I-JSON (RFC 7493): on top of RFC 8259, noncharacters in strings and names
	/// (raw or escaped) are errors (`Noncharacter`), so are numbers beyond a finite double
	/// (`NumberOutOfRange`: `1e400`), and a JsonDocument rejects duplicate member names whatever
	/// DuplicateNames says (JsonReader reports every member, as always). Overrides AllowNonFiniteNumbers,
	/// InvalidUtf8 and InvalidSurrogates: those stay errors.
	public bool IJson = false;
	/// @brief JsonDocument: what to do with duplicate member names. JsonReader reports every member.
	public JsonDuplicateNames DuplicateNames = .KeepAll;

	/// @brief Maximum nesting depth of arrays and objects: 1 allows `[1]` but not `[[1]]`. 0 =
	/// unlimited (the reader is iterative: depth costs one bit per level).
	public int MaxDepth = 1024;
	/// @brief Maximum input size in bytes. 0 = unlimited.
	public int MaxInputBytes = 0;
	/// @brief Maximum length in bytes of a string or member name after unescaping. 0 = unlimited.
	public int MaxStringBytes = 0;
	/// @brief Maximum length in bytes of a number token. 0 = unlimited (conversions are bounded anyway).
	public int MaxNumberLength = 0;
	/// @brief JsonDocument: maximum number of values (every array, object, string, number and literal).
	/// 0 = unlimited. Bounds memory: `[[],[],…]` costs a 40-byte record per two input bytes.
	public int MaxNodes = 0;
	/// @brief JsonDocument: maximum number of members in one object (duplicates included). 0 = unlimited.
	public int MaxMembers = 0;

	/// @brief Buffer size in bytes for reading a Stream. 0 = default (64 KiB); values below 16 are raised
	/// to 16 (`JsonTester -stream 1` reads through the smallest buffer).
	public int StreamBufferBytes = 0;
	/// @brief Streams only: the most bytes the reader may hold at once for one token (a string, number
	/// or literal), counted from its start through the byte after it. Longer tokens fail with
	/// ResourceLimitExceeded whatever the buffer size. 0 = unlimited (bounded by MaxInputBytes and
	/// MaxStringBytes).
	public int MaxTokenBytes = 0;

	/// @brief The defaults: RFC 8259, a leading BOM skipped, MaxDepth 1024.
	public static Self Default => .();

	/// @brief JSON with comments as configuration files mean it (VS Code's settings, tsconfig.json):
	/// comments and trailing commas.
	public static Self Jsonc
	{
		get
		{
			Self config = .();
			config.Comments = true;
			config.TrailingCommas = true;
			return config;
		}
	}

	/// @brief RFC 8259 with nothing extra: a byte order mark and duplicate member names are errors.
	public static Self Strict
	{
		get
		{
			Self config = .();
			config.AllowBom = false;
			config.DuplicateNames = .Error;
			return config;
		}
	}

	/// @brief Finite limits for input from untrusted sources: depth 128, 64 MiB of input, 16 MiB strings,
	/// 4,096-byte numbers, 8 million values, 1 million members per object, 16 MiB stream tokens, and
	/// duplicate names rejected (RFC 7493, I-JSON: parsers that disagree on duplicates let one document
	/// mean two things).
	public static Self Untrusted
	{
		get
		{
			Self config = .();
			config.MaxDepth = 128;
			config.MaxInputBytes = 64 * 1024 * 1024;
			config.MaxStringBytes = 16 * 1024 * 1024;
			config.MaxNumberLength = 4096;
			config.MaxNodes = 8 * 1024 * 1024;
			config.MaxMembers = 1024 * 1024;
			config.MaxTokenBytes = 16 * 1024 * 1024 + 1024;
			config.DuplicateNames = .Error;
			return config;
		}
	}
}
