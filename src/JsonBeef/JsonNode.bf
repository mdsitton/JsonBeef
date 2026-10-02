using System;
using System.Collections;
using internal JsonBeef;

namespace JsonBeef;

/// @brief A value's identity within its document: an index into the document's node table. Stable
/// while the value is in the document; not stable across reads.
public struct JsonNodeId : IHashable, IEquatable<JsonNodeId>
{
	internal uint32 mValue;

	internal this(uint32 value)
	{
		mValue = value;
	}

	/// @brief The ID as a number, for use as an index into per-node side tables (the root is 1).
	public uint32 Value => mValue;

	public int GetHashCode() => (int)mValue;
	public bool Equals(JsonNodeId other) => mValue == other.mValue;
	public static bool operator ==(JsonNodeId lhs, JsonNodeId rhs) => lhs.mValue == rhs.mValue;
	public static bool operator !=(JsonNodeId lhs, JsonNodeId rhs) => lhs.mValue != rhs.mValue;

	public override void ToString(String output)
	{
		mValue.ToString(output);
	}
}

/// @brief A value of a JsonDocument: a handle (the document and the value's ID) whose properties read
/// the document. Handles are small values; copy them freely.
///
/// A handle is valid while its document is not cleared or read again. Lookups (`this[name]`,
/// `this[index]`, `Find`), navigation (`Parent`, `FirstChild`, …), the `Is…` tests, `TryGet…` and the
/// `Get…(fallback)` getters accept an invalid handle (the default one a failed lookup returns) and
/// treat it as "no value", so lookups chain: `doc.Root["a"]["b"].GetInt64(0)`. `Kind`, `Count` and
/// `Name` need a valid handle (a fatal error otherwise); check `IsValid`.
public struct JsonNode : IEquatable<JsonNode>
{
	internal JsonDocument mDocument;
	internal uint32 mId;
	uint32 mGeneration;

	internal this(JsonDocument document, uint32 id)
	{
		mDocument = document;
		mId = id;
		mGeneration = document.mGeneration;
	}

	/// A handle to node `id`, or the invalid (default) handle for 0.
	[Inline]
	internal static JsonNode Of(JsonDocument document, uint32 id)
	{
		return id != 0 ? JsonNode(document, id) : default;
	}

	/// @brief Whether the handle refers to a value that is still in its document.
	public bool IsValid => mDocument != null && mGeneration == mDocument.mGeneration && mDocument.IsLive(mId);
	/// @brief The value's ID in its document.
	public JsonNodeId Id => .(mId);
	/// @brief The document the value belongs to.
	public JsonDocument Document => mDocument;

	internal ref JsonNodeRecord Record
	{
		get
		{
			if (!IsValid)
				Runtime.FatalError("JsonNode: the handle is invalid (no value, or a cleared document)");
			return ref mDocument.mNodes[mId];
		}
	}

	JsonNode Link(uint32 id) => Of(mDocument, id);

	/// @brief What the value is.
	public JsonValueKind Kind => Record.mKind;

	/// @brief Whether the value is `null` (false for an invalid handle).
	public bool IsNull => IsValid && mDocument.mNodes[mId].mKind == .Null;
	/// @brief Whether the value is `true` or `false`.
	public bool IsBool => IsValid && (mDocument.mNodes[mId].mKind == .True || mDocument.mNodes[mId].mKind == .False);
	/// @brief Whether the value is a number.
	public bool IsNumber => IsValid && mDocument.mNodes[mId].mKind == .Number;
	/// @brief Whether the value is a string.
	public bool IsString => IsValid && mDocument.mNodes[mId].mKind == .String;
	/// @brief Whether the value is an array.
	public bool IsArray => IsValid && mDocument.mNodes[mId].mKind == .Array;
	/// @brief Whether the value is an object.
	public bool IsObject => IsValid && mDocument.mNodes[mId].mKind == .Object;

	/// @brief Array: the number of elements. Object: the number of members (duplicates included). 0 for
	/// other values.
	public int Count
	{
		get
		{
			ref JsonNodeRecord node = ref Record;
			return node.IsContainer ? node.Count : 0;
		}
	}

	/// @brief A member's name (decoded); empty for array elements and the root.
	public StringView Name
	{
		get
		{
			if (!IsValid)
				Runtime.FatalError("JsonNode: the handle is invalid (no value, or a cleared document)");
			return mDocument.NameOf(mId);
		}
	}

	/// @brief Whether the value is a member of an object (it has a name, perhaps empty).
	public bool IsMember => IsValid && mDocument.mNodes[mId].mParent != 0 && mDocument.mNodes[mDocument.mNodes[mId].mParent].mKind == .Object;

	// Navigation

