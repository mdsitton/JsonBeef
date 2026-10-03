using System;
using System.Collections;
using FormatCore;
using internal FormatCore;
using internal JsonBeef;

namespace JsonBeef;

/// What push input owns (the cursor is a struct): the bytes fed and not yet consumed, from absolute
/// offset mBase, whether the input is finished, and its error (MaxInputBytes).
internal class JsonPushState
{
	public List<uint8> mBuffer = new .() ~ delete _;
	public int mBase;
	public int mTotal;
	public bool mFinished;
	public bool mStarved;
	public int mMaxInputBytes;
	public int mMaxTokenBytes;
	/// The cursor-level settings (the BOM rule and the wide-encoding check at Begin)
	public InputSettings mSettings;
	public bool mHasError;
	public InputErrorKind mErrorKind;
	public String mErrorMessage = new .() ~ delete _;
	public int mErrorOffset;
	/// Lines counted up to the bytes dropped from the buffer, and forward for Locate
	public LineCounter<JsonText> mLines;
	public LineCounter<JsonText> mLocated;

	public void Reset(JsonReadConfig config)
	{
		mBuffer.Clear();
		mBase = 0;
		mTotal = 0;
		mFinished = false;
		mStarved = false;
		mMaxInputBytes = config.MaxInputBytes;
		mMaxTokenBytes = config.MaxTokenBytes;
		mSettings = JsonInput.Settings(config);
		mHasError = false;
		mLines = .(0);
		mLocated = .(0);
	}

	public char8* Text => (char8*)mBuffer.Ptr - mBase;

	public int End => mBase + mBuffer.Count;

	/// Drops the bytes before `keep` (counting their lines first; never just after a CR, whose LF may
	/// follow).
	public void Drop(int keep)
	{
		int drop = keep - mBase;
		if (drop > 0 && mBuffer[drop - 1] == '\r')
			drop--;
		if (drop <= 0)
			return;
		int dropTo = mBase + drop;
		if (mLocated.mPos <= dropTo)
		{
			mLocated.AdvanceLines(Text, dropTo, End);
			mLocated.Column(Text, dropTo);
			mLines = mLocated;
		}
		else
		{
			mLines.AdvanceLines(Text, Math.Max(dropTo, mLines.mPos), End);
			mLines.Column(Text, dropTo);
			if (mLocated.mLineStart < dropTo)
				mLocated.Column(Text, dropTo);
		}
		mBuffer.RemoveRange(0, drop);
		mBase += drop;
	}

	public void SetError(InputErrorKind kind, StringView message, int offset)
	{
		if (mHasError)
			return;
		mHasError = true;
		mErrorKind = kind;
		mErrorMessage.Set(message);
		mErrorOffset = offset;
		Locate(offset, out mErrorLine, out mErrorColumn);
	}

	public int mErrorLine;
	public int mErrorColumn;

	/// The 1-based line and column of `offset`, from the bytes still held.
	public bool Locate(int offset, out int line, out int column)
	{
		line = 0;
		column = 0;
		if (offset < mLines.mPos)
			return false;
		int target = Math.Min(offset, End);
		if (mLocated.CanReach(target))
		{
			mLocated.Locate(Text, target, End, out line, out column);
			return true;
		}
		var lines = mLines;
		lines.Locate(Text, target, End, out line, out column);
		return true;
	}
}

/// Push input (JsonPushReader): the window is every byte fed and not yet dropped. Where the reader needs
/// more than has been fed, Begin and Fill note that they are starved (unless the input is finished), and
/// the reader takes the token back.
internal struct JsonPushCursor : IInputCursor
{
	JsonPushState mState;

	public this(JsonPushState state)
	{
		mState = state;
	}

	public Result<int, InputError> Begin(ref char8* data, ref int windowStart, ref int end) mut
	{
		SetWindow(ref data, ref windowStart, ref end, 0);
		// Enough to tell a BOM or UTF-16/32 from UTF-8 (or the whole input)
		if (mState.mBuffer.Count < 4 && !mState.mFinished)
		{
			mState.mStarved = true;
			return 0;
		}
		int start = Try!(InputStart.Check(mState.Text, mState.End, mState.mSettings));
		mState.mLines = .(start);
		mState.mLocated = .(start);
		return start;
	}

