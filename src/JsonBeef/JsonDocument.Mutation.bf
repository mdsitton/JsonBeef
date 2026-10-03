using System;
using FormatCore;
using internal FormatCore;
using internal JsonBeef;

namespace JsonBeef;

extension JsonDocument
{
	/// @brief Whether `text` can be a string or member name: well-formed UTF-8 (JsonNode.SetString and
	/// the other setters treat anything else as a programming error).
	public static bool IsValidText(StringView text)
	{
		let message = scope String();
		return Utf8.FindInvalid<JsonText>(text.Ptr, 0, text.Length, message, ?, ?) < 0;
	}

	/// @brief Replace the document's content with a single value, `null`, and return it (to set it:
	/// `doc.CreateRoot().SetObject()`). A document read with PreserveStyle keeps its source around the
	/// new root.
	/// @return The new root.
	public JsonNode CreateRoot()
	{
		if (mRoot != 0)
			RemoveSubtree(mRoot);
		uint32 id = NewNode(0, .Null);
		mRoot = id;
		MarkNew(id);
		return JsonNode(this, id);
	}

	/// A new record (no links but its parent), its range and style slots kept in step.
	internal uint32 NewNode(uint32 parent, JsonValueKind kind)
	{
		uint32 id = (uint32)mNodes.Count;
		ref JsonNodeRecord node = ref mNodes.AddDefault();
		node.mParent = parent;
		node.mKind = kind;
		if (!mRanges.IsEmpty)
		{
			JsonRangeRecord range = .();
			range.mLength = -1;
			range.mNameLength = -1;
			mRanges.Add(range);
		}
		return id;
	}

	/// Checks that a handle is a valid node of this document.
	internal void Check(JsonNode node, StringView operation)
	{
		if (!node.IsValid || node.mDocument != this)
			Runtime.FatalError(scope $"JsonNode.{operation}: the handle is invalid (no value, or a cleared document)");
	}

	/// Checks text set through the API.
	internal static void CheckText(StringView text, StringView operation)
	{
		if (!IsValidText(text))
			Runtime.FatalError(scope $"JsonNode.{operation}: the text is not well-formed UTF-8 (JsonDocument.IsValidText checks first)");
	}

	/// Removes the children of container `id` (marked removed, unlinked).
	internal void ClearChildren(uint32 id)
	{
		uint32 child = mNodes[id].mFirstChild;
		while (child != 0)
		{
			uint32 next = mNodes[child].mNext;
			MarkRemovedSubtree(child);
			child = next;
		}
		ref JsonNodeRecord node = ref mNodes[id];
		node.mFirstChild = 0;
		if (node.IsContainer)
			node.mPayload = 0;
		DropIndex(id);
	}

	/// Unlinks `id` from its parent and marks its subtree removed.
	internal void RemoveSubtree(uint32 id)
	{
		uint32 parent = mNodes[id].mParent;
		if (parent != 0)
		{
			Unlink(id);
			DropIndex(parent);
			MarkChildrenChanged(parent);
		}
		else if (mRoot == id)
			mRoot = 0;
		MarkRemovedSubtree(id);
	}

	/// Marks `id` and every node under it removed (their handles become invalid), without recursion.
	void MarkRemovedSubtree(uint32 top)
	{
		JsonTree.MarkRemovedSubtree(mNodes.Ptr, top);
	}

	/// Links new node `id` into `parent` before `before` (0: at the end).
	internal void LinkBefore(uint32 parent, uint32 id, uint32 before)
	{
		if (before == 0)
			JsonTree.LinkLastFresh(mNodes.Ptr, parent, id);
		else
			JsonTree.LinkBefore(mNodes.Ptr, before, id);
		DropIndex(parent);
		MarkChildrenChanged(parent);
		MarkNew(id);
	}
}

extension JsonNode
{
	// Scalars

	/// @brief Make the value `null` (a container loses its children).
	/// @return This node, for chaining.
	public JsonNode SetNull()
	{
		return SetScalar(.Null, "SetNull");
	}

	/// @brief Make the value `true` or `false`.
	/// @param value The boolean.
	/// @return This node, for chaining.
	public JsonNode SetBool(bool value)
	{
		return SetScalar(value ? .True : .False, "SetBool");
	}

