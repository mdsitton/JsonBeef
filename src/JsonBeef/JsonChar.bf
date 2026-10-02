using System;
using internal JsonBeef;

namespace JsonBeef;

/// 16 comparison results (0 or 1 per byte): a vector LLVM keeps in an SSE register.
[UnderlyingArray(typeof(bool), 16, true)]
internal struct JsonMask16
{
	// The layout as two words (without fields the compiler crashes emitting debug info for a local)
	public uint64 mLow;
	public uint64 mHigh;

	[Intrinsic("or")]
	public static extern JsonMask16 operator|(JsonMask16 a, JsonMask16 b);
}

/// 16 bytes as signed lanes (SSE2's byte compare is signed: bytes ≥ 0x80 are below 0x20 too, which
/// the string scan wants), compared lane by lane with pcmpeqb/pcmpgtb. Beef reaches no movemask or
/// trailing-zero count, so the mask is read back as two words (phase 3 measured this against SWAR).
[UnderlyingArray(typeof(int8), 16, true)]
internal struct JsonBytes16
{
	public int64 mLow;
	public int64 mHigh;

	[Intrinsic("eq")]
	public static extern JsonMask16 operator==(JsonBytes16 a, JsonBytes16 b);
	[Intrinsic("lt")]
	public static extern JsonMask16 operator<(JsonBytes16 a, JsonBytes16 b);

	/// 16 copies of `value`.
	[Inline]
	public static JsonBytes16 Splat(uint8 value)
	{
		uint64[2] words = .((uint64)value * 0x0101010101010101UL, (uint64)value * 0x0101010101010101UL);
		JsonBytes16 result = ?;
		Internal.MemCpy(&result, &words, 16);
		return result;
	}

	/// The 16 bytes at `p` (unaligned).
	[Inline]
	public static JsonBytes16 Load(char8* p)
	{
		JsonBytes16 result = ?;
		Internal.MemCpy(&result, p, 16);
		return result;
	}
}

/// Byte-level helpers shared by the reader, the cursors and the writers: word-at-a-time (SWAR) tests,
/// UTF-8 validation and decoding, line and column counting, hex digits. Ported from XmlBeef's XmlChar and
/// KdlBeef's KdlChar with JSON's rules: only UTF-8 well-formedness is checked up front (every code point
/// may appear in a string; what may appear outside strings is the grammar's business).
internal static class JsonChar
{
	public const uint64 cOnes = 0x0101010101010101UL;
	public const uint64 cHigh = 0x8080808080808080UL;

	/// Character classes of the bytes that may start a token, for the reader's dispatch.
	public enum ByteClass : uint8
	{
		/// Anything that cannot start a token or be whitespace.
		Other,
		/// Space, tab, LF, CR.
		Space,
		/// `"`
		Quote,
		/// `-` and `0`-`9`
		Number,
		/// `{` `}` `[` `]` `,` `:`
		Punct,
		/// `t` `f` `n`
		Literal,
		/// `/`: a comment with JsonReadConfig.Comments
		Slash
	}

	/// The class of every byte.
	public static ByteClass[256] sByteClass = BuildByteClasses();

	static ByteClass[256] BuildByteClasses()
	{
		ByteClass[256] classes = .();
		classes[(int)' '] = .Space;
		classes[(int)'\t'] = .Space;
		classes[(int)'\n'] = .Space;
		classes[(int)'\r'] = .Space;
		classes[(int)'"'] = .Quote;
		classes[(int)'-'] = .Number;
		for (int c = (int)'0'; c <= (int)'9'; c++)
			classes[c] = .Number;
		classes[(int)'{'] = .Punct;
		classes[(int)'}'] = .Punct;
		classes[(int)'['] = .Punct;
		classes[(int)']'] = .Punct;
		classes[(int)','] = .Punct;
		classes[(int)':'] = .Punct;
		classes[(int)'t'] = .Literal;
		classes[(int)'f'] = .Literal;
		classes[(int)'n'] = .Literal;
		classes[(int)'/'] = .Slash;
		return classes;
	}

	/// @brief Whether `c` is JSON whitespace: space, tab, LF or CR (RFC 8259 §2).
	[Inline]
	public static bool IsSpace(char8 c)
	{
		return c == ' ' || c == '\n' || c == '\r' || c == '\t';
	}

	[Inline]
	public static bool IsDigit(char8 c)
	{
		return (uint8)c - (uint8)'0' <= 9;
	}

