using System;
using internal JsonBeef;

namespace JsonBeef;

/// JSON5 1.0.0 (JsonDialect.Json5; spec-reference §12.2): its whitespace, strings, member names and
/// numbers. The structure, comments and trailing commas are the JSON reader's. Tokens are reported as
/// JSON's: a string's decoded text, a name's, and a number's JSON text in mValue (normalized when it
/// is written otherwise: mEscaped then says so), what was written in mRaw.
extension JsonReaderCore<TCursor> where TCursor : IJsonCursor
{
	/// JSON5: past the whitespace JSON does not have at mPos (and the JSON whitespace and comments after
	/// it). Called where JSON would report the byte as unexpected, so that JSON reading pays nothing.
	/// @return Whether anything was skipped: the caller then reads again.
	bool SkipJson5Space()
	{
		if (!mJson5 || !Avail(mPos))
			return false;
		int length = Json5SpaceLength(mPos);
		if (length == 0)
			return false;
		while (length > 0)
		{
			mPos += length;
			SkipSpace();
			if (!Avail(mPos))
				break;
			length = Json5SpaceLength(mPos);
		}
		return true;
	}

	/// The length of the JSON5 whitespace beyond JSON's at `p` (VT, FF, and the Zs spaces NBSP, U+1680,
	/// U+2000-U+200A, U+202F, U+205F, U+3000, with U+2028, U+2029 and U+FEFF), or 0.
	int Json5SpaceLength(int p)
	{
		uint8 b = (uint8)mData[p];
		if (b == 0x0B || b == 0x0C)
			return 1;
		if (b == 0xC2)
			return (AvailN(p, 2) && (uint8)mData[p + 1] == 0xA0) ? 2 : 0;
		if (b != 0xE1 && b != 0xE2 && b != 0xE3 && b != 0xEF)
			return 0;
		if (!AvailN(p, 3))
			return 0;
		uint8 b1 = (uint8)mData[p + 1];
		uint8 b2 = (uint8)mData[p + 2];
		switch (b)
		{
		case 0xE1:
			return (b1 == 0x9A && b2 == 0x80) ? 3 : 0;
		case 0xE2:
			if (b1 == 0x80 && ((b2 >= 0x80 && b2 <= 0x8A) || b2 == 0xA8 || b2 == 0xA9 || b2 == 0xAF))
				return 3;
			return (b1 == 0x81 && b2 == 0x9F) ? 3 : 0;
		case 0xE3:
			return (b1 == 0x80 && b2 == 0x80) ? 3 : 0;
		default:
			return (b1 == 0xBB && b2 == 0xBF) ? 3 : 0;
		}
	}

	// Strings

	/// A JSON5 string value or quoted member name (`isName`), in double or single quotes, from its
	/// opening quote at mPos.
	Result<JsonToken, JsonFailure> ReadString5(bool isName)
	{
		int start = mPos;
		Retain(start);
		mStringStart = start;
		mStringIsName = isName;
		char8 quote = mData[start];
		int p = start + 1;
		bool decode = false;
		// The plain run: to the closing quote, a backslash, a line break or an ill-formed sequence
		while (true)
		{
			if (!Avail(p))
				return .Err(UnterminatedString(start, p));
			char8 c = mData[p];
			if (c == quote)
				break;
			if (c == '\\')
			{
				decode = true;
				break;
			}
			if (c == '\n' || c == '\r')
				return .Err(LineBreakInString(p));
			if ((uint8)c >= 0x80)
			{
				int length = Utf8At(p);
				if (length == 0)
				{
					if (mConfig.InvalidUtf8 != .Replace)
						return .Err(InvalidUtf8(p));
					decode = true;
					break;
				}
				p += length;
				continue;
			}
			// Other control characters, TAB included, may be written raw in JSON5
			p++;
		}
		if (decode)
		{
			Try!(DecodeString5(start, quote, ref p));
			mValue = mStringBuffer;
			mRaw = View(start + 1, p - start - 1);
			mEscaped = true;
		}
		else
		{
			mValue = View(start + 1, p - start - 1);
			mRaw = mValue;
			mEscaped = false;
		}
		if (mConfig.MaxStringBytes > 0 && mValue.Length > mConfig.MaxStringBytes)
			return .Err(Fail(.ResourceLimitExceeded, scope $"The string ({mValue.Length} bytes) exceeds MaxStringBytes ({mConfig.MaxStringBytes})", start, p + 1 - start));
		mToken = isName ? .PropertyName : .String;
		mTokenStart = start;
		mTokenEnd = p + 1;
		mPos = p + 1;
		mState = isName ? .Colon : .AfterValue;
		mStringStart = -1;
		return .Ok(mToken);
	}