	/// @brief The array or object that holds the value; invalid for the root.
	public JsonNode Parent => IsValid ? Link(mDocument.mNodes[mId].mParent) : default;
	/// @brief The first element or member; invalid when there is none.
	public JsonNode FirstChild => IsValid ? Link(mDocument.mNodes[mId].mFirstChild) : default;
	/// @brief The last element or member; invalid when there is none.
	public JsonNode LastChild
	{
		get
		{
			if (!IsValid)
				return default;
			ref JsonNodeRecord node = ref mDocument.mNodes[mId];
			return node.IsContainer ? Link(node.LastChild) : default;
		}
	}
	/// @brief The next element or member of the parent; invalid after the last.
	public JsonNode Next => IsValid ? Link(mDocument.mNodes[mId].mNext) : default;
	/// @brief The previous element or member of the parent; invalid before the first.
	public JsonNode Previous => IsValid ? Link(mDocument.mNodes[mId].mPrev) : default;

	/// @brief The elements of an array or the values of an object's members, in order (empty for other
	/// values and for an invalid handle).
	public JsonNodeList Children => .(this);

	/// @brief The members of an object, name and value, in order (empty for other values).
	public JsonMemberList Members => .(this);

	// Lookups

	/// @brief Object: the value of the last member named `name`. Invalid when there is none, or when this
	/// is not an object.
	public JsonNode this[StringView name]
	{
		get
		{
			if (!IsValid || mDocument.mNodes[mId].mKind != .Object)
				return default;
			return Link(mDocument.FindMember(mId, name));
		}
	}

	/// @brief Array: the element at `index`. Object: the member at `index`. Invalid when out of range.
	public JsonNode this[int index]
	{
		get
		{
			if (!IsValid || index < 0)
				return default;
			ref JsonNodeRecord node = ref mDocument.mNodes[mId];
			if (!node.IsContainer || index >= node.Count)
				return default;
			// From the nearer end
			if (index < node.Count / 2)
			{
				uint32 child = node.mFirstChild;
				for (int i < index)
					child = mDocument.mNodes[child].mNext;
				return Link(child);
			}
			uint32 child = node.LastChild;
			for (int i = node.Count - 1; i > index; i--)
				child = mDocument.mNodes[child].mPrev;
			return Link(child);
		}
	}

	/// @brief Object: whether it has a member named `name`.
	public bool Contains(StringView name) => this[name].IsValid;

	/// @brief The value at a JSON Pointer (RFC 6901) relative to this one: `""` is this value, `/a/0` the
	/// first element of member `a`. A name used more than once resolves to the last member.
	/// @param pointer The pointer, unescaped as written in a URI fragment is not: `~0` for `~`, `~1` for `/`.
	/// @return The value, or why there is none.
	public Result<JsonNode, JsonPointerError> Find(StringView pointer)
	{
		return JsonPointer.Evaluate(this, pointer);
	}

	/// @brief The value at a JSON Pointer, or an invalid handle (see Find).
	public JsonNode At(StringView pointer)
	{
		if (Find(pointer) case .Ok(let node))
			return node;
		return default;
	}

	// Values

	/// @brief `true` or `false`, if the value is one.
	public bool TryGetBool(out bool value)
	{
		value = false;
		if (!IsValid)
			return false;
		let kind = mDocument.mNodes[mId].mKind;
		if (kind != .True && kind != .False)
			return false;
		value = kind == .True;
		return true;
	}

	/// @brief The boolean, or `fallback` if the value is not one.
	public bool GetBool(bool fallback = false) => TryGetBool(let value) ? value : fallback;

	/// @brief The string (decoded; it may hold U+0000), if the value is one.
	public bool TryGetString(out StringView value)
	{
		value = default;
		if (!IsValid || mDocument.mNodes[mId].mKind != .String)
			return false;
		value = mDocument.ValueTextOf(mId);
		return true;
	}

	/// @brief The string, or `fallback` if the value is not one.
	public StringView GetString(StringView fallback = "") => TryGetString(let value) ? value : fallback;

	/// @brief Number: what it holds. Integer for any other value.
	public JsonNumberKind NumberKind => IsNumber ? mDocument.mNodes[mId].mNumberKind : .Integer;

	/// @brief The int64, if the value is an integer number that fits (not `1.0`: a float is not an integer).
	public bool TryGetInt64(out int64 value)
	{
		value = 0;
		if (!IsValid)
			return false;
		ref JsonNodeRecord node = ref mDocument.mNodes[mId];
		if (node.mKind != .Number || node.mNumberKind != .Integer)
			return false;
		value = (int64)node.mPayload;
		return true;
	}

	/// @brief The int64, or `fallback`.
	public int64 GetInt64(int64 fallback = 0) => TryGetInt64(let value) ? value : fallback;

	/// @brief The uint64, if the value is a non-negative integer number that fits.
	public bool TryGetUInt64(out uint64 value)
	{
		value = 0;
		if (!IsValid)
			return false;
		ref JsonNodeRecord node = ref mDocument.mNodes[mId];
		if (node.mKind != .Number)
			return false;
		if (node.mNumberKind == .UInteger || (node.mNumberKind == .Integer && (int64)node.mPayload >= 0))
		{
			value = node.mPayload;
			return true;
		}
		return false;
	}

