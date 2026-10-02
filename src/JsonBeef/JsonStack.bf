using System;
using internal JsonBeef;

namespace JsonBeef;

/// A growable array of values (XmlBeef's XmlStack) for the document's node table and the builder's
/// lists: `Add`, `PopBack`, `Back` and the indexer are inlined, which corlib's List.Add and Count setter
/// are not (each showed up in XmlBeef's profiles).
internal class JsonStack<T> where T : struct
{
	T[] mItems ~ delete _;
	int mCount;

	public this(int capacity = 16)
	{
		mItems = new T[Math.Max(capacity, 1)];
	}

	/// The number of items; setting it lower (never higher) drops the items above.
	public int Count
	{
		[Inline]
		get => mCount;
		[Inline]
		set => mCount = value;
	}

	public bool IsEmpty
	{
		[Inline]
		get => mCount == 0;
	}

	[Inline]
	public void Add(T item)
	{
		if (mCount == mItems.Count)
			Grow();
		mItems[mCount++] = item;
	}

	/// Adds a default item and returns it.
	[Inline]
	public ref T AddDefault()
	{
		if (mCount == mItems.Count)
			Grow();
		mItems[mCount] = default;
		return ref mItems[mCount++];
	}

	/// Makes room for at least `capacity` items.
	public void Reserve(int capacity)
	{
		if (capacity <= mItems.Count)
			return;
		T[] old = mItems;
		mItems = new T[Math.Max(capacity, old.Count * 2)];
		Internal.MemCpy(mItems.Ptr, old.Ptr, mCount * strideof(T), alignof(T));
		delete old;
	}

	/// Frees the capacity beyond the items (keeping at least `minimum`).
	public void TrimExcess(int minimum = 16)
	{
		int capacity = Math.Max(mCount, minimum);
		if (capacity >= mItems.Count)
			return;
		T[] old = mItems;
		mItems = new T[capacity];
		Internal.MemCpy(mItems.Ptr, old.Ptr, mCount * strideof(T), alignof(T));
		delete old;
	}

	/// The bytes of the array.
	public int ReservedBytes => mItems.Count * strideof(T);

	void Grow()
	{
		Reserve(mItems.Count * 2);
	}

	[Inline]
	public T PopBack()
	{
		return mItems[--mCount];
	}

	public ref T Back
	{
		[Inline]
		get => ref mItems[mCount - 1];
	}

	public ref T this[int index]
	{
		[Inline]
		get => ref mItems[index];
	}

	/// The first item's address (valid until the stack grows).
	public T* Ptr
	{
		[Inline]
		get => mItems.Ptr;
	}

	[Inline]
	public void Clear()
	{
		mCount = 0;
	}

	/// The items as a span (valid until the stack changes).
	public Span<T> Span => .(mItems.Ptr, mCount);
}