	/// Decodes a JSON5 string into mStringBuffer, from its opening quote at `start`; `p` is at its first
	/// backslash or ill-formed byte and ends at its closing quote. JSON5's escapes (J5 §5.1): JSON's,
	/// `\'`, `\v`, `\0` (not before a digit), `\xHH`, line continuations (`\` and a line terminator,
	/// which add nothing), and `\` before any other character stands for it, except the digits 1-9.
	Result<void, JsonFailure> DecodeString5(int start, char8 quote, ref int p)
	{
		mStringBuffer.Clear();
		mStringBuffer.Append(mData + start + 1, p - start - 1);
		while (true)
		{
			if (!Avail(p))
				return .Err(UnterminatedString(start, p));
			char8 c = mData[p];
			if (c == quote)
				return .Ok;
			if (c == '\n' || c == '\r')
				return .Err(LineBreakInString(p));
			if ((uint8)c >= 0x80)
			{
				int length = Utf8At(p);
				if (length == 0)
				{
					if (mConfig.InvalidUtf8 != .Replace)
						return .Err(InvalidUtf8(p));
					if (p + 4 > mEnd)
						Grow(p, 4);
					mStringBuffer.Append("\u{FFFD}");
					p += JsonChar.MaximalSubpartLength(mData, p, mEnd);
					continue;
				}
				mStringBuffer.Append(mData + p, length);
				p += length;
				continue;
			}
			if (c != '\\')
			{
				mStringBuffer.Append(c);
				p++;
				continue;
			}
			if (!Avail(p + 1))
				return .Err(UnterminatedString(start, p + 1));
			char8 e = mData[p + 1];
			switch (e)
			{
			case 'b': mStringBuffer.Append('\b'); p += 2;
			case 'f': mStringBuffer.Append('\f'); p += 2;
			case 'n': mStringBuffer.Append('\n'); p += 2;
			case 'r': mStringBuffer.Append('\r'); p += 2;
			case 't': mStringBuffer.Append('\t'); p += 2;
			case 'v': mStringBuffer.Append('\v'); p += 2;
			case '0':
				if (Avail(p + 2) && JsonChar.IsDigit(mData[p + 2]))
					return .Err(Fail(.InvalidEscape, "The escape `\\0` cannot be followed by a digit in JSON5 (no octal escapes)", p, 3));
				mStringBuffer.Append('\0');
				p += 2;
			case '1', '2', '3', '4', '5', '6', '7', '8', '9':
				return .Err(Fail(.InvalidEscape, scope $"The escape `\\{e}` is not JSON5 (no octal or decimal escapes)", p, 2));
			case 'x':
				int value = 0;
				for (int i < 2)
				{
					uint8 digit = Avail(p + 2 + i) ? JsonChar.HexDigitValue(mData[p + 2 + i]) : 255;
					if (digit == 255)
						return .Err(Fail(.InvalidEscape, "The escape `\\x` needs two hex digits", p, 2 + i));
					value = (value << 4) | digit;
				}
				char8[4] utf8 = ?;
				mStringBuffer.Append(&utf8, JsonChar.EncodeUtf8(&utf8, (uint32)value));
				p += 4;
			case 'u':
				char8[4] decoded = ?;
				char8* dest = &decoded;
				Try!(DecodeUnicodeEscape(ref p, ref dest));
				mStringBuffer.Append(&decoded, dest - (char8*)&decoded);
			case '\n':
				p += 2;
			case '\r':
				p += 2;
				if (Avail(p) && mData[p] == '\n')
					p++;
			default:
				if ((uint8)e >= 0x80)
				{
					int length = Utf8At(p + 1);
					if (length == 0)
						return .Err(InvalidUtf8(p + 1));
					// U+2028 and U+2029 continue the line; any other character stands for itself
					bool lineSeparator = length == 3 && (uint8)e == 0xE2 && (uint8)mData[p + 2] == 0x80 && ((uint8)mData[p + 3] & 0xFE) == 0xA8;
					if (!lineSeparator)
						mStringBuffer.Append(mData + p + 1, length);
					p += 1 + length;
				}
				else
				{
					// `\'`, `\"`, `\\`, `\/` and any other character: the character itself
					mStringBuffer.Append(e);
					p += 2;
				}
			}
		}
	}

	JsonFailure LineBreakInString(int p)
	{
		return Fail(.ControlCharacterInString, "A line break cannot be in a JSON5 string: escape it (`\\n`) or continue the line with `\\`", p);
	}

	// Member names

