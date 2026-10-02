using System;
using internal JsonBeef;

namespace JsonBeef;

/// @brief What the writers do with a NaN or infinite double, which JSON cannot represent.
public enum JsonNonFiniteNumbers : uint8
{
	/// @brief A NonFiniteNumber error (the default: the output stays JSON).
	Error,
	/// @brief Write `null` (as JavaScript's JSON.stringify does).
	Null,
	/// @brief Write `NaN`, `Infinity`, `-Infinity`: JSON5 and Python read them, JSON parsers do not.
	Tokens
}

/// @brief How JsonWriter and JsonDocument.Write lay out and escape their output. The default is compact
/// RFC 8259 JSON with minimal escaping and floats in the plain layout.
public struct JsonWriteOptions
{
	/// @brief Write each element and member on its own line, indented (pretty printing). Empty arrays and
	/// objects stay `[]` and `{}`; a member is `"name": value`.
	public bool Indented = false;
	/// @brief The text of one indentation level when Indented.
	public StringView IndentText = "  ";
	/// @brief The line break when Indented (and after the value with FinalNewline).
	public StringView NewLine = "\n";
	/// @brief End the output with NewLine.
	public bool FinalNewline = false;
	/// @brief The layout of doubles (integers are always written exactly).
	public JsonFloatFormat FloatFormat = .Plain;
	/// @brief NaN and ±infinity.
	public JsonNonFiniteNumbers NonFiniteNumbers = .Error;
	/// @brief Escape every non-ASCII character as `\uXXXX` (a surrogate pair above U+FFFF): ASCII output.
	public bool EscapeNonAscii = false;
	/// @brief Escape `<`, `>` and `&` as `<`, `>`, `&`, so the output can sit inside an
	/// HTML `<script>` element.
	public bool EscapeHtml = false;
	/// @brief Escape U+2028 and U+2029 (line terminators in JavaScript before ES2019).
	public bool EscapeLineSeparators = false;
	/// @brief RFC 8785 (JCS) output: no whitespace, numbers as ECMAScript writes their doubles, and from
	/// JsonDocument members sorted by their names' UTF-16 code units; duplicate names, numbers beyond a
	/// double and non-finite values are errors. The layout and escaping options are ignored.
	public bool Canonical = false;

	/// @brief Compact output (the default).
	public static Self Compact => .();

	/// @brief Indented with two spaces and LF, with a final newline.
	public static Self Pretty
	{
		get
		{
			Self options = .();
			options.Indented = true;
			options.FinalNewline = true;
			return options;
		}
	}

	/// @brief RFC 8785 JSON Canonicalization Scheme output.
	public static Self Jcs
	{
		get
		{
			Self options = .();
			options.Canonical = true;
			return options;
		}
	}
}

/// @brief Why writing failed.
public enum JsonWriteErrorKind : uint8
{
	/// @brief A NaN or infinite double with JsonNonFiniteNumbers.Error.
	NonFiniteNumber,
	/// @brief A string or name that is not well-formed UTF-8.
	InvalidUtf8,
	/// @brief A number's text that does not follow the JSON number grammar (WriteNumberText).
	InvalidNumber,
	/// @brief Canonical output of a number beyond a double's range.
	NumberOutOfRange,
	/// @brief Canonical output of an object with two members of the same name.
	DuplicateName,
	/// @brief Calls out of order: a value where a name is needed (or the reverse), an end that does not
	/// match its start, a second root value, or an unfinished document.
	InvalidStructure,
	/// @brief Typed writing ([JsonObject]): a value JSON has no text for, such as an enum value that is
	/// none of its cases.
	InvalidValue,
	/// @brief Writing a file failed.
	IoError
}

/// @brief A write error. `mMessage` views a per-thread buffer, valid until the next error on the thread.
public struct JsonWriteError
{
	static LazyTLS<String> sMessageBuffer = new .() ~ delete _;

	public JsonWriteErrorKind mKind;
	/// @brief Human-readable description. Valid until the next error on this thread.
	public StringView mMessage;

