using System;
using System.Collections;
using internal JsonBeef;

namespace JsonBeef;

/// Plain bytes in chunks that never move, for text with one lifetime (a document's), ported from
/// XmlBeef's XmlTextArena. `Reset` keeps every chunk for reuse, so reading document after document
/// allocates nothing once the arena has grown to the largest (freeing instead lets the heap shrink, and
/// the next read page-faults every page back in: TomlBeef measured up to 40% of parse time).
internal class JsonTextArena
{
	List<uint8[]> mChunks ~ DeleteContainerAndItems!(_);
	/// The chunk being filled (-1: none yet since the last reset), where it is filled to, and its end.
	int mCurrent = -1;
	uint8* mNext;
	uint8* mLimit;
	int mFirstSize;

	public this(int firstChunkBytes = 4096)
	{
		mChunks = new .();
		mFirstSize = firstChunkBytes;
	}

	/// @brief `size` bytes (unaligned), valid until the arena is reset or deleted.
	[Inline]
	public char8* Alloc(int size)
	{
		if (mNext == null || (int)(void*)mLimit - (int)(void*)mNext < size)
			NextChunk(size);
		char8* p = (char8*)mNext;
		mNext += size;
		return p;
	}

	/// Moves to the next kept chunk that holds `size` bytes, or adds one (doubling, from mFirstSize up
	/// to 1 MB, or `size` if that is more).
	void NextChunk(int size)
	{
		while (++mCurrent < mChunks.Count)
		{
			let chunk = mChunks[mCurrent];
			if (chunk.Count >= size)
			{
				mNext = chunk.Ptr;
				mLimit = chunk.Ptr + chunk.Count;
				return;
			}
		}
		int chunkSize = mChunks.IsEmpty ? mFirstSize : Math.Clamp(mChunks.Back.Count * 2, 4096, 1 << 20);
		let chunk = new uint8[Math.Max(chunkSize, size)];
		mChunks.Add(chunk);
		mCurrent = mChunks.Count - 1;
		mNext = chunk.Ptr;
		mLimit = chunk.Ptr + chunk.Count;
	}

	/// @brief Forget everything allocated, keeping the chunks for the next use.
	public void Reset()
	{
		mCurrent = -1;
		mNext = null;
		mLimit = null;
	}

	/// @brief Forget everything allocated and free the chunks.
	public void Release()
	{
		Reset();
		ClearAndDeleteItems!(mChunks);
		mChunks.Capacity = 0;
	}

	/// @brief The bytes of every chunk.
	public int ReservedBytes
	{
		get
		{
			int total = 0;
			for (let chunk in mChunks)
				total += chunk.Count;
			return total;
		}
	}

	/// @brief A copy of `text` in the arena.
	public StringView Copy(StringView text)
	{
		if (text.IsEmpty)
			return "";
		char8* bytes = Alloc(text.Length);
		Internal.MemCpy(bytes, text.Ptr, text.Length);
		return .(bytes, text.Length);
	}
}