	/// @brief Make the value a string (copied; it may hold U+0000). Text that is not well-formed UTF-8
	/// is a fatal error (JsonDocument.IsValidText checks first).
	/// @param value The text.
	/// @return This node, for chaining.
	public JsonNode SetString(StringView value)
	{
		JsonDocument.CheckText(value, "SetString");
		SetScalar(.String, "SetString");
		ref JsonNodeRecord node = ref mDocument.mNodes[mId];
		node.mPayload = mDocument.AddText(value);
		node.mFlags |= .ValueInTable;
		return this;
	}

	/// @brief Make the value an integer, written exactly.
	/// @param value The integer.
	/// @return This node, for chaining.
	public JsonNode SetNumber(int64 value)
	{
		SetScalar(.Number, "SetNumber");
		ref JsonNodeRecord node = ref mDocument.mNodes[mId];
		node.mNumberKind = .Integer;
		node.mPayload = (uint64)value;
		return this;
	}

	/// @brief Make the value an unsigned integer, written exactly.
	/// @param value The integer.
	/// @return This node, for chaining.
	public JsonNode SetNumber(uint64 value)
	{
		SetScalar(.Number, "SetNumber");
		ref JsonNodeRecord node = ref mDocument.mNodes[mId];
		node.mNumberKind = value <= (uint64)int64.MaxValue ? .Integer : .UInteger;
		node.mPayload = value;
		return this;
	}

	/// @brief Make the value a double, written as its shortest round-trip digits. NaN and infinity are
	/// not JSON numbers: a fatal error.
	/// @param value The double.
	/// @return This node, for chaining.
	public JsonNode SetNumber(double value)
	{
		if (!value.IsFinite)
			Runtime.FatalError("JsonNode.SetNumber: NaN and infinity are not JSON numbers");
		SetScalar(.Number, "SetNumber");
		ref JsonNodeRecord node = ref mDocument.mNodes[mId];
		node.mNumberKind = .Float;
		node.mPayload = JsonNumber.ToBits(value);
		return this;
	}

	/// @brief Make the value a number given as its text, kept exactly (a big integer, `1.50`, `1e400`).
	/// @param text The number; it must follow the JSON number grammar.
	/// @return Whether it does (nothing changes when not).
	public bool SetNumberText(StringView text)
	{
		mDocument.Check(this, "SetNumberText");
		if (!JsonWriter.IsNumberText(text))
			return false;
		SetScalar(.Number, "SetNumberText");
		ref JsonNodeRecord node = ref mDocument.mNodes[mId];
		node.mNumberKind = JsonNumber.Classify(text);
		switch (node.mNumberKind)
		{
		case .Integer:
			JsonNumber.TryParseInt64(text, let integer);
			node.mPayload = (uint64)integer;
			if (integer == 0 && text[0] == '-')
				node.mFlags |= .NegativeZero;
		case .UInteger:
			JsonNumber.TryParseUInt64(text, let unsigned);
			node.mPayload = unsigned;
		case .Float:
			if (JsonNumber.ParseDouble(text, let value))
			{
				node.mPayload = JsonNumber.ToBits(value);
				break;
			}
			node.mPayload = mDocument.AddText(text);
			node.mFlags |= .Lexeme | .ValueInTable;
		case .BigInteger:
			node.mPayload = mDocument.AddText(text);
			node.mFlags |= .Lexeme | .ValueInTable;
		case .NonFinite:
			// (Not JSON number text: IsNumberText rejected it above)
		}
		return true;
	}

	/// Turns the node into a scalar of `kind`, its old value (and children) gone.
	JsonNode SetScalar(JsonValueKind kind, StringView operation)
	{
		mDocument.Check(this, operation);
		ref JsonNodeRecord node = ref mDocument.mNodes[mId];
		if (node.IsContainer)
			mDocument.ClearChildren(mId);
		node.mKind = kind;
		node.mPayload = 0;
		node.mNumberKind = .Integer;
		node.mFlags &= ~(.ValueInTable | .Lexeme | .NegativeZero);
		mDocument.MarkValueChanged(mId);
		return this;
	}

	// Containers

	/// @brief Make the value an empty array (a container loses its children).
	/// @return This node, for chaining.
	public JsonNode SetArray()
	{
		SetScalar(.Array, "SetArray");
		return this;
	}

	/// @brief Make the value an empty object.
	/// @return This node, for chaining.
	public JsonNode SetObject()
	{
		SetScalar(.Object, "SetObject");
		return this;
	}