	public this(JsonWriteErrorKind kind, StringView message)
	{
		mKind = kind;
		let buffer = sMessageBuffer.Value;
		if (message.Ptr >= buffer.Ptr && message.Ptr < buffer.Ptr + buffer.Length)
		{
			let copy = scope String(message);
			buffer.Set(copy);
		}
		else
			buffer.Set(message);
		mMessage = buffer;
	}

	public override void ToString(String output)
	{
		output.Append(mMessage);
	}
}

/// @brief A streaming JSON writer: values, names and container boundaries in document order, appended
/// to a String as compact or indented JSON.
///
/// Misuse and bad data do not stop the program: the first problem is recorded (`HasError`), later
/// calls write nothing, and `Finish` returns it. Strings are checked as UTF-8; doubles that JSON cannot
/// hold follow `JsonWriteOptions.NonFiniteNumbers`.
///
/// ```
/// let output = scope String();
/// let writer = scope JsonWriter(output);
/// writer.WriteStartObject();
/// writer.WritePropertyName("name");
/// writer.WriteString("Ada");
/// writer.WriteEndObject();
/// Try!(writer.Finish());
/// ```
public class JsonWriter
{
	String mOutput;
	JsonWriteOptions mOptions;
	/// Per open container: bit 0 object, bit 1 has an element or member.
	JsonStack<uint8> mFrames ~ delete _;
	bool mAfterName;
	bool mRootWritten;
	bool mFailed;
	JsonWriteError mError;

	/// @brief Create a writer that appends to `output` (which must outlive it).
	/// @param output The string to append to.
	/// @param options Layout, escaping and number options.
	public this(String output, JsonWriteOptions options = .())
	{
		mOutput = output;
		mOptions = options;
		if (options.Canonical)
			mOptions.Indented = false;
		mFrames = new .(16);
	}

	/// @brief Start again: append the next document to `output` with `options`.
	/// @param output The string to append to.
	/// @param options Layout, escaping and number options.
	public void Reset(String output, JsonWriteOptions options = .())
	{
		mOutput = output;
		mOptions = options;
		if (options.Canonical)
			mOptions.Indented = false;
		mFrames.Clear();
		mAfterName = false;
		mRootWritten = false;
		mFailed = false;
	}

	/// @brief The options in use.
	public JsonWriteOptions Options => mOptions;

	/// @brief The number of open arrays and objects.
	public int Depth => mFrames.Count;

	/// @brief Whether a call failed (Finish returns the error).
	public bool HasError => mFailed;

	/// @brief Check that the document is complete (one value, every container closed), add the final
	/// newline if asked.
	/// @return .Ok, or the first error of any call.
	public Result<void, JsonWriteError> Finish()
	{
		if (!mFailed)
		{
			if (!mFrames.IsEmpty)
				Fail(.InvalidStructure, "Finish: an array or object is still open");
			else if (!mRootWritten)
				Fail(.InvalidStructure, "Finish: nothing was written (a document holds one value)");
			else if (mOptions.FinalNewline)
				mOutput.Append(mOptions.NewLine);
		}
		if (mFailed)
			return .Err(mError);
		return .Ok;
	}

	/// @brief Record an error of the caller's own (a converter's, a value it cannot write): the writer
	/// stops as for its own errors, and Finish returns the first one.
	/// @param kind The category.
	/// @param message What went wrong.
	public void SetError(JsonWriteErrorKind kind, StringView message)
	{
		Fail(kind, message);
	}

	/// Records the first error; later calls write nothing.
	internal void Fail(JsonWriteErrorKind kind, StringView message)
	{
		if (mFailed)
			return;
		mFailed = true;
		mError = JsonWriteError(kind, message);
	}

	// Structure

	/// @brief `{`: members follow (WritePropertyName, then the value), then WriteEndObject.
	public void WriteStartObject()
	{
		if (!BeforeValue())
			return;
		mOutput.Append('{');
		mFrames.Add(1);
	}

	/// @brief `}`, closing the innermost open object.
	public void WriteEndObject()
	{
		EndContainer(true);
	}

	/// @brief `[`: elements follow, then WriteEndArray.
	public void WriteStartArray()
	{
		if (!BeforeValue())
			return;
		mOutput.Append('[');
		mFrames.Add(0);
	}

