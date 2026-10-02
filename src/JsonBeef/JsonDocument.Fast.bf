using System;
using internal JsonBeef;

namespace JsonBeef;

extension JsonDocument
{
	/// Scratch for strings with escapes in FastBuild.
	String mDecodeBuffer = new .() ~ delete _;

	/// The fast build for input in memory (the document's copy of it, `data[start ..< end]`): one loop,
	/// with the position, depth and current container in locals, writing records directly (yyjson's
	/// shape) instead of going token by token through JsonReader. It checks everything the reader does
	/// (grammar, UTF-8 in strings, escapes and surrogate pairs, control characters, the number grammar,
	/// MaxDepth, MaxStringBytes, MaxNumberLength), but reports nothing: at the first problem of any kind
	/// it returns false, and Read clears what it built and reads again with JsonReader, which reports the
	/// error exactly. Errors are rare, so they cost one more read; the error messages and positions are
	/// the reader's by construction.
	/// @return Whether the document was read completely and is valid.
	bool FastBuild(char8* data, int start, int end, JsonReadConfig config)
	{
		const int cValue = 0;
		const int cAfterValue = 1;
		const int cName = 2;
		int maxDepth = config.MaxDepth;
		// Past these, the reader's builder reports the limit
		int maxNodes = config.MaxNodes > 0 ? config.MaxNodes + 1 : int.MaxValue;
		int maxMembers = config.MaxMembers > 0 ? config.MaxMembers : int.MaxValue;
		int p = start;
		int state = cValue;
		uint32 parent = 0;
		bool inObject = false;
		int depth = 0;
		uint64 name = 0;
		bool nameInTable = false;
		// The node table in locals (stores through `this` would make the compiler reload them after
		// every record written); mNodes.Count is set back on the way out
		JsonNodeRecord* nodes = mNodes.Ptr;
		int count = mNodes.Count;
		int capacity = mNodes.Capacity;
		defer { mNodes.Count = count; }
		while (true)
		{
			switch (state)
			{
			case cValue:
				p = SkipSpace(data, p, end);
				if (p >= end || count >= maxNodes)
					return false;
				if (count == capacity)
				{
					mNodes.Count = count;
					mNodes.Reserve(count * 2);
					nodes = mNodes.Ptr;
					capacity = mNodes.Capacity;
				}
				uint32 id = (uint32)count;
				ref JsonNodeRecord node = ref nodes[count++];
				node = default;
				node.mParent = parent;
				if (parent == 0)
					mRoot = id;
				else
				{
					if (inObject)
					{
						node.mName = name;
						if (nameInTable)
							node.mFlags |= .NameInTable;
					}
					// Appended as the parent's last child
					ref JsonNodeRecord container = ref nodes[parent];
					uint32 last = container.LastChild;
					if (last == 0)
						container.mFirstChild = id;
					else
					{
						nodes[last].mNext = id;
						node.mPrev = last;
					}
					container.mPayload = ((uint64)(uint32)(container.Count + 1) << 32) | id;
				}
				char8 c = data[p];
				switch (c)
				{
				case '{', '[':
					if (maxDepth > 0 && depth >= maxDepth)
						return false;
					depth++;
					bool isObject = c == '{';
					node.mKind = isObject ? .Object : .Array;
					parent = id;
					inObject = isObject;
					p = SkipSpace(data, p + 1, end);
					if (p < end && data[p] == (isObject ? '}' : ']'))
					{
						// Empty: closed at once
						p++;
						depth--;
						parent = node.mParent;
						inObject = parent != 0 && nodes[parent].mKind == .Object;
						state = cAfterValue;
					}
					else
						state = isObject ? cName : cValue;
					continue;
				case '"':
					node.mKind = .String;
					p = FastString(data, p, end, config.MaxStringBytes, out node.mPayload, var inTable);
					if (p < 0)
						return false;
					if (inTable)
						node.mFlags |= .ValueInTable;
				case 't':
					if (p + 4 > end || JsonChar.Load32(data + p) != 0x65757274 || (p + 4 < end && IsWordByte(data[p + 4])))
						return false;
					node.mKind = .True;
					p += 4;
				case 'f':
					if (p + 5 > end || JsonChar.Load32(data + p) != 0x736C6166 || data[p + 4] != 'e' || (p + 5 < end && IsWordByte(data[p + 5])))
						return false;
					node.mKind = .False;
					p += 5;
				case 'n':
					if (p + 4 > end || JsonChar.Load32(data + p) != 0x6C6C756E || (p + 4 < end && IsWordByte(data[p + 4])))
						return false;
					node.mKind = .Null;
					p += 4;
				default:
					if (c != '-' && !JsonChar.IsDigit(c))
						return false;
					node.mKind = .Number;
					p = FastNumber(data, p, end, config.MaxNumberLength, ref node);
					if (p < 0)
						return false;
				}
				state = cAfterValue;
			case cAfterValue:
				p = SkipSpace(data, p, end);
				if (parent == 0)
					return p == end;
				if (p >= end)
					return false;
				char8 c = data[p];
				if (c == ',')
				{
					p++;
					state = inObject ? cName : cValue;
					continue;
				}
				if (c != (inObject ? '}' : ']'))
					return false;
				p++;
				depth--;
				parent = nodes[parent].mParent;
				inObject = parent != 0 && nodes[parent].mKind == .Object;
			case cName:
				p = SkipSpace(data, p, end);
				if (p >= end || data[p] != '"' || nodes[parent].Count >= maxMembers)
					return false;
				p = FastString(data, p, end, config.MaxStringBytes, out name, out nameInTable);
				if (p < 0)
					return false;
				p = SkipSpace(data, p, end);
				if (p >= end || data[p] != ':')
					return false;
				p++;
				state = cValue;
			}
		}
	}