	public bool Fill(ref char8* data, ref int windowStart, ref int end, int keep, int pos, int count) mut
	{
		int oldEnd = end;
		int from = Math.Min(keep, pos);
		// A token longer than MaxTokenBytes (whose bytes exist, or may still come): what the bound is for
		if (mState.mMaxTokenBytes > 0 && pos + count - from > mState.mMaxTokenBytes && !mState.mHasError && (pos + count <= mState.End || !mState.mFinished))
			mState.SetError(.ResourceLimitExceeded, scope $"A token is longer than MaxTokenBytes ({mState.mMaxTokenBytes})", from + mState.mMaxTokenBytes);
		SetWindow(ref data, ref windowStart, ref end, from);
		if (pos + count > end && !mState.mFinished && !mState.mHasError)
			mState.mStarved = true;
		return end > oldEnd;
	}

	/// The window: every byte held (up to an input error), but no more than MaxTokenBytes from `from`
	/// (the token being read), so that a longer token always comes to Fill's check.
	void SetWindow(ref char8* data, ref int windowStart, ref int end, int from)
	{
		data = mState.Text;
		windowStart = mState.mBase;
		end = mState.mHasError ? Math.Min(mState.End, mState.mErrorOffset) : mState.End;
		if (mState.mMaxTokenBytes > 0 && from + mState.mMaxTokenBytes < end)
			end = Math.Max(from + mState.mMaxTokenBytes, mState.mBase);
	}

	public bool TryGetInputError(out InputError error)
	{
		error = default;
		if (!mState.mHasError)
			return false;
		error = InputError(mState.mErrorKind, mState.mErrorMessage, mState.mErrorLine, mState.mErrorColumn, mState.mErrorOffset, 0);
		return true;
	}

	public bool HasInputError => mState.mHasError;

	public bool IsWhole
	{
		[Inline]
		get => false;
	}

	public bool TakeStarved() mut
	{
		bool starved = mState.mStarved;
		mState.mStarved = false;
		return starved;
	}

	public bool Locate(int offset, out int line, out int column) mut
	{
		return mState.Locate(offset, out line, out column);
	}
}

/// @brief A pull reader that is fed: for input that arrives in pieces (a network connection, a pipe read
/// without blocking). Feed bytes as they come, call Next until it returns `JsonToken.None` (it needs
/// more), feed again, and call Finish at the end of the input. A token is reported only once all of it
/// has been fed, so the tokens, values and errors are exactly those of reading the whole input at once
/// (a number at the end of what was fed may go on: it waits for more, or for Finish). Memory holds
/// what has been fed and not read yet.
///
/// ```
/// let reader = scope JsonPushReader();
/// while (ReceiveChunk(chunk) case .Ok(let count) && count > 0)    // the caller's input
/// {
///     reader.Feed(chunk.Slice(0, count));
///     JsonToken token;
///     while ((token = Try!(reader.Next())) != .None)
///         Handle(reader, token);
/// }
/// reader.Finish();
/// JsonToken token;
/// while ((token = Try!(reader.Next())) != .EndOfDocument)
///     Handle(reader, token);
/// ```
public class JsonPushReader
{
	JsonReaderCore<JsonPushCursor> mCore = new .() ~ delete _;
	JsonPushState mState = new .() ~ delete _;
	String mSourceName = new .() ~ delete _;

	/// @brief Create a reader with the default config.
	public this()
	{
		Reset(.());
	}

	/// @brief Create a reader with a config (MaxTokenBytes bounds how much one token may hold back).
	/// @param config The dialect, limits and source name.
	public this(JsonReadConfig config)
	{
		Reset(config);
	}

	/// @brief Start a new input, dropping anything fed before.
	/// @param config The dialect, limits and source name (copied).
	public void Reset(JsonReadConfig config = .())
	{
		mSourceName.Set(config.SourceName);
		var config;
		config.SourceName = mSourceName;
		mState.Reset(config);
		mCore.Reset(JsonPushCursor(mState), config);
		mWaitForQuote = false;
		mScanFrom = 0;
	}

	/// @brief Add the next bytes of the input. The current token's views (StringValue, RawValue) are
	/// invalid afterwards.
	/// @param bytes The bytes, in input order.
	public void Feed(Span<uint8> bytes)
	{
		if (mState.mFinished || bytes.Length == 0)
			return;
		mState.Drop(mCore.KeepFrom);
		mState.mBuffer.AddRange(bytes);
		mState.mTotal += bytes.Length;
		if (mState.mMaxInputBytes > 0 && mState.mTotal > mState.mMaxInputBytes)
			mState.SetError(.ResourceLimitExceeded, scope $"The input exceeds MaxInputBytes ({mState.mMaxInputBytes})", mState.mMaxInputBytes);
		mCore.RefreshWindow();
	}