	[Inline]
	public static uint64 Load64(char8* p)
	{
		uint64 word = ?;
		Internal.MemCpy(&word, p, 8);
		return word;
	}

	[Inline]
	public static uint32 Load32(char8* p)
	{
		uint32 word = ?;
		Internal.MemCpy(&word, p, 4);
		return word;
	}

	/// @brief The high bit of each zero byte of `x`, exactly.
	[Inline]
	public static uint64 ZeroBytes(uint64 x)
	{
		const uint64 low7 = 0x7F7F7F7F7F7F7F7FUL;
		return ~(((x & low7) + low7) | x | low7);
	}

	/// @brief The high bit of each byte of `word` that equals `c`, exactly.
	[Inline]
	public static uint64 BytesEqual(uint64 word, uint8 c)
	{
		return ZeroBytes(word ^ ((uint64)c * cOnes));
	}

	/// @brief The high bit of each byte of `word` below 0x20, exactly (bytes ≥ 0x80 excepted).
	[Inline]
	public static uint64 BytesBelowSpace(uint64 word)
	{
		// Adding 0x60 to a byte below 0x80 sets its high bit when it is at least 0x20
		return ~((word & ~cHigh) + 0x6060606060606060UL) & ~word & cHigh;
	}

	/// @brief The high bit of each byte that ends a string's plain run: `"`, `\` or a byte below 0x20
	/// (a control character, an error). Bytes ≥ 0x80 are UTF-8 validated up front and pass.
	[Inline]
	public static uint64 StringStops(uint64 word)
	{
		return BytesEqual(word, (uint8)'"') | BytesEqual(word, (uint8)'\\') | BytesBelowSpace(word);
	}

	/// @brief Whether the 8 bytes of `word` are all ASCII digits.
	[Inline]
	public static bool AllDigits(uint64 word)
	{
		return ((word & 0xF0F0F0F0F0F0F0F0UL) | (((word + 0x0606060606060606UL) & 0xF0F0F0F0F0F0F0F0UL) >> 4)) == 0x3333333333333333UL;
	}

	/// @brief The value of 8 ASCII digits loaded little-endian (the first digit in the lowest byte):
	/// pairs, then quads, then the whole, in three multiplies (simdjson's parse_eight_digits_unrolled).
	[Inline]
	public static uint64 ParseEightDigits(uint64 word)
	{
		uint64 value = word - 0x3030303030303030UL;
		value = (value * 10) + (value >> 8);
		value = (((value & 0x000000FF000000FFUL) * (100 + (1000000UL << 32))) +
			(((value >> 16) & 0x000000FF000000FFUL) * (1 + (10000UL << 32)))) >> 32;
		return value & 0xFFFFFFFFUL;
	}

	/// @brief The high bit of each byte of `word` that is not JSON whitespace (space, tab, LF, CR).
	[Inline]
	public static uint64 NonSpaceBytes(uint64 word)
	{
		return ~(BytesEqual(word, (uint8)' ') | BytesEqual(word, (uint8)'\n') | BytesEqual(word, (uint8)'\r') | BytesEqual(word, (uint8)'\t')) & cHigh;
	}

	/// @brief The index (0-15) of the first byte of `p[0 ..< 16]` that ends a string's plain ASCII run
	/// (`"`, `\`, a control character or a non-ASCII byte), or 16 when there is none: one 16-byte vector
	/// compare (SSE2, no movemask needed until a stop is found).
	[Inline]
	public static int FirstStringStop16(char8* p)
	{
		let bytes = JsonBytes16.Load(p);
		var mask = (bytes == JsonBytes16.Splat((uint8)'"')) | (bytes == JsonBytes16.Splat((uint8)'\\')) | (bytes < JsonBytes16.Splat((uint8)' '));
		uint64* words = (uint64*)&mask;
		uint64 low = words[0];
		uint64 high = words[1];
		if ((low | high) == 0)
			return 16;
		// Lanes are 0 or 1: moved to each byte's high bit for FirstByte
		if (low != 0)
			return FirstByte(low << 7);
		return 8 + FirstByte(high << 7);
	}

	/// @brief The index (0-7) of the lowest byte whose high bit is set in `mask` (which must be nonzero
	/// and have no other bits): the bytes below it, counted (Beef has no trailing-zero count).
	[Inline]
	public static int FirstByte(uint64 mask)
	{
		return CountHighBits(((mask & (~mask + 1)) - 1) & cHigh);
	}