	/// @brief `]`, closing the innermost open array.
	public void WriteEndArray()
	{
		EndContainer(false);
	}

	void EndContainer(bool isObject)
	{
		if (mFailed)
			return;
		if (mFrames.IsEmpty || ((mFrames.Back & 1) != 0) != isObject || mAfterName)
		{
			Fail(.InvalidStructure, isObject ? "WriteEndObject: no object is open here" : "WriteEndArray: no array is open here");
			return;
		}
		bool hadItems = (mFrames.PopBack() & 2) != 0;
		if (hadItems && mOptions.Indented)
			NewLineAndIndent();
		mOutput.Append(isObject ? '}' : ']');
	}

	/// @brief A member's name, in an object; its value follows.
	/// @param name The name (UTF-8).
	public void WritePropertyName(StringView name)
	{
		if (mFailed)
			return;
		if (mFrames.IsEmpty || (mFrames.Back & 1) == 0 || mAfterName)
		{
			Fail(.InvalidStructure, "WritePropertyName: not in an object, or the previous name has no value yet");
			return;
		}
		if ((mFrames.Back & 2) != 0)
			mOutput.Append(',');
		mFrames.Back |= 2;
		if (mOptions.Indented)
			NewLineAndIndent();
		AppendQuoted(name);
		mOutput.Append(mOptions.Indented ? ": " : ":");
		mAfterName = true;
	}

	/// The separator and indentation before a value; false (nothing written) after an error or out of
	/// order.
	[Inline]
	bool BeforeValue()
	{
		if (mFailed)
			return false;
		if (mFrames.IsEmpty)
		{
			if (mRootWritten)
			{
				Fail(.InvalidStructure, "A second value after the document's value (a document holds one value)");
				return false;
			}
			mRootWritten = true;
			return true;
		}
		if ((mFrames.Back & 1) != 0)
		{
			if (!mAfterName)
			{
				Fail(.InvalidStructure, "A value in an object needs WritePropertyName first");
				return false;
			}
			mAfterName = false;
			return true;
		}
		if ((mFrames.Back & 2) != 0)
			mOutput.Append(',');
		mFrames.Back |= 2;
		if (mOptions.Indented)
			NewLineAndIndent();
		return true;
	}

	void NewLineAndIndent()
	{
		mOutput.Append(mOptions.NewLine);
		for (int i < mFrames.Count)
			mOutput.Append(mOptions.IndentText);
	}

	// Values

	/// @brief `null`.
	public void WriteNull()
	{
		if (BeforeValue())
			mOutput.Append("null");
	}

	/// @brief `true` or `false`.
	public void WriteBool(bool value)
	{
		if (BeforeValue())
			mOutput.Append(value ? "true" : "false");
	}

	/// @brief A string, escaped as the options say (always `"`, `\` and the control characters).
	/// @param value The text (UTF-8; may hold U+0000).
	public void WriteString(StringView value)
	{
		if (BeforeValue())
			AppendQuoted(value);
	}

	/// @brief An integer, exactly.
	public void WriteNumber(int64 value)
	{
		if (!BeforeValue())
			return;
		if (mOptions.Canonical && (value <= -((int64)1 << 53) || value >= ((int64)1 << 53)))
		{
			// JCS writes the double nearest the integer
			let text = scope String();
			text.AppendF("{}", value);
			JsonNumber.ParseDouble(text, let rounded);
			JsonNumber.AppendDouble(mOutput, rounded, .EcmaScript);
			return;
		}
		value.ToString(mOutput);
	}

	/// @brief An unsigned integer, exactly.
	public void WriteNumber(uint64 value)
	{
		if (!BeforeValue())
			return;
		if (mOptions.Canonical && value >= (1UL << 53))
		{
			let text = scope String();
			text.AppendF("{}", value);
			JsonNumber.ParseDouble(text, let rounded);
			JsonNumber.AppendDouble(mOutput, rounded, .EcmaScript);
			return;
		}
		value.ToString(mOutput);
	}