	/// Whether `c` continues a string's plain ASCII run (not `"`, `\`, a control or a non-ASCII byte).
	[Inline]
	static bool IsPlain(char8 c)
	{
		return (uint8)c >= 0x20 && (uint8)c < 0x80 && c != '"' && c != '\\';
	}

	[Inline]
	static bool IsWordByte(char8 c)
	{
		return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
	}

	/// Past whitespace from `p`: one compare when there is none, words for indentation.
	[Inline]
	static int SkipSpace(char8* data, int p, int end)
	{
		if (p < end && (uint8)data[p] > (uint8)' ')
			return p;
		return SkipSpaceRun(data, p, end);
	}

	static int SkipSpaceRun(char8* data, int p, int end)
	{
		var p;
		while (p < end)
		{
			if (!JsonChar.IsSpace(data[p]))
				return p;
			p++;
			if (p >= end || !JsonChar.IsSpace(data[p]))
				return p;
			p++;
			while (p + 8 <= end)
			{
				uint64 nonSpace = JsonChar.NonSpaceBytes(JsonChar.Load64(data + p));
				if (nonSpace != 0)
					return p + JsonChar.FirstByte(nonSpace);
				p += 8;
			}
		}
		return p;
	}

	/// The string at `p` (its opening quote): a view of the source when it has no escapes, else decoded
	/// into the string table. @return The position after its closing quote, or -1 for any problem.
	int FastString(char8* data, int p, int end, int maxBytes, out uint64 textRef, out bool inTable)
	{
		textRef = 0;
		inTable = false;
		int start = p + 1;
		int q = start;
		while (true)
		{
			// Vectors and words only for a plain run (non-ASCII text comes in runs too)
			while (q + 16 <= end && IsPlain(data[q]))
			{
				int stop = JsonChar.FirstStringStop16(data + q);
				q += stop;
				if (stop < 16)
					break;
			}
			while (q + 8 <= end && IsPlain(data[q]))
			{
				uint64 word = JsonChar.Load64(data + q);
				uint64 stops = JsonChar.StringStops(word) | (word & JsonChar.cHigh);
				if (stops != 0)
				{
					q += JsonChar.FirstByte(stops);
					break;
				}
				q += 8;
			}
			if (q >= end)
				return -1;
			char8 c = data[q];
			if (c == '"')
				break;
			if ((uint8)c >= 0x80)
			{
				int length = JsonChar.ValidSequenceLength(data, q, end);
				if (length == 0)
					return -1;
				q += length;
				continue;
			}
			if (c == '\\')
				return FastEscapedString(data, start, q, end, maxBytes, out textRef, out inTable);
			if ((uint8)c < 0x20)
				return -1;
			q++;
		}
		if (maxBytes > 0 && q - start > maxBytes)
			return -1;
		textRef = MakeRef((int)(data + start - mSource), q - start);
		return q + 1;
	}

