using System;
using FormatCore;
using internal FormatCore;
using internal JsonBeef;

namespace JsonBeef;

/// @brief Categories of errors that can occur when reading or converting JSON.
public enum JsonErrorKind : uint8
{
	// Encoding
	/// @brief Bytes that are not well-formed UTF-8.
	InvalidUtf8,
	/// @brief The input is UTF-16 or UTF-32: JSON must be UTF-8 (RFC 8259 §8.1).
	UnsupportedEncoding,

	// Lexical
	/// @brief A character that cannot appear where it is (outside strings).
	UnexpectedChar,
	/// @brief The input ended inside a value, or before the document's value.
	UnexpectedEndOfInput,
	/// @brief A misspelled or truncated `true`, `false` or `null`.
	InvalidLiteral,
	/// @brief Text that starts like a number but does not follow the JSON number grammar.
	InvalidNumber,
	/// @brief A string without its closing quote.
	UnterminatedString,
	/// @brief An unknown escape, or `\u` without four hex digits.
	InvalidEscape,
	/// @brief A `\u` escape of a surrogate that is not part of a high-low pair.
	InvalidSurrogate,
	/// @brief A control character (U+0000-U+001F) written raw inside a string.
	ControlCharacterInString,
	/// @brief A `/*` comment without its `*/` (JsonReadConfig.Comments).
	UnterminatedComment,

	// Structure
	/// @brief A `,`, `:`, `]` or `}` missing, doubled or misplaced, or anything after the document's value.
	InvalidStructure,
	/// @brief A member name an earlier member of the object already has (JsonDuplicateNames.Error).
	DuplicateName,
	/// @brief A noncharacter (U+FDD0-U+FDEF, U+FFFE, U+FFFF and the last two code points of every
	/// plane) in a string or name: legal JSON, but not I-JSON (JsonReadConfig.IJson, RFC 7493 §2.1).
	Noncharacter,

	// Values
	/// @brief A number whose value does not fit the requested type (a double beyond ±1.8e308, an
	/// integer beyond the type's range).
	NumberOutOfRange,

	// Typed binding ([JsonObject])
	/// @brief A value of another kind than the field needs (a string for an integer, `null` for a
	/// field that cannot be null, a fraction for an integer).
	TypeMismatch,
	/// @brief A [JsonRequired] member is absent.
	MissingValue,
	/// @brief A value of the right kind that the field cannot take: an unknown enum case or
	/// discriminator, a converter's rejection.
	InvalidValue,
	/// @brief A member no field maps, in a [JsonObject(Strict = true)] type.
	UnknownMember,

	// Limits
	/// @brief A resource limit of JsonReadConfig was exceeded.
	ResourceLimitExceeded,

	// File I/O
	/// @brief Reading the input failed.
	IoError
}

/// @brief A read error with its location.
///
/// The error owns nothing and needs no cleanup, so it can be dropped freely (including by `Try!`).
/// `mMessage` views a per-thread buffer: it stays valid until the next JsonParseError is created on the
/// same thread, which in practice means the next failing JsonBeef call. Copy it to keep it longer.
public struct JsonParseError
{
	/// Per-thread message and source-name storage, freed when the thread exits.
	static LazyTLS<String> sMessageBuffer = new .() ~ delete _;
	static LazyTLS<String> sSourceBuffer = new .() ~ delete _;
	static LazyTLS<String> sPathBuffer = new .() ~ delete _;

	public JsonErrorKind mKind;
	/// @brief Human-readable description. Valid until the next error on this thread.
	public StringView mMessage;
	/// @brief Name of the input the position refers to; empty if unnamed. Valid until the next error
	/// on this thread.
	public StringView mSource;
	/// @brief Typed binding: the JSON Pointer (RFC 6901) of the value the error is in, from the bound
	/// object (`/statuses/3/user/id`); empty for the object itself and outside binding. Valid until the
	/// next error on this thread.
	public StringView mPath;
	/// @brief 1-based line (0 when there is no position).
	public int32 mLine;
	/// @brief 1-based column, in code points.
	public int32 mColumn;
	/// @brief Byte offset into the input.
	public int64 mOffset;
	/// @brief Length of the erroneous span in bytes.
	public int32 mLength;

	/// @brief Creates a new error at the given location.
	/// @param kind The category of error.
	/// @param message Human-readable description.
	/// @param line 1-based line number (0: no position).
	/// @param column 1-based column number, in code points.
	/// @param offset Byte offset into the input.
	/// @param length Length of the erroneous span in bytes.
	public this(JsonErrorKind kind, StringView message, int line, int column, int offset, int length = 1)
	{
		mKind = kind;
		mLine = (int32)line;
		mColumn = (int32)column;
		mOffset = offset;
		mLength = (int32)length;
		mMessage = Store(sMessageBuffer.Value, message);
		mSource = default;
		mPath = default;
	}

	/// Prepends a reference token to mPath (`/name`, escaped, or `/index`): binding builds the path as
	/// the error leaves each level.
	internal void PrependPath(StringView token, bool escape = true) mut
	{
		let buffer = sPathBuffer.Value;
		let prefix = scope String(token.Length + 2);
		prefix.Append('/');
		if (escape)
			JsonPointer.AppendToken(prefix, token);
		else
			prefix.Append(token);
		if (mPath.IsEmpty)
			buffer.Set(prefix);
		else
		{
			// mPath views the buffer (an error's path is only ever built here)
			buffer.Insert(0, prefix);
		}
		mPath = buffer;
	}

	/// An error at byte `offset` of `input`, with the line and column computed from it.
	internal static JsonParseError At(JsonErrorKind kind, StringView message, StringView input, int offset, int length = 1)
	{
		Utf8.LineAndColumn<JsonText>(input, offset, let line, let column);
		return JsonParseError(kind, message, line, column, offset, length);
	}

	/// Copies `text` into a per-thread buffer and returns a view of it.
	static StringView Store(String buffer, StringView text)
	{
		// The text may itself be a view of the buffer (an error rebuilt from a previous one)
		char8* start = buffer.Ptr;
		if (text.Ptr >= start && text.Ptr < start + buffer.Length)
		{
			let copy = scope String(text);
			buffer.Set(copy);
		}
		else
			buffer.Set(text);
		return buffer;
	}

	/// @brief Set the source name the position refers to. Stored like the message: valid until the next
	/// error on this thread.
	/// @param source The source name, e.g. a file path.
	public void SetSource(StringView source) mut
	{
		mSource = Store(sSourceBuffer.Value, source);
	}

	/// @brief Formats the error as `source:line:column: path: message`, dropping the parts that are
	/// unknown (no source name, no position: line 0, no path).
	/// @param strBuffer The string to append to.
	public override void ToString(String strBuffer)
	{
		if (!mSource.IsEmpty)
		{
			strBuffer.Append(mSource);
			strBuffer.Append(':');
		}
		if (mLine > 0)
			strBuffer.AppendF("{}:{}:", mLine, mColumn);
		if (!mSource.IsEmpty || mLine > 0)
			strBuffer.Append(' ');
		if (!mPath.IsEmpty)
		{
			strBuffer.Append(mPath);
			strBuffer.Append(": ");
		}
		strBuffer.Append(mMessage);
	}
}