	/// @brief The number of bytes of `mask` whose high bit is set (no other bits may be).
	[Inline]
	public static int CountHighBits(uint64 mask)
	{
		return (int)(((mask >> 7) * cOnes) >> 56);
	}

	/// Nonzero when `word` has a byte below 0x0E (exact as to whether there is one).
	[Inline]
	public static uint64 BytesBelow0E(uint64 word)
	{
		return (word - 0x0E0E0E0E0E0E0E0EUL) & ~word & cHigh;
	}

	/// @brief Whether `a[0 ..< length]` equals `b[0 ..< length]`: word compares (overlapping at the end).
	[Inline]
	public static bool EqualBytes(char8* a, char8* b, int length)
	{
		if (length >= 8)
		{
			int i = 0;
			while (i + 8 < length)
			{
				if (Load64(a + i) != Load64(b + i))
					return false;
				i += 8;
			}
			return Load64(a + length - 8) == Load64(b + length - 8);
		}
		if (length >= 4)
			return Load32(a) == Load32(b) && Load32(a + length - 4) == Load32(b + length - 4);
		for (int i < length)
		{
			if (a[i] != b[i])
				return false;
		}
		return true;
	}

	/// @brief The length of the UTF-8 sequence that starts with `leadChar`: 1-4, or 0 for a byte that
	/// cannot start one.
	[Inline]
	public static int Utf8SequenceLength(char8 leadChar)
	{
		uint8 lead = (uint8)leadChar;
		if (lead < 0x80) return 1;
		if ((lead & 0xE0) == 0xC0) return 2;
		if ((lead & 0xF0) == 0xE0) return 3;
		if ((lead & 0xF8) == 0xF0) return 4;
		return 0;
	}

	/// @brief Decode the code point at `text[pos]` from input already checked as UTF-8.
	/// @param text The bytes.
	/// @param pos Byte offset of the lead byte.
	/// @param length Receives the sequence length in bytes.
	/// @return The decoded code point (U+FFFD for a byte that starts no sequence, with length 1).
	public static char32 Decode(char8* text, int pos, out int length)
	{
		uint8* data = (uint8*)text;
		uint8 b0 = data[pos];
		if (b0 < 0x80)
		{
			length = 1;
			return (char32)b0;
		}
		length = Utf8SequenceLength((char8)b0);
		switch (length)
		{
		case 2:
			return (char32)(((uint32)(b0 & 0x1F) << 6) | (uint32)(data[pos + 1] & 0x3F));
		case 3:
			return (char32)(((uint32)(b0 & 0x0F) << 12) | ((uint32)(data[pos + 1] & 0x3F) << 6) | (uint32)(data[pos + 2] & 0x3F));
		case 4:
			return (char32)(((uint32)(b0 & 0x07) << 18) | ((uint32)(data[pos + 1] & 0x3F) << 12) |
				((uint32)(data[pos + 2] & 0x3F) << 6) | (uint32)(data[pos + 3] & 0x3F));
		default:
			length = 1;
			return (char32)0xFFFD;
		}
	}

	/// @brief Encode a code point as UTF-8 at `dst` (room for 4 bytes). @return The bytes written.
	[Inline]
	public static int EncodeUtf8(char8* dst, uint32 cp)
	{
		if (cp < 0x80)
		{
			dst[0] = (char8)cp;
			return 1;
		}
		if (cp < 0x800)
		{
			dst[0] = (char8)(0xC0 | (cp >> 6));
			dst[1] = (char8)(0x80 | (cp & 0x3F));
			return 2;
		}
		if (cp < 0x10000)
		{
			dst[0] = (char8)(0xE0 | (cp >> 12));
			dst[1] = (char8)(0x80 | ((cp >> 6) & 0x3F));
			dst[2] = (char8)(0x80 | (cp & 0x3F));
			return 3;
		}
		dst[0] = (char8)(0xF0 | (cp >> 18));
		dst[1] = (char8)(0x80 | ((cp >> 12) & 0x3F));
		dst[2] = (char8)(0x80 | ((cp >> 6) & 0x3F));
		dst[3] = (char8)(0x80 | (cp & 0x3F));
		return 4;
	}

	/// @brief Encode a code point as UTF-8 and append it to `result`.
	public static void EncodeUtf8(String result, uint32 cp)
	{
		char8[4] buffer = ?;
		int count = EncodeUtf8(&buffer, cp);
		result.Append(&buffer, count);
	}