	/// A string with escapes, from its text's start to its closing quote, `q` at its first backslash:
	/// decoded (and checked) into mDecodeBuffer, then copied into the string table.
	int FastEscapedString(char8* data, int start, int q, int end, int maxBytes, out uint64 textRef, out bool inTable)
	{
		textRef = 0;
		inTable = false;
		let buffer = mDecodeBuffer;
		buffer.Clear();
		buffer.Append(data + start, q - start);
		var q;
		int run = q;
		while (true)
		{
			// Vectors and words only for a plain run (escapes come in clusters: `éè`)
			while (q + 16 <= end && IsPlain(data[q]))
			{
				int stop = JsonChar.FirstStringStop16(data + q);
				q += stop;
				if (stop < 16)
					break;
			}
			while (q + 8 <= end && IsPlain(data[q]))
			{
				uint64 word = JsonChar.Load64(data + q);
				uint64 stops = JsonChar.StringStops(word) | (word & JsonChar.cHigh);
				if (stops != 0)
				{
					q += JsonChar.FirstByte(stops);
					break;
				}
				q += 8;
			}
			if (q >= end)
				return -1;
			char8 c = data[q];
			if (c == '"')
				break;
			if ((uint8)c >= 0x80)
			{
				int length = JsonChar.ValidSequenceLength(data, q, end);
				if (length == 0)
					return -1;
				q += length;
				continue;
			}
			if ((uint8)c < 0x20)
				return -1;
			if (c != '\\')
			{
				q++;
				continue;
			}
			buffer.Append(data + run, q - run);
			if (q + 1 >= end)
				return -1;
			switch (data[q + 1])
			{
			case '"': buffer.Append('"'); q += 2;
			case '\\': buffer.Append('\\'); q += 2;
			case '/': buffer.Append('/'); q += 2;
			case 'b': buffer.Append('\b'); q += 2;
			case 'f': buffer.Append('\f'); q += 2;
			case 'n': buffer.Append('\n'); q += 2;
			case 'r': buffer.Append('\r'); q += 2;
			case 't': buffer.Append('\t'); q += 2;
			case 'u':
				uint32 cp = Hex4(data, q + 2, end);
				if (cp > 0xFFFF)
					return -1;
				if (cp >= 0xD800 && cp <= 0xDFFF)
				{
					// Only a high surrogate escape immediately followed by a low one
					if (cp >= 0xDC00 || q + 12 > end || data[q + 6] != '\\' || data[q + 7] != 'u')
						return -1;
					uint32 low = Hex4(data, q + 8, end);
					if (low < 0xDC00 || low > 0xDFFF)
						return -1;
					cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
					q += 12;
				}
				else
					q += 6;
				char8[4] utf8 = ?;
				buffer.Append(&utf8, JsonChar.EncodeUtf8(&utf8, cp));
			default:
				return -1;
			}
			run = q;
		}
		buffer.Append(data + run, q - run);
		if (maxBytes > 0 && buffer.Length > maxBytes)
			return -1;
		textRef = AddText(buffer);
		inTable = true;
		return q + 1;
	}

	/// The value of four hex digits at `p`, or a value above 0xFFFF if they are not.
	[Inline]
	static uint32 Hex4(char8* data, int p, int end)
	{
		if (p + 4 > end)
			return 0x10000;
		uint32 value = 0;
		for (int i < 4)
		{
			uint8 digit = JsonChar.HexDigitValue(data[p + i]);
			if (digit == 255)
				return 0x10000;
			value = (value << 4) | digit;
		}
		return value;
	}

