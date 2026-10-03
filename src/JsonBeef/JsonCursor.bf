using System;
using FormatCore;
using internal FormatCore;
using internal JsonBeef;

namespace JsonBeef;

/// Where JsonReaderCore's bytes come from (KdlBeef's IKdlCursor, XmlBeef's IXmlCursor). The reader reads
/// a window of the input through a pointer `data` indexed by absolute offsets (`data[offset]`, valid for
/// `windowStart <= offset < end`), so offsets it keeps stay valid when a stream moves or grows its
/// buffer; only `data`, `windowStart` and `end` change. The bytes are not validated here: only strings
/// may hold non-ASCII bytes, so the reader checks UTF-8 as it scans them (and reports a non-ASCII byte
/// anywhere else by whether it is well-formed).
internal interface IJsonCursor
{
	/// Checks the start of the input (a UTF-16/32 encoding, a BOM) and sets up the window.
	/// @return The offset of the first content byte (after a BOM), or the input's error.
	Result<int, JsonParseError> Begin(ref char8* data, ref int windowStart, ref int end) mut;

	/// Makes the input up to `pos + count` available if there is that much, keeping every byte from
	/// `keep` on in the window (the reader's current token). The window may move.
	/// @return Whether `end` grew.
	bool Fill(ref char8* data, ref int windowStart, ref int end, int keep, int pos, int count) mut;

	/// An error of the input itself (I/O, encoding, size) that stopped Fill. The reader reports it in
	/// place of its own once it has run into the end of what Fill delivered. Making the error writes the
	/// per-thread message buffer: to only ask whether there is one, use HasInputError.
	bool TryGetInputError(out JsonParseError error);

	/// Whether the input has failed (TryGetInputError would make an error), without making one.
	bool HasInputError { get; }

	/// The 1-based line and column (in code points) of `offset`: always for in-memory input; for a
	/// stream only from the earliest offset it still holds (the start of the current token).
	bool Locate(int offset, out int line, out int column) mut;

	/// Whether the whole input is in the window from the start (memory): a stream's is not.
	bool IsWhole { get; }

	/// Push input (JsonPushReader): whether Begin or Fill ran out of what has been fed so far, input
	/// that is not finished, since the last call; clears it. Memory and streams never run out that way.
	bool TakeStarved() mut;
}

/// Counts lines forward through the input, and columns only when asked (XmlBeef's XmlLineCounter):
/// newlines are found 8 bytes at a time up to an offset (AdvanceLines), and a column is the code points
/// from a base on the current line (its start, or a later offset whose column is known) to the offset.
/// LF, CR and CRLF are one newline each; an offset on the LF of a CRLF is on the line the CRLF ends.
internal struct JsonLineCounter
{
	/// Newlines are counted up to here.
	public int mPos;
	public int mLine = 1;
	/// The column base: an offset on the current line (its start, or later) and its column.
	public int mLineStart;
	public int mLineColumn = 1;

	public this(int start)
	{
		mPos = start;
		mLineStart = start;
	}

	/// Moves to `offset` (not before the current position), counting every newline (CRLF as one).
	/// `text[mPos ..< offset]` must be available, up to `end`.
	public void AdvanceLines(char8* text, int offset, int end) mut
	{
		while (mPos < offset)
		{
			// Two words at a time while neither has a byte below 0x0E (no LF or CR)
			while (mPos + 16 <= offset && (Swar.BytesBelow0E(Swar.Load64(text + mPos)) | Swar.BytesBelow0E(Swar.Load64(text + mPos + 8))) == 0)
				mPos += 16;
			if (mPos >= offset)
				break;
			if (mPos + 8 <= end)
			{
				// Every newline of the word at once: each LF, and each CR not followed by an LF (in the word,
				// or the next byte). A word past `offset` (still in the window) counts only the bytes before it.
				int count = Math.Min(offset - mPos, 8);
				uint64 word = Swar.Load64(text + mPos);
				uint64 lf = Swar.BytesEqual(word, (uint8)'\n');
				uint64 cr = Swar.BytesEqual(word, (uint8)'\r');
				if ((lf | cr) != 0)
				{
					uint64 lfNext = lf >> 8;
					if (mPos + 8 < end && text[mPos + 8] == '\n')
						lfNext |= 1UL << 63;
					uint64 newlines = lf | (cr & ~lfNext);
					if (count < 8)
						newlines &= (1UL << (count * 8)) - 1;
					if (newlines != 0)
					{
						mLine += Swar.CountHighBits(newlines);
						// The line starts after the last one: smeared down, its byte and those below
						uint64 below = newlines | (newlines >> 8);
						below |= below >> 16;
						below |= below >> 32;
						mLineStart = mPos + Swar.CountHighBits(below);
						mLineColumn = 1;
					}
				}
				mPos += count;
				continue;
			}
			int newline = Utf8.AsciiNewlineLength(text, mPos, end);
			// A CRLF across `offset` (an offset on its LF): its CR is not the newline, as in a word above
			if (mPos + newline > offset)
			{
				mPos = offset;
				break;
			}
			if (newline > 0)
			{
				mPos += newline;
				mLine++;
				mLineStart = mPos;
				mLineColumn = 1;
				continue;
			}
			mPos++;
		}
	}

