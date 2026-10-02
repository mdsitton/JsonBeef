using System;
using System.IO;
using internal JsonBeef;

namespace JsonBeef;

/// @brief What JsonReader.Next reached.
public enum JsonToken : uint8
{
	/// @brief No token yet (before the first Next).
	None,
	/// @brief `{`: its members follow (PropertyName, then the value's tokens), then EndObject.
	StartObject,
	/// @brief `}`.
	EndObject,
	/// @brief `[`: its elements' tokens follow, then EndArray.
	StartArray,
	/// @brief `]`.
	EndArray,
	/// @brief A member's name: `StringValue` is the decoded name. The member's value follows.
	PropertyName,
	/// @brief A string value: `StringValue` is the decoded text.
	String,
	/// @brief A number: `NumberKind`, `RawValue` (its text) and the `TryGet…` conversions.
	Number,
	/// @brief `true`.
	True,
	/// @brief `false`.
	False,
	/// @brief `null`.
	Null,
	/// @brief The end of the document: its value was read and only whitespace followed. Further calls
	/// return it again.
	EndOfDocument
}

/// @brief A pull reader over one JSON text (RFC 8259): each call to `Next` reads the next token. It
/// builds no document and allocates nothing per token; the token's strings (`StringValue`, `RawValue`)
/// are views into the input or into the reader's buffer, valid until the next call to `Next` or `Reset`.
///
/// The input is UTF-8 text in memory, or a Stream read through a buffer (memory stays bounded by the
/// buffer and the longest token). Everything is validated as it is read: UTF-8, the grammar, escapes,
/// surrogate pairs, number syntax; nesting is limited by `JsonReadConfig.MaxDepth` and costs no stack.
/// The first error ends the read: `Next` returns it again on every later call. An in-memory input is
/// checked for encoding errors before the first token; a stream as it is read (a document that fits
/// its first buffer reports the same first error as from memory).
///
/// ```
/// let reader = scope JsonReader(text);
/// while (true)
/// {
///     switch (Try!(reader.Next()))
///     {
///     case .PropertyName: Console.WriteLine(reader.StringValue);
///     case .EndOfDocument: return .Ok;
///     default:
///     }
/// }
/// ```
public class JsonReader
{
	internal JsonReaderCore<JsonByteCursor> mBytes ~ delete _;
	internal JsonReaderCore<JsonBufferedStreamCursor> mStream ~ delete _;
	JsonStreamState mStreamState ~ delete _;
	internal bool mStreaming;

	/// @brief Create a reader with no input; call Reset before reading.
	public this()
	{
		mBytes = new .();
	}

	/// @brief Create a reader over `input`, which must outlive the reader's use of it.
	/// @param input The document text (UTF-8; a leading BOM is skipped).
	public this(StringView input) : this()
	{
		Reset(input);
	}

	/// @brief Create a reader over `input` with a config.
	/// @param input The document text (UTF-8).
	/// @param config The dialect, limits and source name.
	public this(StringView input, JsonReadConfig config) : this()
	{
		Reset(input, config);
	}

	/// @brief Start reading `input` from the beginning with the default config, reusing the reader's
	/// buffers.
	/// @param input The document text (UTF-8; a leading BOM is skipped).
	public void Reset(StringView input)
	{
		Reset(input, .());
	}

	/// @brief Start reading `input` from the beginning, reusing the reader's buffers.
	/// @param input The document text (UTF-8).
	/// @param config The dialect, limits and source name (only viewed: it must outlive the read).
	public void Reset(StringView input, JsonReadConfig config)
	{
		mStreaming = false;
		mBytes.Reset(JsonByteCursor(input, config), config);
	}

	/// @brief Start reading a stream with the default config.
	/// @param stream The document (UTF-8); read from its current position, and must outlive the
	/// reader's use of it.
	public void Reset(Stream stream)
	{
		Reset(stream, .());
	}

	/// @brief Start reading a stream through a buffer of `config.StreamBufferBytes` (see also
	/// `config.MaxTokenBytes`).
	/// @param stream The document (UTF-8); read from its current position, and must outlive the
	/// reader's use of it.
	/// @param config The dialect, limits, buffer size and source name.
	public void Reset(Stream stream, JsonReadConfig config)
	{
		mStreaming = true;
		if (mStream == null)
		{
			mStream = new .();
			mStreamState = new .();
		}
		mStream.Reset(JsonBufferedStreamCursor(stream, mStreamState, config), config);
	}

	/// @brief Read the next token.
	/// @return The token, or the read's error (see IsStopped).
	[Inline]
	public Result<JsonToken, JsonParseError> Next()
	{
		if (!mStreaming)
		{
			if (mBytes.NextToken() case .Ok(let token))
				return .Ok(token);
			return .Err(mBytes.mError);
		}
		if (mStream.NextToken() case .Ok(let token))
			return .Ok(token);
		return .Err(mStream.mError);
	}

