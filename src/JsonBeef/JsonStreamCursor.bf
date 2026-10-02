using System;
using System.Collections;
using System.IO;
using internal JsonBeef;

namespace JsonBeef;

/// What a stream read owns (a cursor is a struct): the buffer and the input's error. The error is kept
/// in parts, with its own copy of the message: a JsonParseError's message lives in a per-thread buffer
/// that the next error overwrites.
internal class JsonStreamState
{
	public List<uint8> mBuffer ~ delete _;
	public bool mHasError;
	public JsonErrorKind mErrorKind;
	public String mErrorMessage ~ delete _;
	public int mErrorLine;
	public int mErrorColumn;
	public int mErrorOffset;
	public int mErrorLength;

	public this()
	{
		mBuffer = new .();
		mErrorMessage = new .();
	}

	public JsonParseError MakeError()
	{
		return JsonParseError(mErrorKind, mErrorMessage, mErrorLine, mErrorColumn, mErrorOffset, mErrorLength);
	}
}

/// A stream read through a buffer (KdlBeef's KdlBufferedStreamCursor): the window is the buffered part
/// of the input from the reader's current token on. A refill drops the bytes before that token and
/// moves the rest to the front; a token longer than the buffer doubles it (bounded by MaxTokenBytes).
/// Bytes are validated as they arrive; the window ends at the last complete, valid code point, so the
/// reader never sees bytes that are not.
internal struct JsonBufferedStreamCursor : IJsonCursor
{
	Stream mStream;
	JsonStreamState mState;
	/// Absolute offset of the buffer's first byte.
	int mBase;
	/// Bytes in the buffer, and how many of them are validated (the window).
	int mRaw;
	int mValid;
	/// The stream is exhausted, or failed (mState.mHasError).
	bool mDone;
	int mBytesRead;
	int mMaxInputBytes;
	int mMaxTokenBytes;
	bool mAllowBom;
	/// The size of the buffer.
	int mCapacity;
	/// Lines counted up to the bytes dropped from the buffer: nothing before it can be located.
	JsonLineCounter mLines;
	/// Lines counted forward for Locate; a request behind it counts from mLines instead.
	JsonLineCounter mLocated;

	public this(Stream stream, JsonStreamState state, JsonReadConfig config)
	{
		mStream = stream;
		mState = state;
		mBase = 0;
		mRaw = 0;
		mValid = 0;
		mDone = false;
		mBytesRead = 0;
		mMaxInputBytes = config.MaxInputBytes;
		mMaxTokenBytes = config.MaxTokenBytes;
		mAllowBom = config.AllowBom;
		mLines = .(0);
		mLocated = .(0);
		state.mHasError = false;
		int size = config.StreamBufferBytes > 0 ? Math.Max(config.StreamBufferBytes, 16) : 64 * 1024;
		// Never more than MaxTokenBytes: a token that would exceed it cannot fit the window, so reading it
		// always comes to Fill, which checks it
		if (mMaxTokenBytes > 0)
			size = Math.Min(size, Math.Max(mMaxTokenBytes, 16));
		mCapacity = size;
		state.mBuffer.Count = size;
	}

	[Inline]
	char8* Buffer => (char8*)mState.mBuffer.Ptr;

	public Result<int, JsonParseError> Begin(ref char8* data, ref int windowStart, ref int end) mut
	{
		// Enough to see a BOM or a UTF-16/32 pattern (or the whole input, if it is shorter)
		while (mRaw < 4 && !mDone)
			ReadMore();
		data = Buffer;
		windowStart = 0;
		end = 0;
		if (mState.mHasError)
			return .Err(mState.MakeError());
		int start = Try!(JsonInputStart.Check(Buffer, mRaw, mAllowBom));
		mValid = start;
		mLines = .(start);
		mLocated = .(start);
		// Finish the first buffer, and validate it: in-memory input is validated before reading, so a
		// document that fits the buffer reports the same first error either way
		while (mRaw < mCapacity && !mDone)
			ReadMore();
		Validate();
		SetWindow(ref data, ref windowStart, ref end, start);
		if (mState.mHasError)
			return .Err(mState.MakeError());
		return start;
	}

