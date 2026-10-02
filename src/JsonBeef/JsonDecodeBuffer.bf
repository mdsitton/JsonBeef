using System;
using internal JsonBeef;

namespace JsonBeef;

/// The bytes a string with escapes decodes to. The decoding loops write through a local pointer
/// `dest`, checking `dest + needed > limit` before each write and calling `Grow` (out of line) only
/// then, instead of a String.Append call per escape and per run of plain text between escapes, which
/// dominated escape-heavy input.
internal class JsonDecodeBuffer
{
	char8* mPtr;
	int mCapacity;

	public this(int capacity = 256)
	{
		mCapacity = capacity;
		mPtr = new char8[capacity]*;
	}

	public ~this()
	{
		delete mPtr;
	}

	/// The first byte (valid until the buffer grows).
	public char8* Ptr
	{
		[Inline]
		get => mPtr;
	}

	/// One past the last byte.
	public char8* Limit
	{
		[Inline]
		get => mPtr + mCapacity;
	}

	/// Grows the buffer so that `needed` more bytes fit at `dest` (the bytes before it kept), moving
	/// `dest` and `limit` with it.
	[NoInline]
	public void Grow(ref char8* dest, ref char8* limit, int needed)
	{
		int length = dest - mPtr;
		int capacity = Math.Max(mCapacity * 2, length + needed);
		char8* grown = new char8[capacity]*;
		Internal.MemCpy(grown, mPtr, length);
		delete mPtr;
		mPtr = grown;
		mCapacity = capacity;
		dest = mPtr + length;
		limit = mPtr + mCapacity;
	}

	/// Copies `count` bytes from `source` to `dest` (room for `count + 16` made first). A run of up to 16
	/// bytes is copied as two 8-byte words when `source` may be read 16 bytes far (`readable`): escapes
	/// come in clusters, so most runs between them are short and a memcpy call would cost more.
	[Inline]
	public static void CopyRun(char8* dest, char8* source, int count, bool readable)
	{
		if (count <= 16 && readable)
		{
			*(uint64*)dest = *(uint64*)source;
			*(uint64*)(dest + 8) = *(uint64*)(source + 8);
		}
		else
			Internal.MemCpy(dest, source, count);
	}
}