	/// @brief The uint64, or `fallback`.
	public uint64 GetUInt64(uint64 fallback = 0) => TryGetUInt64(let value) ? value : fallback;

	/// @brief The correctly rounded double of any number, if it is finite (`1e400` is not: never a silent
	/// infinity). `-0` gives −0.0. A NonFinite number (`NaN`, `Infinity`, read with
	/// AllowNonFiniteNumbers) gives the value it names.
	public bool TryGetDouble(out double value)
	{
		value = 0;
		if (!IsValid)
			return false;
		ref JsonNodeRecord node = ref mDocument.mNodes[mId];
		if (node.mKind != .Number)
			return false;
		if (node.mFlags.HasFlag(.Lexeme))
			return JsonNumber.ParseDouble(mDocument.ValueTextOf(mId), out value);
		switch (node.mNumberKind)
		{
		case .Integer:
			int64 integer = (int64)node.mPayload;
			if (integer > -((int64)1 << 53) && integer < ((int64)1 << 53))
				value = node.mFlags.HasFlag(.NegativeZero) ? -0.0 : (double)integer;
			else
			{
				// Rounded as the text would be
				let text = scope String();
				text.AppendF("{}", integer);
				JsonNumber.ParseDouble(text, out value);
			}
		case .UInteger:
			let text = scope String();
			text.AppendF("{}", node.mPayload);
			JsonNumber.ParseDouble(text, out value);
		default:
			value = JsonNumber.FromBits(node.mPayload);
		}
		return true;
	}

	/// @brief The double, or `fallback` (also when it is out of range).
	public double GetDouble(double fallback = 0) => TryGetDouble(let value) ? value : fallback;

	/// @brief Number: append its text: a big integer or out-of-range float as written, an integer in
	/// decimal, a double as its shortest round-trip digits in `format`. Nothing for other values.
	/// @param output The string to append to.
	/// @param format The layout of doubles.
	public void AppendNumber(String output, JsonFloatFormat format = .Plain)
	{
		if (!IsNumber)
			return;
		mDocument.AppendNumber(output, mId, format);
	}

	public bool Equals(JsonNode other) => mDocument == other.mDocument && mId == other.mId && mGeneration == other.mGeneration;
	public static bool operator ==(JsonNode lhs, JsonNode rhs) => lhs.Equals(rhs);
	public static bool operator !=(JsonNode lhs, JsonNode rhs) => !lhs.Equals(rhs);
}

/// @brief The children of an array or object (an object's member values), in order.
public struct JsonNodeList : IEnumerable<JsonNode>
{
	JsonNode mParent;

	internal this(JsonNode parent)
	{
		mParent = parent;
	}

	/// @brief The number of children.
	public int Count => mParent.IsValid ? mParent.Count : 0;

	public Enumerator GetEnumerator() => .(mParent);

	public struct Enumerator : IEnumerator<JsonNode>
	{
		JsonDocument mDocument;
		uint32 mNext;
		uint32 mGeneration;

		internal this(JsonNode parent)
		{
			mDocument = parent.mDocument;
			mNext = parent.IsValid && parent.mDocument.mNodes[parent.mId].IsContainer ? parent.mDocument.mNodes[parent.mId].mFirstChild : 0;
			mGeneration = mDocument != null ? mDocument.mGeneration : 0;
		}

		public Result<JsonNode> GetNext() mut
		{
			if (mNext == 0)
				return .Err;
			if (mDocument.mGeneration != mGeneration)
				Runtime.FatalError("JsonNodeList: the document was cleared or read again during the enumeration");
			let node = JsonNode(mDocument, mNext);
			mNext = mDocument.mNodes[mNext].mNext;
			return node;
		}
	}
}

/// @brief An object member: its name and its value.
public struct JsonMember
{
	/// @brief The member's name (decoded).
	public StringView Name;
	/// @brief The member's value.
	public JsonNode Value;
}

/// @brief The members of an object, in order (duplicates included).
public struct JsonMemberList : IEnumerable<JsonMember>
{
	JsonNode mObject;

	internal this(JsonNode node)
	{
		mObject = node;
	}

	/// @brief The number of members.
	public int Count => mObject.IsObject ? mObject.Count : 0;

	public Enumerator GetEnumerator() => .(mObject);

	public struct Enumerator : IEnumerator<JsonMember>
	{
		JsonNodeList.Enumerator mInner;

		internal this(JsonNode node)
		{
			mInner = .(node.IsObject ? node : default);
		}

		public Result<JsonMember> GetNext() mut
		{
			switch (mInner.GetNext())
			{
			case .Ok(let value):
				return JsonMember() { Name = value.mDocument.NameOf(value.mId), Value = value };
			case .Err:
				return .Err;
			}
		}
	}
}