	/// @brief A double as its shortest round-trip digits in the options' layout (ECMAScript when
	/// Canonical). NaN and ±∞ follow NonFiniteNumbers.
	public void WriteNumber(double value)
	{
		if (!value.IsFinite)
		{
			if (mOptions.Canonical || mOptions.NonFiniteNumbers == .Error)
			{
				if (!mFailed)
					Fail(.NonFiniteNumber, scope $"{(value.IsNaN ? "NaN" : value < 0 ? "-Infinity" : "Infinity")} cannot be written as JSON (JsonWriteOptions.NonFiniteNumbers)");
				return;
			}
			if (!BeforeValue())
				return;
			if (mOptions.NonFiniteNumbers == .Null)
				mOutput.Append("null");
			else
				JsonNumber.AppendDouble(mOutput, value);
			return;
		}
		if (BeforeValue())
			JsonNumber.AppendDouble(mOutput, value, mOptions.Canonical ? .EcmaScript : mOptions.FloatFormat);
	}

	/// @brief A float as its own shortest round-trip digits (`0.1`, which reads back as the same
	/// float), in the options' layout. Canonical (RFC 8785, whose numbers are doubles) writes the
	/// double it widens to. NaN and ±∞ follow NonFiniteNumbers.
	public void WriteFloat(float value)
	{
		if (!value.IsFinite || mOptions.Canonical)
		{
			WriteNumber((double)value);
			return;
		}
		if (BeforeValue())
			JsonNumber.AppendFloat(mOutput, value, mOptions.FloatFormat);
	}

	/// @brief A number given as its text, written as is (a big integer, `1.50`, `1e400`); it must follow
	/// the JSON number grammar. With Canonical, its double in ECMAScript layout (an error beyond the
	/// double range).
	/// @param text The number's text.
	public void WriteNumberText(StringView text)
	{
		if (mFailed)
			return;
		if (!IsNumberText(text))
		{
			Fail(.InvalidNumber, scope $"`{text}` is not a JSON number");
			return;
		}
		if (mOptions.Canonical)
		{
			if (!JsonNumber.ParseDouble(text, let value))
			{
				Fail(.NumberOutOfRange, scope $"The number `{text}` is beyond the range of a double, which canonical JSON (RFC 8785) cannot write");
				return;
			}
			if (BeforeValue())
				JsonNumber.AppendDouble(mOutput, value, .EcmaScript);
			return;
		}
		if (BeforeValue())
			mOutput.Append(text);
	}

	/// Whether `text` matches RFC 8259's number production.
	internal static bool IsNumberText(StringView text)
	{
		int i = 0;
		int n = text.Length;
		if (i < n && text[i] == '-')
			i++;
		if (i >= n || !JsonChar.IsDigit(text[i]))
			return false;
		if (text[i] == '0')
			i++;
		else
		{
			while (i < n && JsonChar.IsDigit(text[i]))
				i++;
		}
		if (i < n && text[i] == '.')
		{
			i++;
			if (i >= n || !JsonChar.IsDigit(text[i]))
				return false;
			while (i < n && JsonChar.IsDigit(text[i]))
				i++;
		}
		if (i < n && (text[i] == 'e' || text[i] == 'E'))
		{
			i++;
			if (i < n && (text[i] == '+' || text[i] == '-'))
				i++;
			if (i >= n || !JsonChar.IsDigit(text[i]))
				return false;
			while (i < n && JsonChar.IsDigit(text[i]))
				i++;
		}
		return i == n;
	}

	// Strings

	/// `"text"`, escaped.
	void AppendQuoted(StringView text)
	{
		mOutput.Append('"');
		if (!AppendEscaped(mOutput, text, mOptions))
			Fail(.InvalidUtf8, "A string or name is not well-formed UTF-8");
		mOutput.Append('"');
	}

