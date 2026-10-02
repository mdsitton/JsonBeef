using System;
using System.Collections;
using System.IO;
using internal JsonBeef;

namespace JsonBeef;

[AllowDuplicates]
internal enum JsonNodeFlags : uint8
{
	None = 0,
	/// String: the text is an entry of the document's string table (decoded or copied), not a view of
	/// its copy of the source. Number with Lexeme: the same for the token's text.
	ValueInTable = 1,
	/// The member name is an entry of the string table.
	NameInTable = 2,
	/// Number: the payload is the token's text (a big integer, or a float beyond a double's range).
	Lexeme = 4,
	/// Number: the integer token `-0`.
	NegativeZero = 8,
	/// Removed from the document (a duplicate dropped by a JsonDuplicateNames policy); its slot is not
	/// reused until the document is cleared.
	Removed = 16
}

/// A value's slot in the document's node table, 40 bytes. Links are node IDs; 0 means none (slot 0 is
/// unused, so the root is 1). Children are a doubly linked list in document order, built in preorder.
internal struct JsonNodeRecord
{
	/// Number: the int64, uint64 or double bits, or with Lexeme the token's text. String: its text.
	/// Array, Object: the last child's ID (low 32 bits) and the child count (high 32 bits). Text is a
	/// reference: an offset into the source copy, or with the table flag an index into the string table
	/// (low 32 bits), and the length (high 32 bits).
	public uint64 mPayload;
	/// A member's name (a text reference); 0 in arrays and for the root.
	public uint64 mName;
	public uint32 mParent;
	public uint32 mFirstChild;
	public uint32 mNext;
	public uint32 mPrev;
	public JsonValueKind mKind;
	public JsonNodeFlags mFlags;
	public JsonNumberKind mNumberKind;

	public uint32 LastChild
	{
		[Inline]
		get => (uint32)mPayload;
	}

	public int Count
	{
		[Inline]
		get => (int)(mPayload >> 32);
	}

	public bool IsContainer
	{
		[Inline]
		get => mKind >= .Array;
	}
}

/// @brief A JSON document: one value and everything under it, mutable, with handles (`JsonNode`) to
/// its values.
///
/// The document owns all of its text and values. Values are handed out as `JsonNode` handles (the
/// document plus a node ID) that read the document directly; a handle stays valid until the document is
/// cleared or read again, and `IsValid` tells. Strings returned by the document view its storage and
/// share that lifetime. Objects keep every member in document order, duplicates included (unless
/// `JsonReadConfig.DuplicateNames` says otherwise); a lookup by name finds the last.
///
/// ```
/// let doc = scope JsonDocument();
/// Try!(doc.Read(text));
/// let name = doc.Root["user"]["name"].GetString();
/// for (let member in doc.Root.Members)
///     Console.WriteLine(member.Name);
/// ```
public class JsonDocument
{
	/// Objects with more members than this get a hash index on their first lookup.
	internal const int cIndexThreshold = 16;

	/// @brief This document's read configuration, used by the Read and ReadFile overloads that take no
	/// config.
	public JsonReadConfig ReadConfig = .();

	internal JsonStack<JsonNodeRecord> mNodes ~ delete _;
	/// The copy of the source the reader read (strings without escapes view it) and the text of the
	/// string table; both live in the arena.
	internal JsonTextArena mText ~ delete _;
	internal List<StringView> mStrings ~ delete _;
	internal char8* mSource;
	internal int mSourceLength;
	internal uint32 mRoot;
	/// Changes on every Clear and Read, so handles from before can tell they are stale.
	internal uint32 mGeneration;
	/// Member indexes of large objects, by object ID.
	internal Dictionary<uint32, JsonMemberIndex> mIndexes ~ DeleteDictionaryAndValues!(_);
	String mSourceName ~ delete _;
	/// The errors of the last read with CollectErrors (their text in the arena).
	List<JsonParseError> mErrors ~ delete _;
	/// The reader behind Read, kept for its buffers.
	JsonReader mReader ~ delete _;

	/// @brief Create an empty document.
	public this()
	{
		mNodes = new .(64);
		mText = new .(64 * 1024);
		mStrings = new .();
		mIndexes = new .();
		mSourceName = new .();
		mErrors = new .();
		mNodes.Add(default);
		mGeneration = 1;
	}

	/// @brief The errors of the last read with JsonReadConfig.CollectErrors, in order (empty otherwise,
	/// or when it read without error); Read returns the first. Their text belongs to the document (valid
	/// until it is cleared or read again; JsonDiagnostic copies one).
	public Span<JsonParseError> Errors => mErrors;