	/// @brief The last token Next returned.
	public JsonToken TokenType => mStreaming ? mStream.mToken : mBytes.mToken;

	/// @brief The token's depth: the number of containers around it (0 for the document's value and its
	/// StartObject/EndObject or StartArray/EndArray, 1 for the members or elements inside it).
	public int Depth => mStreaming ? mStream.mTokenDepth : mBytes.mTokenDepth;

	/// @brief The number of containers open after the token (StartArray opens one, EndArray closes it).
	public int CurrentDepth => mStreaming ? mStream.CurrentDepth : mBytes.CurrentDepth;

	/// @brief Byte offset into the input where the token starts (a string's opening quote).
	public int Offset => mStreaming ? mStream.mTokenStart : mBytes.mTokenStart;

	/// @brief Byte offset just past the token (after a string's closing quote).
	public int EndOffset => mStreaming ? mStream.mTokenEnd : mBytes.mTokenEnd;

	/// @brief String, PropertyName: the decoded text (it may hold U+0000). Number, True, False, Null:
	/// the token's text.
	public StringView StringValue => mStreaming ? mStream.mValue : mBytes.mValue;

	/// @brief String, PropertyName: the text between the quotes with escapes as written. Number: its
	/// text exactly as written (`1.50e+03`). True, False, Null: the literal.
	public StringView RawValue => mStreaming ? mStream.mRaw : mBytes.mRaw;

	/// @brief String, PropertyName: whether the text has escapes (StringValue then differs from
	/// RawValue).
	public bool ValueIsEscaped => mStreaming ? mStream.mEscaped : mBytes.mEscaped;

	/// @brief Number: what the token holds (an int64, a uint64, a float or a big integer).
	public JsonNumberKind NumberKind => mStreaming ? mStream.mNumberKind : mBytes.mNumberKind;

	/// @brief Whether the read has stopped at an error; Next then returns it again.
	public bool IsStopped => mStreaming ? mStream.IsStopped : mBytes.IsStopped;

	/// @brief Number: the value as an int64, if the token is an integer that fits (`NumberKind` Integer).
	/// @param value Receives the value.
	/// @return Whether it fits.
	public bool TryGetInt64(out int64 value)
	{
		value = 0;
		if (TokenType != .Number || NumberKind != .Integer)
			return false;
		value = mStreaming ? mStream.mInteger : mBytes.mInteger;
		return true;
	}

	/// @brief Number: the value as a uint64, if the token is a non-negative integer that fits.
	/// @param value Receives the value.
	/// @return Whether it fits.
	public bool TryGetUInt64(out uint64 value)
	{
		value = 0;
		if (TokenType != .Number)
			return false;
		int64 integer = mStreaming ? mStream.mInteger : mBytes.mInteger;
		switch (NumberKind)
		{
		case .Integer:
			if (integer < 0)
				return false;
			value = (uint64)integer;
			return true;
		case .UInteger:
			value = (uint64)integer;
			return true;
		default:
			return false;
		}
	}

	/// @brief Number: the correctly rounded double of any number token, if it is finite (`1e400` is not:
	/// GetDouble reports it). Integers beyond 2^53 round as their text does.
	/// @param value Receives the double.
	/// @return Whether the token is a number with a finite double.
	public bool TryGetDouble(out double value)
	{
		value = 0;
		if (TokenType != .Number)
			return false;
		return mStreaming ? mStream.GetDouble(out value) : mBytes.GetDouble(out value);
	}

	/// @brief Number: the correctly rounded double, or a NumberOutOfRange error located at the token
	/// when it overflows (never a silent infinity).
	/// @return The double, or the error.
	public Result<double, JsonParseError> GetDouble()
	{
		if (TokenType != .Number)
			return .Err(MakeError(.NumberOutOfRange, "The token is not a number", Offset, EndOffset - Offset));
		if (TryGetDouble(let value))
			return value;
		return .Err(MakeError(.NumberOutOfRange, scope $"The number `{RawValue}` is beyond the range of a double (±1.7976931348623157e308)", Offset, EndOffset - Offset));
	}

	/// @brief Append the current String or PropertyName token's decoded text.
	/// @param output The string to append to.
	public void GetString(String output)
	{
		output.Append(StringValue);
	}

	/// An error at `offset` of the input, located (for errors found outside the reader: duplicates,
	/// conversions).
	internal JsonParseError MakeError(JsonErrorKind kind, StringView message, int offset, int length)
	{
		return mStreaming ? mStream.MakeError(kind, message, offset, length) : mBytes.MakeError(kind, message, offset, length);
	}
}