	/// A JSON5 member name at mPos: a string in either quotes, or an identifier.
	Result<JsonToken, JsonFailure> ReadName5()
	{
		char8 c = mData[mPos];
		if (c == '"' || c == '\'')
			return ReadString5(true);
		return ReadIdentifier();
	}

	/// An ECMAScript 5.1 IdentifierName as a member name (J5 §3): `$`, `_`, a letter or a `\uXXXX`
	/// escape of one first, then also digits, combining marks, connector punctuation, ZWNJ and ZWJ.
	/// Reserved words are names like any other (`{while: 1}`).
	Result<JsonToken, JsonFailure> ReadIdentifier()
	{
		int start = mPos;
		Retain(start);
		int p = start;
		bool escaped = false;
		bool first = true;
		while (Avail(p))
		{
			char8 c = mData[p];
			uint32 cp;
			int length;
			if (c == '\\')
			{
				if (!AvailN(p, 2) || mData[p + 1] != 'u')
					return .Err(Fail(.InvalidEscape, "An unquoted member name can only have `\\uXXXX` escapes", p, 2));
				cp = Try!(ReadHex4(p));
				length = 6;
			}
			else if ((uint8)c < 0x80)
			{
				cp = (uint32)c;
				length = 1;
			}
			else
			{
				length = Utf8At(p);
				if (length == 0)
					return .Err(InvalidUtf8(p));
				cp = (uint32)JsonChar.Decode(mData, p, ?);
			}
			if (!(first ? IsIdentifierStart(cp) : IsIdentifierPart(cp)))
			{
				if (c == '\\')
					return .Err(Fail(.InvalidEscape, scope $"The escape `{View(p, 6)}` is not a character an unquoted member name can have", p, 6));
				break;
			}
			if (c == '\\')
			{
				if (!escaped)
				{
					mStringBuffer.Clear();
					mStringBuffer.Append(mData + start, p - start);
					escaped = true;
				}
				char8[4] utf8 = ?;
				mStringBuffer.Append(&utf8, JsonChar.EncodeUtf8(&utf8, cp));
			}
			else if (escaped)
				mStringBuffer.Append(mData + p, length);
			p += length;
			first = false;
		}
		if (first)
		{
			// JSON5's other whitespace before the name: the state reads again after it
			if (p == start && SkipJson5Space())
				return ReadNext();
			return .Err(Unexpected(.InvalidStructure, "a member name (a string, or in JSON5 an identifier) or `}`"));
		}
		mRaw = View(start, p - start);
		mValue = escaped ? (StringView)mStringBuffer : mRaw;
		mEscaped = escaped;
		if (mConfig.MaxStringBytes > 0 && mValue.Length > mConfig.MaxStringBytes)
			return .Err(Fail(.ResourceLimitExceeded, scope $"The name ({mValue.Length} bytes) exceeds MaxStringBytes ({mConfig.MaxStringBytes})", start, p - start));
		mToken = .PropertyName;
		mTokenStart = start;
		mTokenEnd = p;
		mPos = p;
		mState = .Colon;
		return .Ok(.PropertyName);
	}

	static bool IsIdentifierStart(uint32 cp)
	{
		if (cp < 0x80)
		{
			char8 c = (char8)cp;
			return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '$' || c == '_';
		}
		return JsonIdentifierTables.Contains(JsonIdentifierTables.sStart, cp);
	}

	static bool IsIdentifierPart(uint32 cp)
	{
		if (cp < 0x80)
		{
			char8 c = (char8)cp;
			return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '$' || c == '_';
		}
		// ZWNJ and ZWJ
		return cp == 0x200C || cp == 0x200D || JsonIdentifierTables.Contains(JsonIdentifierTables.sPart, cp);
	}

	// Numbers

