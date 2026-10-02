using System;
using System.Collections;
using internal JsonBeef;

namespace JsonBeef;

/// The error type of the reader's internal methods: empty, so their results are no bigger than their
/// values (KdlBeef measured a JsonParseError-sized error in every Result as a real cost). The error
/// itself is recorded in the reader by Fail, and Next returns it.
internal struct JsonFailure
{
}

/// The reader itself, over a cursor (in-memory text or a buffered stream). It reads through a window:
/// `mData[offset]` for `mBase <= offset < mEnd`, offsets absolute, so the offsets it keeps survive the
/// window moving. Anything that may read at the window's end asks for more first (`Avail`, `AvailN`,
/// `Grow`); for in-memory text the window is the whole input and those checks compile away.
///
/// Parsing is iterative: the open containers are a bit stack (1 = object), so depth costs a bit, not
/// stack. Every token is fully validated when it is read (UTF-8 up front, then grammar, escapes and
/// surrogate pairs, number grammar); strings with escapes are decoded into a reusable buffer.
///
/// Invariants:
/// - **Retention.** The window keeps every byte from min(mRetain, mPos) on: mRetain is the start of the
///   token being read, and stays there until the next call, so the token's views stay valid; a new call
///   releases it.
/// - **Views.** mValue and mRaw view the window or mStringBuffer: valid until the next call (Grow
///   rebases them when the window moves). mError views the per-thread error buffers.
internal class JsonReaderCore<TCursor> where TCursor : IJsonCursor
{
	enum State : uint8
	{
		/// Not set up yet: the cursor's Begin comes first.
		Start,
		/// A value: the document's, an array element after `,`, or a member's after `:`.
		Value,
		/// After `[`: an element or `]`.
		ArrayStart,
		/// After `{`: a member name or `}`.
		ObjectStart,
		/// After `,` in an object: a member name.
		Name,
		/// After a member name: `:` and the value.
		Colon,
		/// After a value: `,` or the container's end, or at depth 0 the end of the input.
		AfterValue,
		End,
		Failed
	}

	internal TCursor mCursor;
	char8* mData;
	int mBase;
	int mPos;
	int mEnd;
	/// The start of the token being read (int.MaxValue: none).
	int mRetain;
	/// The cursor stopped on an error of the input; the reader's next error is replaced by it.
	bool mInputFailed;
	State mState;
	internal JsonParseError mError;
	JsonReadConfig mConfig;

	/// The open containers: bit d is set when the container at depth d (0-based) is an object.
	uint64[] mBits ~ delete _;
	int mDepth;

	String mStringBuffer ~ delete _;

	// The current token
	internal JsonToken mToken;
	internal int mTokenStart;
	internal int mTokenEnd;
	internal int mTokenDepth;
	/// String, PropertyName: the decoded text. Number, literals: the token's text.
	internal StringView mValue;
	/// String, PropertyName: the text between the quotes, escapes as written. Number, literals: the
	/// token's text.
	internal StringView mRaw;
	internal bool mEscaped;
	internal JsonNumberKind mNumberKind;
	/// Integer: the value. UInteger: the value's bits.
	internal int64 mInteger;

	public this()
	{
		mBits = new uint64[16];
		mStringBuffer = new .();
		mConfig = .();
	}

	public void Reset(TCursor cursor, JsonReadConfig config)
	{
		mCursor = cursor;
		mConfig = config;
		mData = null;
		mBase = 0;
		mPos = 0;
		mEnd = 0;
		mRetain = int.MaxValue;
		mInputFailed = false;
		mState = .Start;
		mDepth = 0;
		mToken = .None;
		mTokenStart = 0;
		mTokenEnd = 0;
		mTokenDepth = 0;
		mValue = default;
		mRaw = default;
		mEscaped = false;
		mNumberKind = .Integer;
		mInteger = 0;
	}

	/// The next token; on failure the error is in mError. (JsonReader.Next makes the public Result, so
	/// the large error is copied once.)
	[Inline]
	public Result<JsonToken, JsonFailure> NextToken()
	{
		if (mState == .Failed)
			return .Err(.());
		let result = ReadNext();
		if (result case .Err)
			mState = .Failed;
		return result;
	}

	/// Whether the read has stopped at an error.
	public bool IsStopped => mState == .Failed;

