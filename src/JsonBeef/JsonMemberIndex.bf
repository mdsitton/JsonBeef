using System;
using internal JsonBeef;

namespace JsonBeef;

/// The name index of a large object (TomlBeef's TomlEntryMap pattern): an open-addressing table, a
/// power of two probed linearly and at most half full, each slot holding a member's ID and its name's
/// hash, so a probe compares names only when the hashes match. A name maps to the last member that has
/// it (lookups find the last duplicate). The hash is seeded per process, so names chosen to collide
/// cannot be prepared in advance (hash flooding, spec-reference §13).
internal class JsonMemberIndex
{
	/// A slot: member ID (low 32 bits; 0 = empty) and hash (high 32 bits).
	uint64[] mSlots ~ delete _;
	int mMask;
	int mCount;

	static uint64 sSeed = MakeSeed();

	static uint64 MakeSeed()
	{
		int local = 0;
		uint64 seed = (uint64)DateTime.UtcNow.Ticks ^ ((uint64)(int)(void*)&local << 17);
		return Mix(seed ^ 0x9E3779B97F4A7C15UL);
	}

	public this()
	{
		mSlots = new uint64[64];
		mMask = 63;
	}

	/// splitmix64's finalizer.
	[Inline]
	static uint64 Mix(uint64 x)
	{
		var x;
		x ^= x >> 30;
		x *= 0xBF58476D1CE4E5B9UL;
		x ^= x >> 27;
		x *= 0x94D049BB133111EBUL;
		x ^= x >> 31;
		return x;
	}

	/// The seeded hash of a name.
	public static uint32 Hash(StringView name)
	{
		char8* p = name.Ptr;
		int length = name.Length;
		uint64 h = sSeed ^ ((uint64)length * 0x9E3779B97F4A7C15UL);
		int i = 0;
		while (i + 8 <= length)
		{
			h = Mix(h ^ JsonChar.Load64(p + i));
			i += 8;
		}
		if (i < length)
		{
			uint64 tail = 0;
			for (int j = i; j < length; j++)
				tail = (tail << 8) | (uint8)p[j];
			h = Mix(h ^ tail ^ 0xFF);
		}
		return (uint32)(Mix(h) >> 32);
	}

	/// Maps `name` to member `id` (replacing an earlier member of that name).
	public void Set(JsonDocument document, uint32 id, StringView name)
	{
		if ((mCount + 1) * 2 > mMask + 1)
			Grow(document);
		uint32 hash = Hash(name);
		int pos = (int)hash & mMask;
		while (true)
		{
			uint64 slot = mSlots[pos];
			if (slot == 0)
			{
				mSlots[pos] = ((uint64)hash << 32) | id;
				mCount++;
				return;
			}
			if ((uint32)(slot >> 32) == hash && document.NameOf((uint32)slot) == name)
			{
				mSlots[pos] = ((uint64)hash << 32) | id;
				return;
			}
			pos = (pos + 1) & mMask;
		}
	}

	/// The member named `name` (whose hash is `hash`), or 0.
	public uint32 Find(JsonDocument document, StringView name, uint32 hash)
	{
		int pos = (int)hash & mMask;
		while (true)
		{
			uint64 slot = mSlots[pos];
			if (slot == 0)
				return 0;
			if ((uint32)(slot >> 32) == hash && document.NameOf((uint32)slot) == name)
				return (uint32)slot;
			pos = (pos + 1) & mMask;
		}
	}

	void Grow(JsonDocument document)
	{
		let old = mSlots;
		mSlots = new uint64[old.Count * 2];
		mMask = mSlots.Count - 1;
		for (let slot in old)
		{
			if (slot == 0)
				continue;
			int pos = (int)(uint32)(slot >> 32) & mMask;
			while (mSlots[pos] != 0)
				pos = (pos + 1) & mMask;
			mSlots[pos] = slot;
		}
		delete old;
	}
}
