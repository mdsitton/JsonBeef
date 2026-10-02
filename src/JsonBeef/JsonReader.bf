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
	/// Typed binding: the error of the JsonBind call that last returned false.
	internal JsonParseError mBindError;

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
	public int Depth => mStreaming ? mStream.TokenDepth : mBytes.TokenDepth;

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

	/// @brief The config the reader was last reset with.
	public JsonReadConfig Config => mStreaming ? mStream.Config : mBytes.Config;

	// On-demand

	/// @brief Skip the value the current token starts, to its last token (a container's EndObject or
	/// EndArray; a scalar is its own token), so that Next goes on after it. Skipping checks everything
	/// reading would (UTF-8, escapes, numbers, structure, limits): an invalid value is an error here
	/// too. At a PropertyName it skips the member's value; before the first token, the document's
	/// value; at an End token or EndOfDocument there is nothing to skip.
	/// @return .Ok, or the read's error.
	public Result<void, JsonParseError> SkipValue()
	{
		if (!mStreaming)
		{
			if (mBytes.SkipValue() case .Err)
				return .Err(mBytes.mError);
			return .Ok;
		}
		if (mStream.SkipValue() case .Err)
			return .Err(mStream.mError);
		return .Ok;
	}

	/// @brief The source text of the value the current token starts, checked and skipped as SkipValue
	/// does: a string with its quotes and escapes as written, a number as written, a container from its
	/// bracket through the closing one, whitespace and all. Valid until the next call to Next or Reset.
	/// A stream keeps the whole value in its buffer for this, so MaxTokenBytes bounds it.
	/// @return The text, or the read's error.
	public Result<StringView, JsonParseError> ReadRaw()
	{
		if (!mStreaming)
		{
			if (mBytes.ReadRaw() case .Ok(let raw))
				return raw;
			return .Err(mBytes.mError);
		}
		if (mStream.ReadRaw() case .Ok(let raw))
			return raw;
		return .Err(mStream.mError);
	}

	/// @brief Move forward to the value at `pointer` (RFC 6901), relative to the value the current
	/// token starts (before the first token: the document's): every value passed on the way is skipped
	/// and checked as SkipValue does. Found, the reader is at the value's first token (read it with
	/// Next, SkipValue, ReadRaw or a [JsonObject] type's JsonRead). Not found, the reader is at the last
	/// token of the value where the lookup failed (the object without the member, the array too short,
	/// the scalar that is not a container), so Next goes on after it.
	///
	/// The reader cannot go back: in an object with a repeated name it finds the first member of that
	/// name (JsonNode lookups find the last), and a second Find starts where the first one stopped.
	/// `-` and indexes that are not canonical (`01`) find nothing.
	/// @param pointer The JSON Pointer: `""` for the value itself, else `/`-separated reference tokens
	/// (`~0` for `~`, `~1` for `/`). A malformed pointer is a fatal error (JsonPointer.IsValid checks).
	/// @return Whether the value was found, or the read's error.
	public Result<bool, JsonParseError> Find(StringView pointer)
	{
		if (!JsonPointer.IsValid(pointer))
			Runtime.FatalError(scope $"JsonReader.Find: `{pointer}` is not a JSON Pointer");
		var token = TokenType;
		if (token == .None || token == .PropertyName)
			token = Try!(Next());
		if (token != .StartObject && token != .StartArray && token != .String && token != .Number && token != .True && token != .False && token != .Null)
			return false;
		let scratch = scope String();
		int pos = 0;
		while (pos < pointer.Length)
		{
			pos++;
			StringView reference = JsonPointer.NextToken(pointer, ref pos, scratch).Value;
			switch (TokenType)
			{
			case .StartObject:
				while (true)
				{
					if (Try!(Next()) == .EndObject)
						return false;
					bool match = StringValue == reference;
					Try!(Next());
					if (match)
						break;
					Try!(SkipValue());
				}
			case .StartArray:
				int index = JsonPointer.ParseIndex(reference);
				if (index < 0)
				{
					Try!(SkipValue());
					return false;
				}
				for (int i = 0; ; i++)
				{
					if (Try!(Next()) == .EndArray)
						return false;
					if (i == index)
						break;
					Try!(SkipValue());
				}
			default:
				return false;
			}
		}
		return true;
	}

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
	/// GetDouble reports it). Integers beyond 2^53 round as their text does. A NonFinite token
	/// (`NaN`, `Infinity`, with AllowNonFiniteNumbers) gives the value it names.
	/// @param value Receives the double.
	/// @return Whether the token is a number with a finite double, or a NonFinite one.
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

	/// At a StartObject: whether the member `name` is in the object, its value's first token and a
	/// string's text; the reader is then back where it was (see JsonReaderCore.PeekMember).
	internal Result<bool, JsonParseError> PeekMember(StringView name, out JsonToken token, String text)
	{
		if (!mStreaming)
		{
			if (mBytes.PeekMember(name, out token, text) case .Ok(let found))
				return found;
			return .Err(mBytes.mError);
		}
		if (mStream.PeekMember(name, out token, text) case .Ok(let found))
			return found;
		return .Err(mStream.mError);
	}

	/// The current token's integer payload (Number: Integer or UInteger).
	internal int64 IntegerPayload => mStreaming ? mStream.mInteger : mBytes.mInteger;

	/// The line and column of `offset` (at or after the current token's start for a stream).
	internal bool Locate(int offset, out int line, out int column)
	{
		if (mStreaming)
			return mStream.mCursor.Locate(offset, out line, out column);
		return mBytes.mCursor.Locate(offset, out line, out column);
	}

	/// An error at `offset` of the input, located (for errors found outside the reader: duplicates,
	/// conversions).
	internal JsonParseError MakeError(JsonErrorKind kind, StringView message, int offset, int length)
	{
		return mStreaming ? mStream.MakeError(kind, message, offset, length) : mBytes.MakeError(kind, message, offset, length);
	}
}