	/// The current depth: the number of open containers.
	public int CurrentDepth => mDepth;

	Result<JsonToken, JsonFailure> ReadNext()
	{
		mRetain = int.MaxValue;
		switch (mState)
		{
		case .Start:
			switch (mCursor.Begin(ref mData, ref mBase, ref mEnd))
			{
			case .Ok(let start):
				mPos = start;
			case .Err(let error):
				mError = error;
				if (!mConfig.SourceName.IsEmpty)
					mError.SetSource(mConfig.SourceName);
				return .Err(.());
			}
			mState = .Value;
			return ReadValue(false);
		case .Value:
			return ReadValue(true);
		case .ArrayStart:
			SkipSpace();
			if (Avail(mPos) && mData[mPos] == ']')
				return EndContainer();
			return ReadValue(false);
		case .ObjectStart:
			SkipSpace();
			if (!Avail(mPos))
				return .Err(EndOfInput("The input ends inside an object: expected a member name or `}`"));
			if (mData[mPos] == '"')
				return ReadString(true);
			if (mData[mPos] == '}')
				return EndContainer();
			return .Err(Unexpected(.InvalidStructure, "a member name (a string in double quotes) or `}`"));
		case .Name:
			return ReadNameAfterComma();
		case .Colon:
			SkipSpace();
			if (!Avail(mPos))
				return .Err(EndOfInput("The input ends inside an object: expected `:` after the member name"));
			if (mData[mPos] != ':')
				return .Err(Unexpected(.InvalidStructure, "`:` after the member name"));
			mPos++;
			mState = .Value;
			return ReadValue(false);
		case .AfterValue:
			return ReadAfterValue();
		case .End:
			return .Ok(.EndOfDocument);
		case .Failed:
			return .Err(.());
		}
	}

	/// After a value: `,` or the container's end; at depth 0, nothing but whitespace.
	Result<JsonToken, JsonFailure> ReadAfterValue()
	{
		SkipSpace();
		if (mDepth == 0)
		{
			if (Avail(mPos))
				return .Err(Unexpected(.InvalidStructure, "the end of the input after the JSON value (a document holds one value)"));
			mState = .End;
			mToken = .EndOfDocument;
			mTokenStart = mPos;
			mTokenEnd = mPos;
			mTokenDepth = 0;
			return .Ok(.EndOfDocument);
		}
		bool inObject = InObject;
		if (!Avail(mPos))
			return .Err(EndOfInput(inObject ? "The input ends inside an object: expected `,` or `}`" : "The input ends inside an array: expected `,` or `]`"));
		char8 c = mData[mPos];
		if (c == ',')
		{
			mPos++;
			if (inObject)
				return ReadNameAfterComma();
			mState = .Value;
			return ReadValue(true);
		}
		if (c == (inObject ? '}' : ']'))
			return EndContainer();
		return .Err(Unexpected(.InvalidStructure, inObject ? "`,` or `}` after a member's value" : "`,` or `]` after an array element"));
	}

	/// After `,` in an object: the next member's name.
	Result<JsonToken, JsonFailure> ReadNameAfterComma()
	{
		mState = .Name;
		SkipSpace();
		if (!Avail(mPos))
			return .Err(EndOfInput("The input ends inside an object: expected a member name after `,`"));
		char8 c = mData[mPos];
		if (c == '"')
			return ReadString(true);
		if (c == '}')
			return .Err(Fail(.InvalidStructure, "Expected a member name after `,`, found `}` (a trailing comma is not allowed)", mPos));
		return .Err(Unexpected(.InvalidStructure, "a member name (a string in double quotes) after `,`"));
	}

	/// A value: a scalar token, or the start of a container. `afterComma`: in an array after `,` (for
	/// the trailing-comma message).
	Result<JsonToken, JsonFailure> ReadValue(bool afterComma)
	{
		SkipSpace();
		if (!Avail(mPos))
		{
			if (mDepth == 0)
				return .Err(EndOfInput("Expected a JSON value, found the end of the input"));
			return .Err(EndOfInput(InObject ? "The input ends inside an object: expected a value" : "The input ends inside an array: expected a value"));
		}
		char8 c = mData[mPos];
		switch (JsonChar.sByteClass[(uint8)c])
		{
		case .Quote:
			return ReadString(false);
		case .Number:
			return ReadNumber();
		case .Literal:
			return ReadLiteral();
		case .Punct:
			if (c == '[')
				return StartContainer(false);
			if (c == '{')
				return StartContainer(true);
			if (c == ']' && afterComma && mDepth > 0 && !InObject)
				return .Err(Fail(.InvalidStructure, "Expected a value after `,`, found `]` (a trailing comma is not allowed)", mPos));
			return .Err(Unexpected(.InvalidStructure, "a value"));
		default:
			return .Err(UnexpectedInValue());
		}
	}