	/// Keeps an error of a read with CollectErrors, its text copied into the arena.
	void AddError(JsonParseError error)
	{
		var error;
		error.mMessage = mText.Copy(error.mMessage);
		error.mSource = mText.Copy(error.mSource);
		mErrors.Add(error);
	}

	/// @brief The document's value; an invalid handle when the document is empty.
	public JsonNode Root => mRoot != 0 ? JsonNode(this, mRoot) : default;

	/// @brief Whether the document has no value (before a read, after Clear or a failed read).
	public bool IsEmpty => mRoot == 0;

	/// @brief The name of the source last read (JsonReadConfig.SourceName, or ReadFile's path); empty if
	/// unnamed.
	public StringView SourceName => mSourceName;

	/// @brief The number of value slots in use (removed values included until the document is cleared).
	public int NodeCount => mNodes.Count - 1;

	/// @brief Remove everything. The document keeps its memory for the next read.
	public void Clear()
	{
		mText.Reset();
		mStrings.Clear();
		mNodes.Clear();
		mNodes.Add(default);
		for (let index in mIndexes.Values)
			delete index;
		mIndexes.Clear();
		mSource = null;
		mSourceLength = 0;
		mRoot = 0;
		mSourceName.Clear();
		mRanges.Clear();
		mLineStarts.Clear();
		mErrors.Clear();
		ClearStyle();
		mGeneration++;
	}

	/// @brief Remove everything and free the memory kept for the next read (after an unusually large
	/// document).
	public void Release()
	{
		Clear();
		mText.Release();
		mStrings.Capacity = 0;
		mNodes.TrimExcess(64);
		delete mReader;
		mReader = null;
	}

	/// @brief The value with the given ID, if it is in this document.
	/// @param id A node ID, from `JsonNode.Id`.
	/// @return The value, or an invalid handle if the ID is unknown or its value was removed.
	public JsonNode GetNode(JsonNodeId id)
	{
		return IsLive(id.mValue) ? JsonNode(this, id.mValue) : default;
	}

	[Inline]
	internal bool IsLive(uint32 id)
	{
		return id != 0 && id < (uint32)mNodes.Count && !mNodes[id].mFlags.HasFlag(.Removed);
	}

	// Text

	[Inline]
	internal static uint64 MakeRef(int offset, int length)
	{
		return (uint64)(uint32)offset | ((uint64)(uint32)length << 32);
	}

	/// The text a reference names.
	[Inline]
	internal StringView TextOf(uint64 textRef, bool inTable)
	{
		if (inTable)
			return mStrings[(int)(uint32)textRef];
		return .(mSource + (int)(uint32)textRef, (int)(textRef >> 32));
	}

	/// A reference to a copy of `text` in the string table.
	internal uint64 AddText(StringView text)
	{
		int index = mStrings.Count;
		mStrings.Add(mText.Copy(text));
		return MakeRef(index, text.Length);
	}

	/// A member's name ("" for array elements and the root).
	[Inline]
	internal StringView NameOf(uint32 id)
	{
		ref JsonNodeRecord node = ref mNodes[id];
		return TextOf(node.mName, node.mFlags.HasFlag(.NameInTable));
	}

	/// A string's text, or a number's token (with Lexeme).
	[Inline]
	internal StringView ValueTextOf(uint32 id)
	{
		ref JsonNodeRecord node = ref mNodes[id];
		return TextOf(node.mPayload, node.mFlags.HasFlag(.ValueInTable));
	}

	// Reading

	/// @brief Replace the document's content with the JSON text in `text`, using ReadConfig.
	/// @param text The document (UTF-8; a leading BOM is skipped).
	/// @return .Ok, or the first error; the document is then empty.
	public Result<void, JsonParseError> Read(StringView text)
	{
		return Read(text, ReadConfig);
	}

	/// @brief Replace the document's content with the JSON text in `text`. The document copies it once;
	/// strings without escapes are views of the copy.
	/// @param text The document (UTF-8).
	/// @param config The dialect, limits, duplicate-name policy and source name.
	/// @return .Ok, or the first error; the document is then empty.
	public Result<void, JsonParseError> Read(StringView text, JsonReadConfig config)
	{
		let readerConfig = BeginRead(config);
		StringView owned = text;
		// Too large: the reader reports it without the copy
		if (config.MaxInputBytes <= 0 || text.Length <= config.MaxInputBytes)
			owned = mText.Copy(text);
		return ReadOwned(owned, readerConfig, config);
	}