	/// The column of `offset`, which must be on the current line, at or after the base, with
	/// `text[mLineStart ..< offset]` available. The base moves there.
	public int Column(char8* text, int offset) mut
	{
		if (offset > mLineStart)
		{
			mLineColumn += Utf8.CountCodePoints(text, mLineStart, offset);
			mLineStart = offset;
		}
		return mLineColumn;
	}

	/// AdvanceLines and Column: the line and column of `offset`.
	public void Locate(char8* text, int offset, int end, out int line, out int column) mut
	{
		AdvanceLines(text, offset, end);
		line = mLine;
		column = Column(text, offset);
	}
}

/// The checks every input gets before its first byte is read: a UTF-16/32 encoding, the byte order mark.
internal static class JsonInputStart
{
	/// The offset of the first content byte of `data[0 ..< length]` (3 after a BOM), or the error.
	public static Result<int, JsonParseError> Check(char8* data, int length, bool allowBom)
	{
		let wide = InputStart.DetectWideEncoding(data, length);
		if (!wide.IsEmpty)
		{
			let message = scope String();
			message.AppendF("The input is {} (JSON must be UTF-8, RFC 8259 §8.1): transcode it first", wide);
			return .Err(JsonParseError(.UnsupportedEncoding, message, 1, 1, 0, 0));
		}
		if (Utf8.StartsWithBom(data, length))
		{
			if (!allowBom)
				return .Err(JsonParseError(.UnexpectedChar, "A byte order mark (U+FEFF) is not allowed (JsonReadConfig.AllowBom is off)", 1, 1, 0, 3));
			return 3;
		}
		return 0;
	}
}

/// An in-memory input: the window is the whole input; Fill never has more.
internal struct JsonByteCursor : IJsonCursor
{
	StringView mInput;
	int mMaxInputBytes;
	bool mAllowBom;
	JsonLineCounter mLines;

	public this(StringView input, JsonReadConfig config)
	{
		mInput = input;
		mMaxInputBytes = config.MaxInputBytes;
		mAllowBom = config.AllowBom;
		mLines = .(0);
	}

	public Result<int, JsonParseError> Begin(ref char8* data, ref int windowStart, ref int end) mut
	{
		data = mInput.Ptr;
		windowStart = 0;
		end = mInput.Length;
		if (mMaxInputBytes > 0 && mInput.Length > mMaxInputBytes)
			return .Err(JsonParseError(.ResourceLimitExceeded, scope $"The input ({mInput.Length} bytes) exceeds MaxInputBytes ({mMaxInputBytes})", 1, 1, 0, 0));
		int start = Try!(JsonInputStart.Check(mInput.Ptr, mInput.Length, mAllowBom));
		mLines = .(start);
		return start;
	}

	[Inline]
	public bool Fill(ref char8* data, ref int windowStart, ref int end, int keep, int pos, int count) mut
	{
		return false;
	}

	[Inline]
	public bool TryGetInputError(out JsonParseError error)
	{
		error = default;
		return false;
	}

	public bool HasInputError
	{
		[Inline]
		get => false;
	}

	public bool IsWhole
	{
		[Inline]
		get => true;
	}

	[Inline]
	public bool TakeStarved() mut => false;

	public bool Locate(int offset, out int line, out int column) mut
	{
		int target = Math.Min(offset, mInput.Length);
		if (target < mLines.mPos || target < mLines.mLineStart)
		{
			// Behind the counter (an error before the last position asked for): count from the start
			Utf8.LineAndColumn<JsonText>(mInput, target, out line, out column);
			return true;
		}
		mLines.Locate(mInput.Ptr, target, mInput.Length, out line, out column);
		return true;
	}
}