	/// The error for a byte that cannot start a value, worded for the likely cause.
	JsonFailure UnexpectedInValue()
	{
		char8 c = mData[mPos];
		if (c == '\'')
			return Fail(.UnexpectedChar, "Expected a value, found `'` (strings are written in double quotes)", mPos);
		if (c == '+')
			return Fail(.InvalidNumber, "A number cannot start with `+`", mPos);
		if (c == '.')
			return Fail(.InvalidNumber, "A number needs a digit before its decimal point (`0.5`, not `.5`)", mPos);
		if (IsWordByte(c))
		{
			int end = WordEnd(mPos);
			StringView word = View(mPos, end - mPos);
			if (word == "NaN" || word == "Infinity")
				return Fail(.InvalidNumber, scope $"`{word}` is not a JSON number (non-finite numbers are not allowed)", mPos, end - mPos);
			return Fail(.InvalidLiteral, scope $"Invalid literal `{word}` (JSON's literals are `true`, `false` and `null`)", mPos, end - mPos);
		}
		return Unexpected(.UnexpectedChar, "a value");
	}

	Result<JsonToken, JsonFailure> StartContainer(bool isObject)
	{
		if (mConfig.MaxDepth > 0 && mDepth >= mConfig.MaxDepth)
			return .Err(Fail(.ResourceLimitExceeded, scope $"The nesting depth exceeds MaxDepth ({mConfig.MaxDepth})", mPos));
		int word = mDepth >> 6;
		if (word >= mBits.Count)
		{
			let old = mBits;
			mBits = new uint64[old.Count * 2];
			old.CopyTo(mBits);
			delete old;
		}
		uint64 bit = 1UL << (mDepth & 63);
		if (isObject)
			mBits[word] |= bit;
		else
			mBits[word] &= ~bit;
		mToken = isObject ? .StartObject : .StartArray;
		mTokenStart = mPos;
		mTokenEnd = mPos + 1;
		mTokenDepth = mDepth;
		mDepth++;
		mPos++;
		mState = isObject ? .ObjectStart : .ArrayStart;
		return .Ok(mToken);
	}

	Result<JsonToken, JsonFailure> EndContainer()
	{
		mDepth--;
		mToken = mData[mPos] == '}' ? .EndObject : .EndArray;
		mTokenStart = mPos;
		mTokenEnd = mPos + 1;
		mTokenDepth = mDepth;
		mPos++;
		mState = .AfterValue;
		return .Ok(mToken);
	}

	/// Whether the innermost open container is an object (mDepth > 0).
	bool InObject
	{
		[Inline]
		get
		{
			int d = mDepth - 1;
			return ((mBits[d >> 6] >> (d & 63)) & 1) != 0;
		}
	}

	// Literals

	Result<JsonToken, JsonFailure> ReadLiteral()
	{
		int start = mPos;
		mRetain = start;
		char8 c = mData[start];
		StringView literal = c == 't' ? "true" : c == 'f' ? "false" : "null";
		int length = literal.Length;
		if (!AvailN(start, length) || !JsonChar.EqualBytes(mData + start, literal.Ptr, length) || (Avail(start + length) && IsWordByte(mData[start + length])))
		{
			int end = WordEnd(start);
			StringView word = View(start, end - start);
			if (word.Length < length && literal.StartsWith(word))
			{
				if (!Avail(end))
					return .Err(Fail(.InvalidLiteral, scope $"The input ends inside the literal `{literal}` (found `{word}`)", start, end - start));
				return .Err(Fail(.InvalidLiteral, scope $"Invalid literal `{word}` (expected `{literal}`)", start, end - start));
			}
			return .Err(Fail(.InvalidLiteral, scope $"Invalid literal `{word}` (JSON's literals are `true`, `false` and `null`)", start, end - start));
		}
		mToken = c == 't' ? .True : c == 'f' ? .False : .Null;
		mTokenStart = start;
		mTokenEnd = start + length;
		mTokenDepth = mDepth;
		mValue = View(start, length);
		mRaw = mValue;
		mEscaped = false;
		mPos = start + length;
		mState = .AfterValue;
		return .Ok(mToken);
	}