	/// Reads `owned`, which lives as long as the document (in its arena).
	Result<void, JsonParseError> ReadOwned(StringView owned, JsonReadConfig readerConfig, JsonReadConfig config)
	{
		mSource = owned.Ptr;
		mSourceLength = owned.Length;
		mNodes.Reserve(owned.Length / 8 + 16);
		// The fast build first (JsonDocument.Fast.bf); at any problem, the reader reads again and reports it
		if (config.DuplicateNames == .KeepAll && config.MetadataMode == .None && !config.CollectErrors && !config.IJson &&
			(config.MaxInputBytes <= 0 || owned.Length <= config.MaxInputBytes))
		{
			if (JsonInputStart.Check(owned.Ptr, owned.Length, config.AllowBom) case .Ok(let start) && FastBuild(owned.Ptr, start, owned.Length, config))
				return .Ok;
			mNodes.Clear();
			mNodes.Add(default);
			mStrings.Clear();
			mRoot = 0;
		}
		mReader.Reset(owned, readerConfig);
		let result = Build(mReader, mReader.mBytes, true, config);
		if (config.MetadataMode == .PreserveStyle && result case .Ok)
			FinishStyle();
		return EndRead(result);
	}

	/// @brief Replace the document's content with the JSON text read from a stream, using ReadConfig.
	/// @param stream The document, read from its current position.
	/// @return .Ok, or the first error; the document is then empty.
	public Result<void, JsonParseError> Read(Stream stream)
	{
		return Read(stream, ReadConfig);
	}

	/// @brief Replace the document's content with the JSON text read from a stream, through a buffer of
	/// `config.StreamBufferBytes`: memory for the input stays bounded by the buffer and the longest token
	/// (see `config.MaxTokenBytes`); the document itself grows with the content, every string copied.
	/// @param stream The document, read from its current position.
	/// @param config The dialect, limits, duplicate-name policy, buffer size and source name.
	/// @return .Ok, or the first error (IoError if reading fails); the document is then empty.
	public Result<void, JsonParseError> Read(Stream stream, JsonReadConfig config)
	{
		if (config.MetadataMode == .PreserveStyle)
		{
			// The document keeps the whole source anyway: read it all, then as memory input
			let bytes = scope List<uint8>();
			uint8[4096] chunk = ?;
			while (true)
			{
				switch (stream.TryRead(.(&chunk, chunk.Count)))
				{
				case .Ok(let read):
					if (read <= 0)
						return Read(StringView((char8*)bytes.Ptr, bytes.Count), config);
					bytes.AddRange(Span<uint8>(&chunk, read));
					if (config.MaxInputBytes > 0 && bytes.Count > config.MaxInputBytes)
						return FailRead(.ResourceLimitExceeded, scope $"The input exceeds MaxInputBytes ({config.MaxInputBytes})", config);
				case .Err:
					return FailRead(.IoError, "Reading the input failed", config);
				}
			}
		}
		let readerConfig = BeginRead(config);
		mReader.Reset(stream, readerConfig);
		return EndRead(Build(mReader, mReader.mStream, false, config));
	}

	/// @brief Replace the document's content with the JSON text in a file, using ReadConfig.
	/// @param path The file's path; errors name it unless ReadConfig.SourceName is set.
	/// @return .Ok, or the first error (IoError if the file cannot be read); the document is then empty.
	public Result<void, JsonParseError> ReadFile(StringView path)
	{
		return ReadFile(path, ReadConfig);
	}

	/// @brief Replace the document's content with the JSON text in a file: loaded whole into the
	/// document's memory, or with `config.StreamBufferBytes` set, streamed through a buffer of that size.
	/// @param path The file's path; errors name it unless config.SourceName is set.
	/// @param config The dialect, limits, duplicate-name policy, buffer size and source name.
	/// @return .Ok, or the first error (IoError if the file cannot be read); the document is then empty.
	public Result<void, JsonParseError> ReadFile(StringView path, JsonReadConfig config)
	{
		var config;
		if (config.SourceName.IsEmpty)
			config.SourceName = path;
		let file = scope FileStream();
		if (file.Open(path, .Read, .Read) case .Err)
			return FailRead(.IoError, "Cannot open the file", config);
		if (config.StreamBufferBytes > 0)
			return Read(file, config);
		let readerConfig = BeginRead(config);
		int64 length = file.Length;
		if (config.MaxInputBytes > 0 && length > config.MaxInputBytes)
			return FailRead(.ResourceLimitExceeded, scope $"The input ({length} bytes) exceeds MaxInputBytes ({config.MaxInputBytes})", config);
		// Straight into the document's memory: the only copy
		char8* bytes = length > 0 ? mText.Alloc((int)length) : null;
		int filled = 0;
		while (filled < length)
		{
			switch (file.TryRead(.((uint8*)bytes + filled, (int)length - filled)))
			{
			case .Ok(let read):
				if (read <= 0)
					return FailRead(.IoError, "The file ended before its size", config);
				filled += read;
			case .Err:
				return FailRead(.IoError, "Reading the file failed", config);
			}
		}
		return ReadOwned(.(bytes, filled), readerConfig, config);
	}