	/// @brief Add the next part of the input as text.
	/// @param text UTF-8 text.
	public void Feed(StringView text)
	{
		Feed(Span<uint8>((uint8*)text.Ptr, text.Length));
	}

	/// @brief Mark the end of the input: what is left is read as the end of a whole input (a final number
	/// completes; a value cut off is an error).
	public void Finish()
	{
		mState.mFinished = true;
		mCore.RefreshWindow();
	}

	/// @brief Whether Finish was called.
	public bool IsFinished => mState.mFinished;

	/// @brief Read the next token, if all of it has been fed.
	/// @return The token; None when more input is needed first (Feed, or Finish); or the read's error.
	public Result<JsonToken, JsonParseError> Next()
	{
		// Cut off inside a string: read it again only once a `"` has come (or the input is finished),
		// so that a long string fed a byte at a time is not scanned again for every byte
		// (Unless the string is already past MaxTokenBytes: reading it again reports that)
		if (mWaitForQuote && !mState.mFinished && !(mState.mMaxTokenBytes > 0 && mState.End - mCore.KeepFrom > mState.mMaxTokenBytes))
		{
			let bytes = mState.mBuffer;
			int i = mScanFrom - mState.mBase;
			while (i < bytes.Count && bytes[i] != '"')
				i++;
			if (i >= bytes.Count)
			{
				mScanFrom = mState.End;
				return .Ok(.None);
			}
			mWaitForQuote = false;
		}
		switch (mCore.NextTokenPush(let starved))
		{
		case .Ok(let token):
			if (starved)
			{
				mWaitForQuote = mCore.mStarvedInString;
				mScanFrom = mState.End;
			}
			return .Ok(token);
		case .Err:
			return .Err(mCore.mError);
		}
	}

	/// The last token was cut off inside a string; the bytes from mScanFrom (absolute) have no `"` yet.
	bool mWaitForQuote;
	int mScanFrom;

	/// @brief The last token Next returned (None after it needed more input).
	public JsonToken TokenType => mCore.mToken;

	/// @brief The token's depth (see JsonReader.Depth).
	public int Depth => mCore.TokenDepth;

	/// @brief The number of containers open after the token.
	public int CurrentDepth => mCore.CurrentDepth;

	/// @brief Byte offset into the input where the token starts.
	public int Offset => mCore.mTokenStart;

	/// @brief Byte offset just past the token.
	public int EndOffset => mCore.mTokenEnd;

	/// @brief String, PropertyName: the decoded text; Number: its JSON text; literals: the literal (as
	/// JsonReader.StringValue). Valid until the next Next or Feed.
	public StringView StringValue => mCore.mValue;

	/// @brief The token's text as written (as JsonReader.RawValue). Valid until the next Next or Feed.
	public StringView RawValue => mCore.mRaw;

	/// @brief String, PropertyName: whether the text has escapes.
	public bool ValueIsEscaped => mCore.mEscaped;

	/// @brief Number: what the token holds.
	public JsonNumberKind NumberKind => mCore.mNumberKind;

	/// @brief Whether the read has stopped at an error.
	public bool IsStopped => mCore.IsStopped;

	/// @brief Number: the value as an int64, if it is an integer that fits.
	public bool TryGetInt64(out int64 value)
	{
		value = 0;
		if (mCore.mToken != .Number || mCore.mNumberKind != .Integer)
			return false;
		value = mCore.mInteger;
		return true;
	}

	/// @brief Number: the value as a uint64, if it is a non-negative integer that fits.
	public bool TryGetUInt64(out uint64 value)
	{
		value = 0;
		if (mCore.mToken != .Number)
			return false;
		switch (mCore.mNumberKind)
		{
		case .Integer:
			if (mCore.mInteger < 0)
				return false;
			value = (uint64)mCore.mInteger;
			return true;
		case .UInteger:
			value = (uint64)mCore.mInteger;
			return true;
		default:
			return false;
		}
	}

	/// @brief Number: the correctly rounded double, if it is finite (or a NonFinite token's value).
	public bool TryGetDouble(out double value)
	{
		value = 0;
		if (mCore.mToken != .Number)
			return false;
		return mCore.GetDouble(out value);
	}

	/// @brief Number: the correctly rounded double, or NumberOutOfRange (never a silent infinity).
	public Result<double, JsonParseError> GetDouble()
	{
		if (TryGetDouble(let value))
			return value;
		return .Err(mCore.MakeError(.NumberOutOfRange, scope $"The number `{RawValue}` is not a finite double", Offset, EndOffset - Offset));
	}
}