	[Inline]
	static bool IsWordByte(char8 c)
	{
		return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
	}

	/// The end of the run of ASCII letters, digits and `_` from `pos` (at most 32 bytes: it only words
	/// error messages).
	int WordEnd(int pos)
	{
		int end = pos;
		while (end - pos < 32 && Avail(end) && IsWordByte(mData[end]))
			end++;
		return end;
	}

	// Numbers

	Result<JsonToken, JsonFailure> ReadNumber()
	{
		int start = mPos;
		mRetain = start;
		int p = start;
		bool negative = false;
		if (mData[p] == '-')
		{
			negative = true;
			p++;
			if (!Avail(p) || !JsonChar.IsDigit(mData[p]))
				return .Err(NumberError("Expected a digit after `-`", p));
		}
		uint64 magnitude = 0;
		int digits = 0;
		bool big = false;
		if (mData[p] == '0')
		{
			p++;
			digits = 1;
			if (Avail(p) && JsonChar.IsDigit(mData[p]))
				return .Err(Fail(.InvalidNumber, "A number cannot have a leading zero (`01`): write `1`, or `0.1` for a fraction", start, p + 1 - start));
		}
		else
		{
			// 19 digits always fit; the 20th may overflow; more make a big integer
			while (true)
			{
				while (p < mEnd && JsonChar.IsDigit(mData[p]))
				{
					uint64 digit = (uint8)mData[p] - (uint8)'0';
					if (digits < 19)
						magnitude = magnitude * 10 + digit;
					else if (digits == 19 && (magnitude < 1844674407370955161UL || (magnitude == 1844674407370955161UL && digit <= 5)))
						magnitude = magnitude * 10 + digit;
					else
						big = true;
					digits++;
					p++;
				}
				if (p < mEnd || !Grow(p, 1))
					break;
			}
		}
		bool isFloat = false;
		if (Avail(p) && mData[p] == '.')
		{
			p++;
			if (!Avail(p) || !JsonChar.IsDigit(mData[p]))
				return .Err(NumberError("Expected a digit after the decimal point", p));
			p = SkipDigits(p);
			isFloat = true;
		}
		if (Avail(p) && (mData[p] == 'e' || mData[p] == 'E'))
		{
			p++;
			if (Avail(p) && (mData[p] == '+' || mData[p] == '-'))
				p++;
			if (!Avail(p) || !JsonChar.IsDigit(mData[p]))
				return .Err(NumberError("Expected a digit in the exponent", p));
			p = SkipDigits(p);
			isFloat = true;
		}
		int length = p - start;
		if (mConfig.MaxNumberLength > 0 && length > mConfig.MaxNumberLength)
			return .Err(Fail(.ResourceLimitExceeded, scope $"The number ({length} bytes) exceeds MaxNumberLength ({mConfig.MaxNumberLength})", start, length));
		// Something that continues the number's text: a malformed number, not a missing separator
		if (Avail(p) && (IsWordByte(mData[p]) || mData[p] == '.' || mData[p] == '+' || mData[p] == '-'))
		{
			let message = scope String();
			message.Append("Unexpected ");
			JsonChar.AppendCharDescription(message, mData, p, mEnd, let charLength);
			message.AppendF(" after the number `{}`", View(start, length));
			return .Err(Fail(.InvalidNumber, message, p, charLength));
		}
		if (isFloat)
			mNumberKind = .Float;
		else if (big)
			mNumberKind = .BigInteger;
		else if (negative)
		{
			if (magnitude <= (uint64)int64.MaxValue + 1)
			{
				mNumberKind = .Integer;
				mInteger = magnitude == 0 ? 0 : -(int64)(magnitude - 1) - 1;
			}
			else
				mNumberKind = .BigInteger;
		}
		else if (magnitude <= (uint64)int64.MaxValue)
		{
			mNumberKind = .Integer;
			mInteger = (int64)magnitude;
		}
		else
		{
			mNumberKind = .UInteger;
			mInteger = (int64)magnitude;
		}
		mToken = .Number;
		mTokenStart = start;
		mTokenEnd = p;
		mTokenDepth = mDepth;
		mValue = View(start, length);
		mRaw = mValue;
		mEscaped = false;
		mPos = p;
		mState = .AfterValue;
		return .Ok(.Number);
	}