	public bool Fill(ref char8* data, ref int windowStart, ref int end, int keep, int pos, int count) mut
	{
		int oldEnd = end;
		int from = Math.Min(keep, pos);
		// The reader would hold the token from `from` through what it looks at at once: that is what
		// MaxTokenBytes bounds, whatever the buffer's size. Only when those bytes exist (in the buffer,
		// or maybe still in the stream).
		if (mMaxTokenBytes > 0 && pos + count - from > mMaxTokenBytes && (pos + count <= mBase + mValid || !mDone))
		{
			SetError(.ResourceLimitExceeded, scope $"A token is longer than MaxTokenBytes ({mMaxTokenBytes})", from + mMaxTokenBytes);
			SetWindow(ref data, ref windowStart, ref end, from);
			return false;
		}
		while (mBase + mValid < pos + count && !mDone)
		{
			// Drop what the reader is done with, counting its lines first; never just after a CR (an LF
			// may follow, and the two halves of a CRLF would count as two newlines)
			int drop = from - mBase;
			if (drop > 0 && Buffer[drop - 1] == '\r')
				drop--;
			if (drop > 0)
			{
				char8* text = Buffer - mBase;
				int dropTo = mBase + drop;
				if (mLocated.mPos <= dropTo)
				{
					mLocated.AdvanceLines(text, dropTo, mBase + mRaw);
					mLocated.Column(text, dropTo);
					mLines = mLocated;
				}
				else
				{
					mLines.AdvanceLines(text, Math.Max(dropTo, mLines.mPos), mBase + mRaw);
					mLines.Column(text, dropTo);
					if (mLocated.mLineStart < dropTo)
						mLocated.Column(text, dropTo);
				}
				Internal.MemMove(Buffer, Buffer + drop, mRaw - drop);
				mBase += drop;
				mRaw -= drop;
				mValid -= drop;
			}
			if (mRaw == mCapacity)
			{
				// One token fills the buffer: grow it, never past MaxTokenBytes
				if (mMaxTokenBytes > 0 && mRaw >= mMaxTokenBytes)
				{
					SetError(.ResourceLimitExceeded, scope $"A token is longer than MaxTokenBytes ({mMaxTokenBytes})", mBase + mRaw);
					break;
				}
				int grown = mCapacity * 2;
				if (mMaxTokenBytes > 0)
					grown = Math.Min(grown, mMaxTokenBytes);
				mCapacity = grown;
				mState.mBuffer.Count = grown;
			}
			ReadMore();
			Validate();
		}
		SetWindow(ref data, ref windowStart, ref end, from);
		return end > oldEnd;
	}

	/// The window: the validated bytes, but with MaxTokenBytes no more than that from `from` (the token
	/// being read), so a longer token always comes to Fill's check.
	void SetWindow(ref char8* data, ref int windowStart, ref int end, int from)
	{
		data = Buffer - mBase;
		windowStart = mBase;
		end = mBase + mValid;
		if (mMaxTokenBytes > 0 && from + mMaxTokenBytes < end)
			end = Math.Max(from + mMaxTokenBytes, mBase);
	}

	/// Reads once into the free part of the buffer.
	void ReadMore() mut
	{
		// A full buffer reads nothing (a zero-length read would look like the end of the stream)
		if (mDone || mRaw == mCapacity)
			return;
		switch (mStream.TryRead(.(mState.mBuffer.Ptr + mRaw, mCapacity - mRaw)))
		{
		case .Ok(let read):
			if (read <= 0)
			{
				mDone = true;
				return;
			}
			mRaw += read;
			mBytesRead += read;
			if (mMaxInputBytes > 0 && mBytesRead > mMaxInputBytes)
				SetError(.ResourceLimitExceeded, scope $"The input exceeds MaxInputBytes ({mMaxInputBytes})", mMaxInputBytes, 0);
		case .Err:
			SetError(.IoError, "Reading the input failed", mBase + mRaw, 0);
		}
	}

	/// Validates the newly read bytes up to the last complete code point (all of them at the end of the
	/// input) and extends the window over them, or stops the stream at the first invalid one.
	void Validate() mut
	{
		char8* text = Buffer - mBase;
		int from = mBase + mValid;
		int to = mDone ? mBase + mRaw : JsonChar.CompleteSequencesEnd(text, from, mBase + mRaw);
		if (mState.mHasError)
			to = Math.Max(Math.Min(to, mState.mErrorOffset), from);
		let message = scope String();
		int bad = JsonChar.FindInvalid(text, from, to, message, let length);
		if (bad >= 0)
		{
			mValid = bad - mBase;
			SetError(.InvalidUtf8, message, bad, length);
			return;
		}
		mValid = to - mBase;
	}

	/// Records the input's first error and stops reading.
	void SetError(JsonErrorKind kind, StringView message, int offset, int length = 1) mut
	{
		mDone = true;
		if (mState.mHasError)
			return;
		Locate(offset, out mState.mErrorLine, out mState.mErrorColumn);
		mState.mErrorKind = kind;
		mState.mErrorMessage.Set(message);
		mState.mErrorOffset = offset;
		mState.mErrorLength = length;
		mState.mHasError = true;
	}

	public bool TryGetInputError(out JsonParseError error)
	{
		error = mState.mHasError ? mState.MakeError() : default;
		return mState.mHasError;
	}

	public bool HasInputError => mState.mHasError;

	public bool IsWhole
	{
		[Inline]
		get => false;
	}

	public bool Locate(int offset, out int line, out int column) mut
	{
		line = 0;
		column = 0;
		if (offset < mLines.mPos)
			return false;
		int target = Math.Min(offset, mBase + mRaw);
		char8* text = Buffer - mBase;
		if (target >= mLocated.mPos && target >= mLocated.mLineStart)
		{
			mLocated.Locate(text, target, mBase + mRaw, out line, out column);
			return true;
		}
		// Behind the forward count (an error at an earlier offset): count from the dropped bytes
		var lines = mLines;
		lines.Locate(text, target, mBase + mRaw, out line, out column);
		return true;
	}
}