	/// @brief Array: append an element, `null` until set. Fatal on another kind of value.
	/// @return The new element.
	public JsonNode Add()
	{
		mDocument.Check(this, "Add");
		if (Kind != .Array)
			Runtime.FatalError("JsonNode.Add(): not an array (an object's member needs a name)");
		uint32 id = mDocument.NewNode(mId, .Null);
		mDocument.LinkBefore(mId, id, 0);
		return JsonNode(mDocument, id);
	}

	/// @brief Object: append a member named `name`, `null` until set (an existing member of that name
	/// stays; the new one, last, is what lookups find). Fatal on another kind of value.
	/// @param name The member's name (well-formed UTF-8).
	/// @return The new member's value.
	public JsonNode Add(StringView name)
	{
		mDocument.Check(this, "Add");
		if (Kind != .Object)
			Runtime.FatalError("JsonNode.Add(name): not an object");
		JsonDocument.CheckText(name, "Add");
		uint32 id = mDocument.NewNode(mId, .Null);
		SetName(id, name);
		mDocument.LinkBefore(mId, id, 0);
		return JsonNode(mDocument, id);
	}

	/// @brief Object: the value of the last member named `name`, or a new member of that name (`null`).
	/// @param name The member's name.
	/// @return The member's value.
	public JsonNode Set(StringView name)
	{
		let existing = this[name];
		if (existing.IsValid)
			return existing;
		return Add(name);
	}

	/// @brief Insert a new `null` element before this one, in its array.
	/// @return The new element.
	public JsonNode InsertBefore()
	{
		return Insert(false, default, "InsertBefore");
	}

	/// @brief Insert a new `null` element after this one, in its array.
	/// @return The new element.
	public JsonNode InsertAfter()
	{
		return Insert(true, default, "InsertAfter");
	}

	/// @brief Insert a new member before this one, in its object.
	/// @param name The new member's name.
	/// @return The new member's value (`null`).
	public JsonNode InsertBefore(StringView name)
	{
		return Insert(false, name, "InsertBefore");
	}

	/// @brief Insert a new member after this one, in its object.
	/// @param name The new member's name.
	/// @return The new member's value (`null`).
	public JsonNode InsertAfter(StringView name)
	{
		return Insert(true, name, "InsertAfter");
	}

	JsonNode Insert(bool after, StringView name, StringView operation)
	{
		mDocument.Check(this, operation);
		uint32 parent = mDocument.mNodes[mId].mParent;
		if (parent == 0)
			Runtime.FatalError(scope $"JsonNode.{operation}: the root has no container");
		bool inObject = mDocument.mNodes[parent].mKind == .Object;
		if (inObject != (name.Ptr != null))
			Runtime.FatalError(scope $"JsonNode.{operation}: {(inObject ? "an object member needs a name" : "an array element has no name")}");
		if (inObject)
			JsonDocument.CheckText(name, operation);
		uint32 id = mDocument.NewNode(parent, .Null);
		if (inObject)
			SetName(id, name);
		mDocument.LinkBefore(parent, id, after ? mDocument.mNodes[mId].mNext : mId);
		return JsonNode(mDocument, id);
	}

	void SetName(uint32 id, StringView name)
	{
		ref JsonNodeRecord node = ref mDocument.mNodes[id];
		node.mName = mDocument.AddText(name);
		node.mFlags |= .NameInTable;
	}

	/// @brief Remove this value from its array or object (the root: the document becomes empty). The
	/// handle, and those of the values under it, become invalid.
	public void Remove()
	{
		mDocument.Check(this, "Remove");
		mDocument.RemoveSubtree(mId);
	}

	/// @brief Object: remove every member named `name`.
	/// @param name The name.
	/// @return How many were removed.
	public int RemoveMember(StringView name)
	{
		int removed = 0;
		while (true)
		{
			let member = this[name];
			if (!member.IsValid)
				return removed;
			member.Remove();
			removed++;
		}
	}

	/// @brief Rename this member (fatal for an array element or the root).
	/// @param name The new name (well-formed UTF-8).
	public void Rename(StringView name)
	{
		mDocument.Check(this, "Rename");
		if (!IsMember)
			Runtime.FatalError("JsonNode.Rename: not an object member");
		JsonDocument.CheckText(name, "Rename");
		SetName(mId, name);
		mDocument.DropIndex(mDocument.mNodes[mId].mParent);
		mDocument.MarkNameChanged(mId);
	}
}