	/// Past the digits from `p` (reading more of a stream as needed).
	[Inline]
	int SkipDigits(int p)
	{
		var p;
		while (true)
		{
			while (p < mEnd && JsonChar.IsDigit(mData[p]))
				p++;
			if (p < mEnd || !Grow(p, 1))
				return p;
		}
	}

	/// "Expected X, found Y" for a malformed number, at `p`.
	JsonFailure NumberError(StringView expected, int p)
	{
		let message = scope String();
		message.Append(expected);
		message.Append(", found ");
		if (!Avail(p))
		{
			message.Append("the end of the input");
			return Fail(.InvalidNumber, message, p, 0);
		}
		JsonChar.AppendCharDescription(message, mData, p, mEnd, let length);
		return Fail(.InvalidNumber, message, p, length);
	}

	// Strings

	/// A string value or a member name (`isName`), from its opening quote at mPos.
	Result<JsonToken, JsonFailure> ReadString(bool isName)
	{
		int start = mPos;
		mRetain = start;
		int p = start + 1;
		while (true)
		{
			p = ScanStringRun(p);
			if (p < mEnd)
				break;
			if (!Grow(p, 1))
				return .Err(UnterminatedString(start, p));
		}
		char8 c = mData[p];
		if (c == '"')
		{
			mValue = View(start + 1, p - start - 1);
			mRaw = mValue;
			mEscaped = false;
		}
		else if (c == '\\')
		{
			Try!(DecodeEscaped(start, ref p));
			mValue = mStringBuffer;
			mRaw = View(start + 1, p - start - 1);
			mEscaped = true;
		}
		else
			return .Err(ControlCharacter(p));
		if (mConfig.MaxStringBytes > 0 && mValue.Length > mConfig.MaxStringBytes)
			return .Err(Fail(.ResourceLimitExceeded, scope $"The string ({mValue.Length} bytes) exceeds MaxStringBytes ({mConfig.MaxStringBytes})", start, p + 1 - start));
		mToken = isName ? .PropertyName : .String;
		mTokenStart = start;
		mTokenEnd = p + 1;
		mTokenDepth = mDepth;
		mPos = p + 1;
		mState = isName ? .Colon : .AfterValue;
		return .Ok(mToken);
	}

	/// The first byte from `p` in the window that ends a string's plain run (`"`, `\` or a control
	/// character), or mEnd: 8 bytes at a time, then byte by byte at the window's end.
	[Inline]
	int ScanStringRun(int p)
	{
		var p;
		while (p + 8 <= mEnd)
		{
			uint64 stops = JsonChar.StringStops(JsonChar.Load64(mData + p));
			if (stops != 0)
				return p + JsonChar.FirstByte(stops);
			p += 8;
		}
		while (p < mEnd)
		{
			char8 c = mData[p];
			if (c == '"' || c == '\\' || (uint8)c < 0x20)
				return p;
			p++;
		}
		return p;
	}