	/// A JSON5 number at mPos (J5 §6): an optional sign, then `Infinity`, `NaN`, a hexadecimal integer
	/// (`0x1F`, any length) or a decimal one with optional leading or trailing point (`.5`, `5.`, no
	/// leading zeros), with JSON's exponent. Reported as the JSON number it is.
	Result<JsonToken, JsonFailure> ReadNumber5()
	{
		int start = mPos;
		Retain(start);
		int p = start;
		bool negative = false;
		if (mData[p] == '+' || mData[p] == '-')
		{
			negative = mData[p] == '-';
			p++;
		}
		if (!Avail(p))
			return .Err(NumberError("Expected a digit, `.`, `Infinity` or `NaN` after the sign", p));
		char8 c = mData[p];
		bool normalized = false;
		mStringBuffer.Clear();
		if (c == 'I' || c == 'N')
		{
			int end = WordEnd(p);
			StringView word = View(p, end - p);
			if (word != "Infinity" && word != "NaN")
				return .Err(Fail(.InvalidNumber, scope $"Invalid number `{View(start, end - start)}` (JSON5's non-finite numbers are `Infinity` and `NaN`, with an optional sign)", start, end - start));
			p = end;
			mNumberKind = .NonFinite;
		}
		else if (c == '0' && Avail(p + 1) && (mData[p + 1] == 'x' || mData[p + 1] == 'X'))
		{
			// Hexadecimal: an integer of any length
			p += 2;
			int digitsStart = p;
			uint64 magnitude = 0;
			bool big = false;
			while (Avail(p) && JsonChar.HexDigitValue(mData[p]) != 255)
			{
				if (magnitude >> 60 != 0)
					big = true;
				magnitude = (magnitude << 4) | JsonChar.HexDigitValue(mData[p]);
				p++;
			}
			if (p == digitsStart)
				return .Err(NumberError("Expected a hex digit after `0x`", p));
			if (negative)
				mStringBuffer.Append('-');
			if (big)
			{
				JsonNumber.AppendHexAsDecimal(mStringBuffer, View(digitsStart, p - digitsStart));
				mNumberKind = .BigInteger;
			}
			else
			{
				magnitude.ToString(mStringBuffer);
				if (negative)
				{
					if (magnitude <= (uint64)int64.MaxValue + 1)
					{
						mNumberKind = .Integer;
						mInteger = magnitude == 0 ? 0 : -(int64)(magnitude - 1) - 1;
					}
					else
						mNumberKind = .BigInteger;
				}
				else
				{
					mNumberKind = magnitude <= (uint64)int64.MaxValue ? .Integer : .UInteger;
					mInteger = (int64)magnitude;
				}
			}
			normalized = true;
		}
		else
		{
			// Decimal, with JSON's grammar but for the optional integer or fraction digits
			int intStart = p;
			if (c == '0')
			{
				p++;
				if (Avail(p) && JsonChar.IsDigit(mData[p]))
					return .Err(Fail(.InvalidNumber, "A number cannot have a leading zero (`01`), in JSON5 either: write `1`, or `0.1` for a fraction", start, p + 1 - start));
			}
			else
				p = SkipDigits(p);
			int intEnd = p;
			bool isFloat = false;
			int fracStart = -1;
			int fracEnd = -1;
			if (Avail(p) && mData[p] == '.')
			{
				isFloat = true;
				p++;
				fracStart = p;
				p = SkipDigits(p);
				fracEnd = p;
			}
			if (intEnd == intStart && (fracStart < 0 || fracEnd == fracStart))
				return .Err(NumberError("Expected a digit", fracStart >= 0 ? p : intStart));
			int expStart = p;
			if (Avail(p) && (mData[p] == 'e' || mData[p] == 'E'))
			{
				isFloat = true;
				p++;
				if (Avail(p) && (mData[p] == '+' || mData[p] == '-'))
					p++;
				if (!Avail(p) || !JsonChar.IsDigit(mData[p]))
					return .Err(NumberError("Expected a digit in the exponent", p));
				p = SkipDigits(p);
			}
			// The JSON text: a sign only if `-`, `0` for missing integer digits, `.0` for a bare point
			normalized = mData[start] == '+' || intEnd == intStart || (fracStart >= 0 && fracEnd == fracStart);
			if (negative)
				mStringBuffer.Append('-');
			if (intEnd == intStart)
				mStringBuffer.Append('0');
			else
				mStringBuffer.Append(mData + intStart, intEnd - intStart);
			if (fracStart >= 0)
			{
				mStringBuffer.Append('.');
				if (fracEnd == fracStart)
					mStringBuffer.Append('0');
				else
					mStringBuffer.Append(mData + fracStart, fracEnd - fracStart);
			}
			mStringBuffer.Append(mData + expStart, p - expStart);
			if (isFloat)
			{
				mNumberKind = .Float;
				mFloatExact = false;
			}
			else
			{
				StringView text = mStringBuffer;
				mNumberKind = JsonNumber.Classify(text);
				if (mNumberKind == .Integer)
					JsonNumber.TryParseInt64(text, out mInteger);
				else if (mNumberKind == .UInteger)
				{
					JsonNumber.TryParseUInt64(text, let unsigned);
					mInteger = (int64)unsigned;
				}
			}
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
		mToken = .Number;
		mTokenStart = start;
		mTokenEnd = p;
		mRaw = View(start, length);
		mValue = (normalized && mNumberKind != .NonFinite) ? (StringView)mStringBuffer : mRaw;
		mEscaped = normalized && mNumberKind != .NonFinite;
		mPos = p;
		mState = .AfterValue;
		return .Ok(.Number);
	}
}
