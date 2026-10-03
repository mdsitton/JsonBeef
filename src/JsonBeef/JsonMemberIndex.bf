using System;
using FormatCore;
using internal FormatCore;
using internal JsonBeef;

namespace JsonBeef;

/// The name index of a large object: FormatCore's OpenIdIndex (an open-addressing table of member IDs
/// and name hashes, at most half full, names compared only when hashes match) with the document's
/// member names as its keys. A name maps to the last member that has it (lookups find the last
/// duplicate). The hash is seeded per index, so names chosen to collide cannot be prepared in advance
/// (hash flooding, spec-reference §13).
internal class JsonMemberIndex
{
	/// The member names of a document, by node ID.
	struct MemberNames : IKeySource
	{
		JsonDocument mDocument;

		public this(JsonDocument document)
		{
			mDocument = document;
		}

		[Inline]
		public StringView KeyOf(uint32 id) => mDocument.NameOf(id);
	}

	OpenIdIndex mIndex ~ _.Dispose();

	public this()
	{
		mIndex = .(ByteHash.NewSeed());
	}

	/// Maps `name` to member `id` (replacing an earlier member of that name).
	public void Set(JsonDocument document, uint32 id, StringView name)
	{
		mIndex.Set(MemberNames(document), name, id);
	}

	/// The member named `name`, or 0.
	[Inline]
	public uint32 Find(JsonDocument document, StringView name)
	{
		return mIndex.Find(MemberNames(document), name);
	}
}