	/// Decodes a string with escapes into mStringBuffer, from its opening quote at `start`; `p` is at its
	/// first backslash and ends at its closing quote.
	Result<void, JsonFailure> DecodeEscaped(int start, ref int p)
	{
		mStringBuffer.Clear();
		mStringBuffer.Append(mData + start + 1, p - start - 1);
		while (true)
		{
			char8 c = mData[p];
			if (c == '"')
				return .Ok;
			if ((uint8)c < 0x20)
				return .Err(ControlCharacter(p));
			// A backslash
			if (!Avail(p + 1))
				return .Err(UnterminatedString(start, p + 1));
			char8 e = mData[p + 1];
			switch (e)
			{
			case '"': mStringBuffer.Append('"'); p += 2;
			case '\\': mStringBuffer.Append('\\'); p += 2;
			case '/': mStringBuffer.Append('/'); p += 2;
			case 'b': mStringBuffer.Append('\b'); p += 2;
			case 'f': mStringBuffer.Append('\f'); p += 2;
			case 'n': mStringBuffer.Append('\n'); p += 2;
			case 'r': mStringBuffer.Append('\r'); p += 2;
			case 't': mStringBuffer.Append('\t'); p += 2;
			case 'u': Try!(DecodeUnicodeEscape(ref p));
			default:
				let message = scope String();
				message.Append("Invalid escape: `\\` followed by ");
				JsonChar.AppendCharDescription(message, mData, p + 1, mEnd, let length);
				message.Append(" (JSON's escapes are `\\\"` `\\\\` `\\/` `\\b` `\\f` `\\n` `\\r` `\\t` and `\\uXXXX`)");
				return .Err(Fail(.InvalidEscape, message, p, 1 + length));
			}
			// The plain run up to the next stop
			while (true)
			{
				int q = ScanStringRun(p);
				mStringBuffer.Append(mData + p, q - p);
				p = q;
				if (p < mEnd)
					break;
				if (!Grow(p, 1))
					return .Err(UnterminatedString(start, p));
			}
		}
	}

	/// A `\uXXXX` escape at `p` (and the low surrogate's escape after a high one): appends the code
	/// point's UTF-8 and moves `p` past the escape(s).
	Result<void, JsonFailure> DecodeUnicodeEscape(ref int p)
	{
		uint32 cp = Try!(ReadHex4(p));
		if (cp >= 0xD800 && cp <= 0xDFFF)
		{
			if (cp >= 0xDC00)
				return .Err(Fail(.InvalidSurrogate, scope $"The escape `{View(p, 6)}` is a low surrogate without a high surrogate before it (a lone surrogate is not Unicode text)", p, 6));
			// A high surrogate: an escaped low one must follow
			if (!AvailN(p + 6, 2) || mData[p + 6] != '\\' || mData[p + 7] != 'u')
				return .Err(Fail(.InvalidSurrogate, scope $"The escape `{View(p, 6)}` is a high surrogate without an escaped low surrogate (`\\uDC00`-`\\uDFFF`) after it (a lone surrogate is not Unicode text)", p, 6));
			uint32 low = Try!(ReadHex4(p + 6));
			if (low < 0xDC00 || low > 0xDFFF)
				return .Err(Fail(.InvalidSurrogate, scope $"The escape `{View(p, 6)}` is a high surrogate followed by `{View(p + 6, 6)}`, which is not a low surrogate (`\\uDC00`-`\\uDFFF`)", p, 12));
			cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
			p += 12;
		}
		else
			p += 6;
		char8[4] utf8 = ?;
		int count = JsonChar.EncodeUtf8(&utf8, cp);
		mStringBuffer.Append(&utf8, count);
		return .Ok;
	}

	/// The value of the four hex digits of the `\u` escape at `p`.
	Result<uint32, JsonFailure> ReadHex4(int p)
	{
		uint32 value = 0;
		for (int i < 4)
		{
			int q = p + 2 + i;
			if (!Avail(q))
				return .Err(Fail(.InvalidEscape, "The escape `\\u` needs four hex digits, found the end of the input", p, q - p));
			uint8 digit = JsonChar.HexDigitValue(mData[q]);
			if (digit == 255)
			{
				let message = scope String();
				message.Append("The escape `\\u` needs four hex digits, found ");
				JsonChar.AppendCharDescription(message, mData, q, mEnd, let length);
				return .Err(Fail(.InvalidEscape, message, p, q + length - p));
			}
			value = (value << 4) | digit;
		}
		return value;
	}

	JsonFailure UnterminatedString(int start, int p)
	{
		return Fail(.UnterminatedString, "The input ends inside a string: expected its closing `\"`", p, 0);
	}

	JsonFailure ControlCharacter(int p)
	{
		let message = scope String();
		message.Append("The control character ");
		JsonChar.AppendCharDescription(message, mData, p, mEnd, ?);
		message.Append(" must be escaped in a string");
		return Fail(.ControlCharacterInString, message, p);
	}

	// Whitespace

	[Inline]
	void SkipSpace()
	{
		while (true)
		{
			while (mPos < mEnd && JsonChar.IsSpace(mData[mPos]))
				mPos++;
			if (mPos < mEnd || !Grow(mPos, 1))
				return;
		}
	}