	/// Clears the document and returns an error that names the source.
	Result<void, JsonParseError> FailRead(JsonErrorKind kind, StringView message, JsonReadConfig config)
	{
		Clear();
		mSourceName.Set(config.SourceName);
		var error = JsonParseError(kind, message, 0, 0, 0, 0);
		if (!config.SourceName.IsEmpty)
			error.SetSource(config.SourceName);
		return .Err(error);
	}

	/// Clears the document for a read and returns the reader's config, naming the document's copy of the
	/// source name.
	JsonReadConfig BeginRead(JsonReadConfig config)
	{
		Clear();
		mSourceName.Set(config.SourceName);
		var readerConfig = config;
		readerConfig.SourceName = mSourceName;
		if (mReader == null)
			mReader = new JsonReader();
		return readerConfig;
	}

	Result<void, JsonParseError> EndRead(Result<void, JsonParseError> result)
	{
		// Nothing may keep viewing the caller's input or stream
		mReader.Reset(StringView());
		// Collect-errors keeps what was read
		if (result case .Err && mErrors.IsEmpty)
		{
			let sourceName = scope String(mSourceName);
			Clear();
			mSourceName.Set(sourceName);
		}
		return result;
	}

	/// Builds the records from the reader's tokens in preorder. `viewSource`: the reader reads the
	/// document's copy of the source, so unescaped text is a view of it; otherwise (a stream) every
	/// string is copied into the string table.
	Result<void, JsonParseError> Build<TCursor>(JsonReader reader, JsonReaderCore<TCursor> core, bool viewSource, JsonReadConfig config) where TCursor : IJsonCursor
	{
		uint32 parent = 0;
		bool parentIsObject = false;
		uint64 name = 0;
		bool nameInTable = false;
		bool hasName = false;
		bool discard = false;
		// I-JSON: no duplicates, whatever the policy
		JsonDuplicateNames duplicates = config.IJson ? .Error : config.DuplicateNames;
		bool positions = config.MetadataMode != .None;
		bool preserve = config.MetadataMode == .PreserveStyle;
		// Positions: the pending name's range, and the line and column of what a stream read locates
		int64 nameOffset = 0;
		int32 nameLength = 0;
		int nameLine = 0;
		int nameColumn = 0;
		if (positions)
			mRanges.Add(.());
		while (true)
		{
			JsonToken token;
			switch (core.NextToken())
			{
			case .Ok(let next):
				token = next;
			case .Err:
				if (!config.CollectErrors)
					return .Err(core.mError);
				// Kept with its text; the read goes on unless the error stopped it
				AddError(core.mError);
				if (core.IsStopped)
					return .Err(mErrors[0]);
				continue;
			}
			switch (token)
			{
			case .PropertyName:
				if (config.MaxMembers > 0 && mNodes[parent].Count >= config.MaxMembers)
					return .Err(reader.MakeError(.ResourceLimitExceeded, scope $"The object has more than MaxMembers ({config.MaxMembers}) members", core.mTokenStart, core.mTokenEnd - core.mTokenStart));
				// (With CollectErrors a name whose value was broken is followed by the next name: dropped)
				hasName = true;
				name = TextRef(core, viewSource, out nameInTable);
				if (positions)
				{
					nameOffset = core.mTokenStart;
					nameLength = (int32)(core.mTokenEnd - core.mTokenStart);
					if (!viewSource)
						reader.Locate(core.mTokenStart, out nameLine, out nameColumn);
				}
				if (duplicates != .KeepAll)
				{
					uint32 existing = FindMember(parent, core.mValue);
					if (existing != 0)
					{
						switch (duplicates)
						{
						case .Error:
							let message = scope String();
							message.Append("The member name ");
							AppendQuoted(message, core.mValue);
							message.Append(config.IJson ? " appears twice in this object (I-JSON, RFC 7493 §2.3)" : " appears twice in this object (JsonDuplicateNames.Error)");
							return .Err(reader.MakeError(.DuplicateName, message, core.mTokenStart, core.mTokenEnd - core.mTokenStart));
						case .LastWins:
							Unlink(existing);
							mNodes[existing].mFlags |= .Removed;
						case .FirstWins:
							discard = true;
						default:
						}
					}
				}
				continue;
			case .EndObject, .EndArray:
				if (positions)
					mRanges[parent].mLength = (int32)(core.mTokenEnd - mRanges[parent].mOffset);
				if (preserve)
					CaptureEnd(parent, core.mTokenStart, core.mTokenEnd);
				parent = mNodes[parent].mParent;
				parentIsObject = parent != 0 && mNodes[parent].mKind == .Object;
				hasName = false;
				discard = false;
				continue;
			case .EndOfDocument:
				if (!mErrors.IsEmpty)
					return .Err(mErrors[0]);
				return .Ok;
			default:
			}
			if (config.MaxNodes > 0 && mNodes.Count > config.MaxNodes)
				return .Err(reader.MakeError(.ResourceLimitExceeded, scope $"The document has more than MaxNodes ({config.MaxNodes}) values", core.mTokenStart, core.mTokenEnd - core.mTokenStart));
			uint32 id = (uint32)mNodes.Count;
			ref JsonNodeRecord node = ref mNodes.AddDefault();
			node.mParent = parent;
			switch (token)
			{
			case .StartObject:
				node.mKind = .Object;
			case .StartArray:
				node.mKind = .Array;
			case .String:
				node.mKind = .String;
				node.mPayload = TextRef(core, viewSource, var inTable);
				if (inTable)
					node.mFlags |= .ValueInTable;
			case .Number:
				node.mKind = .Number;
				SetNumber(ref node, core, viewSource);
			case .True:
				node.mKind = .True;
			case .False:
				node.mKind = .False;
			case .Null:
				node.mKind = .Null;
			default:
			}
			if (positions)
			{
				JsonRangeRecord range = .();
				range.mOffset = core.mTokenStart;
				range.mLength = (int32)(core.mTokenEnd - core.mTokenStart);
				range.mNameLength = -1;
				if (parentIsObject && hasName)
				{
					range.mNameOffset = nameOffset;
					range.mNameLength = nameLength;
					range.mNameLine = (int32)nameLine;
					range.mNameColumn = (int32)nameColumn;
				}
				if (!viewSource)
				{
					reader.Locate(core.mTokenStart, var line, var column);
					range.mLine = (int32)line;
					range.mColumn = (int32)column;
				}
				mRanges.Add(range);
			}
			if (preserve)
			{
				bool named = parentIsObject && hasName;
				CaptureValue(id, named ? (int)nameOffset : core.mTokenStart, named ? (int)(nameOffset + nameLength) : -1,
					core.mTokenStart, core.mTokenEnd);
			}
			if (parent == 0)
				mRoot = id;
			else
			{
				if (parentIsObject)
				{
					// (A value in an object always follows its name, but after recovery: then it has none)
					node.mName = hasName ? name : 0;
					if (nameInTable && hasName)
						node.mFlags |= .NameInTable;
					hasName = false;
				}
				if (discard)
				{
					// FirstWins: a later duplicate is read (and checked) but never linked
					node.mFlags |= .Removed;
					discard = false;
				}
				else
				{
					AppendChild(parent, id);
					if (parentIsObject && duplicates != .KeepAll)
						IndexMember(parent, id);
				}
			}
			if (node.IsContainer)
			{
				parentIsObject = node.mKind == .Object;
				parent = id;
			}
		}
	}