	/// The number at `p` into `node` (kind, value or text reference), as the reader classifies and
	/// converts it. @return The position after it, or -1 for any problem.
	int FastNumber(char8* data, int p, int end, int maxLength, ref JsonNodeRecord node)
	{
		int start = p;
		var p;
		bool negative = false;
		if (data[p] == '-')
		{
			negative = true;
			p++;
			if (p >= end || !JsonChar.IsDigit(data[p]))
				return -1;
		}
		uint64 magnitude = 0;
		int digits = 0;
		bool big = false;
		if (data[p] == '0')
		{
			p++;
			digits = 1;
			if (p < end && JsonChar.IsDigit(data[p]))
				return -1;
		}
		else
		{
			while (digits <= 11 && p + 8 <= end)
			{
				uint64 word = JsonChar.Load64(data + p);
				if (!JsonChar.AllDigits(word))
					break;
				magnitude = magnitude * 100000000 + JsonChar.ParseEightDigits(word);
				digits += 8;
				p += 8;
			}
			while (p < end && JsonChar.IsDigit(data[p]))
			{
				uint64 digit = (uint8)data[p] - (uint8)'0';
				if (digits < 19)
					magnitude = magnitude * 10 + digit;
				else if (digits == 19 && (magnitude < 1844674407370955161UL || (magnitude == 1844674407370955161UL && digit <= 5)))
					magnitude = magnitude * 10 + digit;
				else
					big = true;
				digits++;
				p++;
			}
		}
		bool isFloat = false;
		uint64 mantissa = magnitude;
		int mantissaDigits = digits;
		bool exact = digits <= 19;
		int exponent = 0;
		if (p < end && data[p] == '.')
		{
			p++;
			if (p >= end || !JsonChar.IsDigit(data[p]))
				return -1;
			while (mantissaDigits <= 11 && p + 8 <= end)
			{
				uint64 word = JsonChar.Load64(data + p);
				if (!JsonChar.AllDigits(word))
					break;
				mantissa = mantissa * 100000000 + JsonChar.ParseEightDigits(word);
				mantissaDigits += 8;
				exponent -= 8;
				p += 8;
			}
			while (p < end && JsonChar.IsDigit(data[p]))
			{
				if (mantissaDigits < 19)
				{
					mantissa = mantissa * 10 + (uint64)((uint8)data[p] - (uint8)'0');
					mantissaDigits++;
					exponent--;
				}
				else
					exact = false;
				p++;
			}
			isFloat = true;
		}
		if (p < end && (data[p] == 'e' || data[p] == 'E'))
		{
			p++;
			bool negativeExponent = false;
			if (p < end && (data[p] == '+' || data[p] == '-'))
			{
				negativeExponent = data[p] == '-';
				p++;
			}
			if (p >= end || !JsonChar.IsDigit(data[p]))
				return -1;
			int explicitExponent = 0;
			while (p < end && JsonChar.IsDigit(data[p]))
			{
				if (explicitExponent < 100000)
					explicitExponent = explicitExponent * 10 + ((uint8)data[p] - (uint8)'0');
				p++;
			}
			exponent += negativeExponent ? -explicitExponent : explicitExponent;
			isFloat = true;
		}
		int length = p - start;
		if (maxLength > 0 && length > maxLength)
			return -1;
		// Something that continues the number's text: the reader's InvalidNumber
		if (p < end && (IsWordByte(data[p]) || data[p] == '.' || data[p] == '+' || data[p] == '-'))
			return -1;
		if (isFloat)
		{
			node.mNumberKind = .Float;
			double value = 0;
			if ((exact && !big && JsonNumber.TryClinger(mantissa, exponent, negative, out value)) ||
				JsonNumber.ParseDoubleSlow(.(data + start, length), out value))
				node.mPayload = JsonNumber.ToBits(value);
			else
			{
				// Beyond a double's range: the text is kept
				node.mPayload = MakeRef((int)(data + start - mSource), length);
				node.mFlags |= .Lexeme;
			}
		}
		else if (big)
		{
			node.mNumberKind = .BigInteger;
			node.mPayload = MakeRef((int)(data + start - mSource), length);
			node.mFlags |= .Lexeme;
		}
		else if (negative)
		{
			if (magnitude <= (uint64)int64.MaxValue + 1)
			{
				node.mNumberKind = .Integer;
				node.mPayload = (uint64)(magnitude == 0 ? 0 : -(int64)(magnitude - 1) - 1);
				if (magnitude == 0)
					node.mFlags |= .NegativeZero;
			}
			else
			{
				node.mNumberKind = .BigInteger;
				node.mPayload = MakeRef((int)(data + start - mSource), length);
				node.mFlags |= .Lexeme;
			}
		}
		else if (magnitude <= (uint64)int64.MaxValue)
		{
			node.mNumberKind = .Integer;
			node.mPayload = magnitude;
		}
		else
		{
			node.mNumberKind = .UInteger;
			node.mPayload = magnitude;
		}
		return p;
	}
}