	/// @brief The value of a hex digit, or 255 if `c` is not one.
	[Inline]
	public static uint8 HexDigitValue(char8 c)
	{
		uint32 ci = (uint8)c;
		uint32 result = ci - (uint32)'0';
		if (result <= 9)
			return (uint8)result;
		result = (ci | 0x20) - (uint32)'a';
		if (result <= 5)
			return (uint8)(result + 10);
		return 255;
	}

	/// @brief Whether the input starts with a UTF-8 byte order mark.
	public static bool StartsWithBom(char8* data, int length)
	{
		return length >= 3 && (uint8)data[0] == 0xEF && (uint8)data[1] == 0xBB && (uint8)data[2] == 0xBF;
	}

	/// @brief The name of the UTF-16 or UTF-32 encoding the first bytes of an input show (a byte order
	/// mark, or the zero bytes of ASCII characters in 16- or 32-bit units: RFC 4627 §3), or "" when
	/// they show none. JSON must be UTF-8 (RFC 8259 §8.1), so such input is rejected with this name.
	/// @param data The input's first bytes.
	/// @param length How many there are (up to 4 are looked at).
	public static StringView DetectWideEncoding(char8* data, int length)
	{
		uint8* b = (uint8*)data;
		if (length >= 4 && b[0] == 0 && b[1] == 0 && b[2] == 0xFE && b[3] == 0xFF)
			return "UTF-32BE";
		if (length >= 4 && b[0] == 0xFF && b[1] == 0xFE && b[2] == 0 && b[3] == 0)
			return "UTF-32LE";
		if (length >= 2 && b[0] == 0xFE && b[1] == 0xFF)
			return "UTF-16BE";
		if (length >= 2 && b[0] == 0xFF && b[1] == 0xFE)
			return "UTF-16LE";
		if (length >= 4)
		{
			if (b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] != 0)
				return "UTF-32BE";
			if (b[0] != 0 && b[1] == 0 && b[2] == 0 && b[3] == 0)
				return "UTF-32LE";
			if (b[0] == 0 && b[1] != 0 && b[2] == 0 && b[3] != 0)
				return "UTF-16BE";
			if (b[0] != 0 && b[1] == 0 && b[2] != 0 && b[3] == 0)
				return "UTF-16LE";
		}
		return "";
	}

	/// @brief Find the first ill-formed UTF-8 sequence in `text[from ..< to]` (Unicode §3.9 table 3-7:
	/// overlongs, encoded surrogates and code points above U+10FFFF included). A sequence cut by `to`
	/// is an error: streams pass only complete sequences (`CompleteSequencesEnd`) until their input
	/// ends. ASCII is skipped 32 and 8 bytes at a time.
	/// @param text The input.
	/// @param from The first byte to check.
	/// @param to The end of the range.
	/// @param message Receives the error message.
	/// @param length Receives the length of the offending bytes.
	/// @return The offset of the first error, or -1.
	public static int FindInvalid(char8* text, int from, int to, String message, out int length)
	{
		uint8* data = (uint8*)text;
		length = 1;
		int i = from;
		while (i < to)
		{
			if (i + 32 <= to && ((Load64(text + i) | Load64(text + i + 8) | Load64(text + i + 16) | Load64(text + i + 24)) & cHigh) == 0)
			{
				i += 32;
				continue;
			}
			if (i + 8 <= to && (Load64(text + i) & cHigh) == 0)
			{
				i += 8;
				continue;
			}
			uint8 b = data[i];
			if (b < 0x80)
			{
				i++;
				continue;
			}
			int seqLen = Utf8SequenceLength((char8)b);
			if (seqLen == 0 || b == 0xC0 || b == 0xC1 || b > 0xF4)
			{
				message.AppendF("The byte 0x{:X2} is not valid UTF-8 ", b);
				if ((b & 0xC0) == 0x80)
					message.Append("(a continuation byte without a lead byte)");
				else if (b < 0xC2)
					message.Append("(it can only start an overlong encoding)");
				else
					message.Append("(it never appears in UTF-8)");
				return i;
			}
			if (i + seqLen > to)
			{
				message.AppendF("The UTF-8 sequence starting with 0x{:X2} is cut off by the end of the input", b);
				length = to - i;
				return i;
			}
			// The second byte's range depends on the lead (table 3-7): this rules out overlongs, surrogates
			// and code points above U+10FFFF
			uint8 low = 0x80;
			uint8 high = 0xBF;
			if (b == 0xE0) low = 0xA0;
			else if (b == 0xED) high = 0x9F;
			else if (b == 0xF0) low = 0x90;
			else if (b == 0xF4) high = 0x8F;
			uint8 b1 = data[i + 1];
			if (b1 < low || b1 > high)
			{
				AppendSequenceError(message, b, b1, low, high);
				length = 2;
				return i;
			}
			for (int j = 2; j < seqLen; j++)
			{
				if ((data[i + j] & 0xC0) != 0x80)
				{
					message.AppendF("The UTF-8 sequence starting with 0x{:X2} is cut off by 0x{:X2}", b, data[i + j]);
					length = j + 1;
					return i;
				}
			}
			i += seqLen;
		}
		return -1;
	}

	static void AppendSequenceError(String message, uint8 lead, uint8 next, uint8 low, uint8 high)
	{
		if ((next & 0xC0) != 0x80)
			message.AppendF("The UTF-8 sequence starting with 0x{:X2} is cut off by 0x{:X2}", lead, next);
		else if (lead == 0xED)
			message.AppendF("The bytes 0x{:X2} 0x{:X2} encode a surrogate (U+D800-U+DFFF), which is not valid UTF-8", lead, next);
		else if (lead == 0xF4)
			message.AppendF("The bytes 0x{:X2} 0x{:X2} encode a code point above U+10FFFF, which is not valid UTF-8", lead, next);
		else
			message.AppendF("The bytes 0x{:X2} 0x{:X2} are an overlong UTF-8 encoding", lead, next);
	}

	/// @brief The length of the well-formed UTF-8 sequence at `p[i]` (a lead byte ≥ 0x80) within
	/// `p[i ..< length]`, or 0 if it is ill-formed or cut off (Unicode §3.9 table 3-7).
	[Inline]
	public static int ValidSequenceLength(char8* p, int i, int length)
	{
		uint8 b = (uint8)p[i];
		if (i + 4 <= length)
		{
			// The common sequences from one word: the lead's length, the continuation bytes' tags, and the
			// second byte's range for the leads that restrict it (overlongs, surrogates, > U+10FFFF)
			uint32 word = Load32(p + i);
			if (b >= 0xC2 && b < 0xE0)
				return (word & 0xC000) == 0x8000 ? 2 : 0;
			if (b >= 0xE1 && b < 0xF0 && b != 0xED)
				return (word & 0xC0C000) == 0x808000 ? 3 : 0;
		}
		if (b < 0xC2 || b > 0xF4)
			return 0;
		int seqLength = b < 0xE0 ? 2 : b < 0xF0 ? 3 : 4;
		if (i + seqLength > length)
			return 0;
		uint8 low = 0x80;
		uint8 high = 0xBF;
		if (b == 0xE0) low = 0xA0;
		else if (b == 0xED) high = 0x9F;
		else if (b == 0xF0) low = 0x90;
		else if (b == 0xF4) high = 0x8F;
		uint8 b1 = (uint8)p[i + 1];
		if (b1 < low || b1 > high)
			return 0;
		for (int j = 2; j < seqLength; j++)
		{
			if (((uint8)p[i + j] & 0xC0) != 0x80)
				return 0;
		}
		return seqLength;
	}

	/// @brief The end of the complete UTF-8 sequences in `text[from ..< to]`: `to`, or the start of a
	/// sequence cut off by `to` (a stream validates it once the rest arrives).
	public static int CompleteSequencesEnd(char8* text, int from, int to)
	{
		for (int back = 1; back <= 3; back++)
		{
			int p = to - back;
			if (p < from)
				break;
			uint8 b = (uint8)text[p];
			if ((b & 0xC0) == 0x80)
				continue;
			// A lead byte (or ASCII): cut if its sequence runs past `to`; invalid bytes are FindInvalid's
			int seqLen = Utf8SequenceLength((char8)b);
			return (seqLen > 0 && p + seqLen > to) ? p : to;
		}
		return to;
	}

	/// @brief The number of code points in `text[from ..< to]`: its bytes that are not UTF-8
	/// continuation bytes (10xxxxxx), counted 8 at a time.
	public static int CountCodePoints(char8* text, int from, int to)
	{
		int count = 0;
		int p = from;
		while (p + 8 <= to)
		{
			uint64 word = Load64(text + p);
			uint64 continuation = word & ~(word << 1) & cHigh;
			count += continuation == 0 ? 8 : 8 - CountHighBits(continuation);
			p += 8;
		}
		while (p < to)
		{
			if (((uint8)text[p] & 0xC0) != 0x80)
				count++;
			p++;
		}
		return count;
	}

	/// @brief The byte length of the newline at `text[pos]`, or 0: LF, CR, or CRLF (one newline).
	[Inline]
	public static int NewlineLength(char8* text, int pos, int end)
	{
		char8 c = text[pos];
		if (c == '\n')
			return 1;
		if (c != '\r')
			return 0;
		return (pos + 1 < end && text[pos + 1] == '\n') ? 2 : 1;
	}

	/// @brief The 1-based line and column (in code points) of byte `offset`, counting LF, CR and CRLF
	/// as one newline each. A leading BOM takes no column.
	public static void LineAndColumn(StringView input, int offset, out int line, out int column)
	{
		int end = Math.Min(offset, input.Length);
		int i = StartsWithBom(input.Ptr, input.Length) ? 3 : 0;
		line = 1;
		column = 1;
		while (i < end)
		{
			int newline = NewlineLength(input.Ptr, i, input.Length);
			// An offset on the LF of a CRLF is still on the line the CRLF ends, after its CR
			if (i + newline > end)
			{
				column++;
				break;
			}
			if (newline > 0)
			{
				i += newline;
				line++;
				column = 1;
				continue;
			}
			i += Math.Max(Utf8SequenceLength(input[i]), 1);
			column++;
		}
	}

	/// @brief Append `U+XXXX` (at least four uppercase hex digits).
	public static void AppendCodePointName(String output, uint32 cp)
	{
		output.Append("U+");
		AppendHex(output, cp, 4);
	}

	/// @brief Append `value` in uppercase hex with at least `minDigits` digits.
	public static void AppendHex(String output, uint32 value, int minDigits)
	{
		int digits = 1;
		while (digits < 8 && (value >> (4 * digits)) != 0)
			digits++;
		digits = Math.Max(digits, minDigits);
		for (int d = digits - 1; d >= 0; d--)
		{
			uint32 nibble = (value >> (4 * d)) & 0xF;
			output.Append(nibble < 10 ? (char8)('0' + nibble) : (char8)('A' + nibble - 10));
		}
	}

	/// @brief Append a description of the character at `text[pos]` for an error message: `` `x` `` for a
	/// printable one, its code point name (`U+0009 (tab)`) for controls, whitespace and invisible ones.
	/// @param text The (validated) text.
	/// @param pos Where the character starts.
	/// @param end The end of the available text.
	/// @param length Receives the character's byte length.
	public static void AppendCharDescription(String output, char8* text, int pos, int end, out int length)
	{
		uint8 b = (uint8)text[pos];
		uint32 cp;
		int seqLen = Utf8SequenceLength((char8)b);
		if (seqLen == 0 || pos + seqLen > end)
		{
			length = 1;
			output.AppendF("the byte 0x{:X2}", b);
			return;
		}
		cp = (uint32)Decode(text, pos, out length);
		switch (cp)
		{
		case 0x00: output.Append("U+0000 (NUL)"); return;
		case 0x09: output.Append("U+0009 (tab)"); return;
		case 0x0A: output.Append("U+000A (line feed)"); return;
		case 0x0B: output.Append("U+000B (vertical tab)"); return;
		case 0x0C: output.Append("U+000C (form feed)"); return;
		case 0x0D: output.Append("U+000D (carriage return)"); return;
		case 0x20: output.Append("U+0020 (space)"); return;
		case 0xA0: output.Append("U+00A0 (no-break space)"); return;
		case 0xFEFF: output.Append("U+FEFF (byte order mark)"); return;
		}
		if (cp < 0x20 || cp == 0x7F || (cp >= 0x80 && cp < 0xA0) || (cp >= 0x2000 && cp <= 0x200F) ||
			(cp >= 0x2028 && cp <= 0x202F) || (cp >= 0x205F && cp <= 0x206F) || cp == 0x3000 || cp == 0x1680 || cp == 0x180E)
		{
			AppendCodePointName(output, cp);
			return;
		}
		output.Append('`');
		output.Append(text + pos, length);
		output.Append('`');
	}
}