	/// Appends `text` escaped: `"`, `\` and U+0000-U+001F always (`\b \t \n \f \r`, else `\u00xx` in
	/// lowercase hex: JCS's and JSON.stringify's spelling), and what the options add. Plain runs are
	/// found 8 bytes at a time. Surrogates in WTF-8 (`ED A0 80`: strings read with
	/// JsonInvalidSurrogates.Wtf8) are written as their escapes (`\ud800`), except in canonical output.
	/// @return Whether `text` is well-formed UTF-8 (the bytes are appended either way).
	internal static bool AppendEscaped(String output, StringView text, JsonWriteOptions options)
	{
		char8* p = text.Ptr;
		int length = text.Length;
		bool extra = !options.Canonical && (options.EscapeHtml || options.EscapeNonAscii || options.EscapeLineSeparators);
		bool valid = true;
		int run = 0;
		int i = 0;
		while (i < length)
		{
			// Words of plain ASCII
			while (i + 8 <= length)
			{
				uint64 word = JsonChar.Load64(p + i);
				uint64 stops = JsonChar.StringStops(word) | (word & JsonChar.cHigh);
				if (extra && options.EscapeHtml)
					stops |= JsonChar.BytesEqual(word, (uint8)'<') | JsonChar.BytesEqual(word, (uint8)'>') | JsonChar.BytesEqual(word, (uint8)'&');
				if (stops != 0)
				{
					i += JsonChar.FirstByte(stops);
					break;
				}
				i += 8;
			}
			if (i >= length)
				break;
			char8 c = p[i];
			uint8 b = (uint8)c;
			if (b >= 0x80)
			{
				int seqLength = JsonChar.ValidSequenceLength(p, i, length);
				if (seqLength == 0)
				{
					// A surrogate in WTF-8 (JsonInvalidSurrogates.Wtf8): back to its escape, so the text
					// reads back the same. Not in canonical output (RFC 8785 §3.2.2.2: an error).
					if (b == 0xED && !options.Canonical && i + 2 < length && (uint8)p[i + 1] >= 0xA0 && (uint8)p[i + 1] <= 0xBF && ((uint8)p[i + 2] & 0xC0) == 0x80)
					{
						output.Append(p + run, i - run);
						AppendUnicodeEscape(output, 0xD000 | (((uint32)(uint8)p[i + 1] & 0x3F) << 6) | ((uint32)(uint8)p[i + 2] & 0x3F));
						i += 3;
						run = i;
						continue;
					}
					valid = false;
					i++;
					continue;
				}
				if (extra)
				{
					uint32 cp = (uint32)JsonChar.Decode(p, i, ?);
					if (options.EscapeNonAscii || (options.EscapeLineSeparators && (cp == 0x2028 || cp == 0x2029)))
					{
						output.Append(p + run, i - run);
						AppendUnicodeEscape(output, cp);
						i += seqLength;
						run = i;
						continue;
					}
				}
				i += seqLength;
				continue;
			}
			bool escape = b < 0x20 || c == '"' || c == '\\' || (extra && options.EscapeHtml && (c == '<' || c == '>' || c == '&'));
			if (!escape)
			{
				i++;
				continue;
			}
			output.Append(p + run, i - run);
			switch (c)
			{
			case '"': output.Append("\\\"");
			case '\\': output.Append("\\\\");
			case '\b': output.Append("\\b");
			case '\t': output.Append("\\t");
			case '\n': output.Append("\\n");
			case '\f': output.Append("\\f");
			case '\r': output.Append("\\r");
			default: AppendUnicodeEscape(output, b);
			}
			i++;
			run = i;
		}
		output.Append(p + run, length - run);
		return valid;
	}

	/// `\uxxxx` (lowercase hex), a surrogate pair above U+FFFF.
	static void AppendUnicodeEscape(String output, uint32 cp)
	{
		if (cp >= 0x10000)
		{
			uint32 v = cp - 0x10000;
			AppendUnicodeEscape(output, 0xD800 + (v >> 10));
			AppendUnicodeEscape(output, 0xDC00 + (v & 0x3FF));
			return;
		}
		const String hex = "0123456789abcdef";
		output.Append("\\u");
		output.Append(hex[(cp >> 12) & 0xF]);
		output.Append(hex[(cp >> 8) & 0xF]);
		output.Append(hex[(cp >> 4) & 0xF]);
		output.Append(hex[cp & 0xF]);
	}
}