	// The window

	/// Whether the byte at `pos` is available, reading more of a stream if needed.
	[Inline]
	bool Avail(int pos)
	{
		return pos < mEnd || Grow(pos, 1);
	}

	/// Whether `count` bytes from `pos` are available, reading more of a stream if needed.
	[Inline]
	bool AvailN(int pos, int count)
	{
		return pos + count <= mEnd || Grow(pos, count);
	}

	/// Asks the cursor for more input, keeping the current token, and moves the token's views if the
	/// window moved. @return Whether `count` bytes from `pos` are now available. Inlined so that for
	/// in-memory input (Fill is an inlined `false`) it folds to a compare.
	[Inline]
	bool Grow(int pos, int count)
	{
		char8* oldData = mData;
		int oldBase = mBase;
		int oldEnd = mEnd;
		bool grew = mCursor.Fill(ref mData, ref mBase, ref mEnd, Math.Min(Math.Min(mRetain, mPos), pos), pos, count);
		if (mData != oldData)
			RebaseViews(oldData, oldBase, oldEnd);
		if (!grew)
		{
			if (mCursor.HasInputError)
				mInputFailed = true;
			return false;
		}
		return pos + count <= mEnd;
	}

	void RebaseViews(char8* oldData, int oldBase, int oldEnd)
	{
		char8* low = oldData + oldBase;
		char8* high = oldData + oldEnd;
		Rebase(ref mValue, low, high, oldData);
		Rebase(ref mRaw, low, high, oldData);
	}

	/// Moves a view of the old window to the same offsets in the new one.
	void Rebase(ref StringView view, char8* low, char8* high, char8* oldData)
	{
		if (view.Ptr >= low && view.Ptr < high)
			view = .(mData + (view.Ptr - oldData), view.Length);
	}

	[Inline]
	StringView View(int start, int length)
	{
		return StringView(mData + start, length);
	}

	// Errors

	/// Records the error (Next reports it) and returns the token internal methods fail with. After the
	/// input itself failed (a stream's I/O, encoding or size error), that error is reported instead: the
	/// reader's own came from running into the end of what could be read.
	JsonFailure Fail(JsonErrorKind kind, StringView message, int offset, int length = 1)
	{
		if (mInputFailed && mCursor.TryGetInputError(let inputError))
			mError = inputError;
		else
		{
			int line = 0;
			int column = 0;
			if (mCursor.Locate(offset, var l, var c))
			{
				line = l;
				column = c;
			}
			mError = JsonParseError(kind, message, line, column, offset, length);
		}
		if (!mConfig.SourceName.IsEmpty)
			mError.SetSource(mConfig.SourceName);
		return .();
	}

	/// The input ended where more was needed, at mPos.
	JsonFailure EndOfInput(StringView message)
	{
		return Fail(.UnexpectedEndOfInput, message, mPos, 0);
	}

	/// "Expected X, found Y" at mPos (which must be available).
	JsonFailure Unexpected(JsonErrorKind kind, StringView expected)
	{
		let message = scope String();
		message.Append("Expected ");
		message.Append(expected);
		message.Append(", found ");
		JsonChar.AppendCharDescription(message, mData, mPos, mEnd, let length);
		return Fail(kind, message, mPos, length);
	}

	// Values of the current token

	/// The current number token's double (correctly rounded); false if it overflows (the value is ±∞).
	public bool GetDouble(out double value)
	{
		if (mNumberKind == .Integer && mInteger != 0)
		{
			// Exact below 2^53; beyond, the conversion rounds as the text would
			if (mInteger > -((int64)1 << 53) && mInteger < ((int64)1 << 53))
			{
				value = (double)mInteger;
				return true;
			}
		}
		return JsonNumber.ParseDouble(mRaw, out value);
	}

	/// Locates `offset` for an error made outside the reader (a value conversion).
	public JsonParseError MakeError(JsonErrorKind kind, StringView message, int offset, int length)
	{
		int line = 0;
		int column = 0;
		if (mCursor.Locate(offset, var l, var c))
		{
			line = l;
			column = c;
		}
		var error = JsonParseError(kind, message, line, column, offset, length);
		if (!mConfig.SourceName.IsEmpty)
			error.SetSource(mConfig.SourceName);
		return error;
	}
}