	/// A reference to the current token's text: a view of the source when possible, else a copy.
	[Inline]
	uint64 TextRef<TCursor>(JsonReaderCore<TCursor> core, bool viewSource, out bool inTable) where TCursor : IJsonCursor
	{
		StringView text = core.mValue;
		if (viewSource && !core.mEscaped)
		{
			inTable = false;
			return MakeRef(text.Ptr - mSource, text.Length);
		}
		inTable = true;
		return AddText(text);
	}

	[Inline]
	void SetNumber<TCursor>(ref JsonNodeRecord node, JsonReaderCore<TCursor> core, bool viewSource) where TCursor : IJsonCursor
	{
		node.mNumberKind = core.mNumberKind;
		switch (core.mNumberKind)
		{
		case .Integer:
			node.mPayload = (uint64)core.mInteger;
			if (core.mInteger == 0 && core.mValue[0] == '-')
				node.mFlags |= .NegativeZero;
		case .UInteger:
			node.mPayload = (uint64)core.mInteger;
		case .Float:
			if (core.GetDouble(let value))
			{
				node.mPayload = JsonNumber.ToBits(value);
				return;
			}
			// Beyond a double's range: the text is kept, the conversion fails
			node.mPayload = TextRef(core, viewSource, var inTable);
			node.mFlags |= .Lexeme;
			if (inTable)
				node.mFlags |= .ValueInTable;
		case .BigInteger:
			node.mPayload = TextRef(core, viewSource, var inTable);
			node.mFlags |= .Lexeme;
			if (inTable)
				node.mFlags |= .ValueInTable;
		case .NonFinite:
			node.mPayload = JsonNumber.ToBits(JsonNumber.NonFiniteValue(core.mRaw));
		}
	}

	// Links

	/// Appends `id` as the last child of `parent`.
	[Inline]
	internal void AppendChild(uint32 parent, uint32 id)
	{
		ref JsonNodeRecord container = ref mNodes[parent];
		uint32 last = container.LastChild;
		if (last == 0)
			container.mFirstChild = id;
		else
		{
			mNodes[last].mNext = id;
			mNodes[id].mPrev = last;
		}
		container.mPayload = ((uint64)(uint32)(container.Count + 1) << 32) | id;
	}

	/// Takes `id` out of its parent's children (its subtree goes with it).
	internal void Unlink(uint32 id)
	{
		ref JsonNodeRecord node = ref mNodes[id];
		uint32 parent = node.mParent;
		ref JsonNodeRecord container = ref mNodes[parent];
		uint32 last = container.LastChild;
		if (node.mPrev != 0)
			mNodes[node.mPrev].mNext = node.mNext;
		else
			container.mFirstChild = node.mNext;
		if (node.mNext != 0)
			mNodes[node.mNext].mPrev = node.mPrev;
		else
			last = node.mPrev;
		container.mPayload = ((uint64)(uint32)(container.Count - 1) << 32) | last;
		node.mNext = 0;
		node.mPrev = 0;
	}

	// Members

	/// The last member of object `id` named `name`, or 0.
	internal uint32 FindMember(uint32 id, StringView name)
	{
		ref JsonNodeRecord node = ref mNodes[id];
		if (node.Count > cIndexThreshold)
			return GetIndex(id).Find(this, name, JsonMemberIndex.Hash(name));
		uint32 child = node.LastChild;
		while (child != 0)
		{
			ref JsonNodeRecord member = ref mNodes[child];
			if ((int)(member.mName >> 32) == name.Length)
			{
				let memberName = TextOf(member.mName, member.mFlags.HasFlag(.NameInTable));
				if (JsonChar.EqualBytes(memberName.Ptr, name.Ptr, name.Length))
					return child;
			}
			child = member.mPrev;
		}
		return 0;
	}

	/// The member index of object `id`, built now if it has none.
	internal JsonMemberIndex GetIndex(uint32 id)
	{
		if (mIndexes.TryGetValue(id, let existing))
			return existing;
		let index = new JsonMemberIndex();
		uint32 child = mNodes[id].mFirstChild;
		while (child != 0)
		{
			index.Set(this, child, NameOf(child));
			child = mNodes[child].mNext;
		}
		mIndexes[id] = index;
		return index;
	}

	/// Adds member `id` of object `parent` to its index, if it has one or now needs one.
	void IndexMember(uint32 parent, uint32 id)
	{
		if (mIndexes.TryGetValue(parent, let index))
			index.Set(this, id, NameOf(id));
		else if (mNodes[parent].Count > cIndexThreshold)
			GetIndex(parent);
	}

	/// Drops the index of object `id` (its members changed).
	internal void DropIndex(uint32 id)
	{
		if (mIndexes.GetAndRemove(id) case .Ok(let entry))
			delete entry.value;
	}

	/// Appends `text` in backquotes for a message, shortened past 64 bytes.
	static void AppendQuoted(String output, StringView text)
	{
		output.Append('`');
		if (text.Length <= 64)
			output.Append(text);
		else
		{
			int cut = 64;
			while (cut > 0 && ((uint8)text[cut] & 0xC0) == 0x80)
				cut--;
			output.Append(text.Substring(0, cut));
			output.Append("…");
		}
		output.Append('`');
	}
}
