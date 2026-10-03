using System;
using System.Collections;
using FormatCore;
using internal FormatCore;
using internal JsonBeef;

namespace JsonBeef;

/// @brief Why a JSON Patch (RFC 6902) failed.
public enum JsonPatchErrorKind : uint8
{
	/// @brief The patch is not an array of operation objects, or an operation is not one: `op` missing or
	/// unknown, `path`, `from` or `value` missing where the operation needs it, `path` or `from` not a
	/// string, or a member given twice.
	InvalidOperation,
	/// @brief `path` or `from` is not a JSON Pointer (it does not start with `/`, or has a bad `~`).
	InvalidPointer,
	/// @brief No value at `path` or `from` (for add: no container there), or an array index past the end.
	NotFound,
	/// @brief A token on an array is not an index (`01`, `1e0`; `-` where an element must exist).
	InvalidIndex,
	/// @brief A token goes into a value that is not an array or object.
	NotAContainer,
	/// @brief move: `from` is a proper prefix of `path` (a value cannot move into itself).
	MoveIntoItself,
	/// @brief remove: the whole document (a patched document always has a value).
	RemoveRoot,
	/// @brief test: the value at `path` is not equal to `value`.
	TestFailed
}

/// @brief A JSON Patch error: what failed, in which operation, and where in its pointer.
public struct JsonPatchError
{
	public JsonPatchErrorKind mKind;
	/// @brief The failing operation's index in the patch; -1 when the patch is not an array.
	public int mOperation;
	/// @brief The operation's member at fault: "op", "path", "from", "value", or empty.
	public StringView mMember;
	/// @brief For the pointer errors: byte offset of the failing token's `/` in the pointer.
	public int mOffset;

	public this(JsonPatchErrorKind kind, int operation, StringView member, int offset = 0)
	{
		mKind = kind;
		mOperation = operation;
		mMember = member;
		mOffset = offset;
	}

	public override void ToString(String output)
	{
		if (mOperation >= 0)
			output.AppendF("operation {}: ", mOperation);
		if (!mMember.IsEmpty)
			output.AppendF("`{}`: ", mMember);
		switch (mKind)
		{
		case .InvalidOperation: output.Append(mOperation < 0 ? "a patch is an array of operations" : (mMember.IsEmpty ? "not an operation object" : "missing, of the wrong type, given twice or unknown"));
		case .InvalidPointer: output.AppendF("invalid JSON Pointer syntax at offset {}", mOffset);
		case .NotFound: output.AppendF("no such value at offset {}", mOffset);
		case .InvalidIndex: output.AppendF("invalid array index at offset {}", mOffset);
		case .NotAContainer: output.AppendF("not an array or object at offset {}", mOffset);
		case .MoveIntoItself: output.Append("a value cannot move into itself");
		case .RemoveRoot: output.Append("the whole document cannot be removed");
		case .TestFailed: output.Append("the value is not equal");
		}
	}
}

/// @brief JSON Patch (RFC 6902) and JSON Merge Patch (RFC 7396) on documents.
///
/// ```
/// let patch = scope JsonDocument();
/// Try!(patch.Read("""[{"op": "replace", "path": "/port", "value": 8443}]"""));
/// if (JsonPatch.Apply(config, patch.Root) case .Err(let error))
///     Console.WriteLine(error);
/// ```
public static class JsonPatch
{
	/// @brief Apply a JSON Patch: its operations in order, all or nothing (on an error the document is as
	/// it was, handles included). `test` compares by value: numbers numerically (`1` equals `1.0`),
	/// objects regardless of member order. A name used more than once in the target resolves to the
	/// last member, as in lookups. Values are copied from the patch, which must belong to another
	/// document. Applying keeps a copy of the node table for the rollback: the cost is linear in the
	/// document's size.
	/// @param target The document to change (an empty document has no value: only `add` at `""` applies).
	/// @param patch The patch: an array of operation objects.
	/// @return .Ok, or the first failing operation's error.
	public static Result<void, JsonPatchError> Apply(JsonDocument target, JsonNode patch)
	{
		if (patch.IsValid && patch.mDocument == target)
			Runtime.FatalError("JsonPatch.Apply: the patch belongs to the target document");
		if (!patch.IsArray)
			return .Err(.(.InvalidOperation, -1, ""));
		let checkpoint = scope JsonDocument.Checkpoint(target);
		int index = 0;
		for (let operation in patch.Children)
		{
			if (ApplyOne(target, operation, index) case .Err(let error))
			{
				checkpoint.Restore();
				return .Err(error);
			}
			index++;
		}
		return .Ok;
	}

	/// @brief Apply a JSON Merge Patch to the document's value (an empty document's value is `null`): an
	/// object patch merges into an object (a member set to `null` is removed, objects merge recursively,
	/// anything else replaces the member); any other patch replaces the value. A merge cannot fail.
	/// @param target The document to change.
	/// @param patch The patch (from another document).
	public static void Merge(JsonDocument target, JsonNode patch)
	{
		if (target.IsEmpty)
			target.CreateRoot();
		Merge(target.Root, patch);
	}

	/// @brief Apply a JSON Merge Patch to a value (see the document overload).
	/// @param target The value to change; its name and place stay.
	/// @param patch The patch (from another document).
	public static void Merge(JsonNode target, JsonNode patch)
	{
		let doc = target.mDocument;
		doc.Check(target, "Merge");
		if (!patch.IsValid)
			Runtime.FatalError("JsonPatch.Merge: the patch handle is invalid");
		if (patch.mDocument == doc)
			Runtime.FatalError("JsonPatch.Merge: the patch belongs to the target document");
		if (!patch.IsObject)
		{
			target.SetValue(patch);
			return;
		}
		if (!target.IsObject)
			target.SetObject();
		let source = patch.mDocument;
		// Depth first, in the patch's order (a later member of the same name sees the earlier one's
		// result), without recursion: (target object, next patch member) per level
		let stack = scope List<(uint32 target, uint32 next)>();
		stack.Add((target.mId, source.mNodes[patch.mId].mFirstChild));
		while (!stack.IsEmpty)
		{
			let (objectId, member) = stack.Back;
			if (member == 0)
			{
				stack.PopBack();
				continue;
			}
			stack.Back.next = source.mNodes[member].mNext;
			let into = JsonNode(doc, objectId);
			let name = source.NameOf(member);
			switch (source.mNodes[member].mKind)
			{
			case .Null:
				into.RemoveMember(name);
			case .Object:
				var existing = into[name];
				if (!existing.IsValid)
					existing = into.Add(name);
				if (!existing.IsObject)
					existing.SetObject();
				stack.Add((existing.mId, source.mNodes[member].mFirstChild));
			default:
				into.Set(name).SetValue(JsonNode(source, member));
			}
		}
	}

	/// One operation.
	static Result<void, JsonPatchError> ApplyOne(JsonDocument doc, JsonNode operation, int index)
	{
		if (!operation.IsObject)
			return .Err(.(.InvalidOperation, index, ""));
		JsonNode op = default, path = default, from = default, value = default;
		for (let member in operation.Members)
		{
			JsonNode* slot;
			switch (member.Name)
			{
			case "op": slot = &op;
			case "path": slot = &path;
			case "from": slot = &from;
			case "value": slot = &value;
			default: continue;
			}
			if (slot.IsValid)
				return .Err(.(.InvalidOperation, index, member.Name));
			*slot = member.Value;
		}
		if (!op.IsString)
			return .Err(.(.InvalidOperation, index, "op"));
		if (!path.IsString)
			return .Err(.(.InvalidOperation, index, "path"));
		let opName = op.GetString();
		let pathText = path.GetString();
		bool needsValue = opName == "add" || opName == "replace" || opName == "test";
		bool needsFrom = opName == "move" || opName == "copy";
		if (!needsValue && !needsFrom && opName != "remove")
			return .Err(.(.InvalidOperation, index, "op"));
		if (needsValue && !value.IsValid)
			return .Err(.(.InvalidOperation, index, "value"));
		if (needsFrom && !from.IsString)
			return .Err(.(.InvalidOperation, index, "from"));
		if (!JsonPointer.IsValid(pathText))
			return .Err(.(.InvalidPointer, index, "path", InvalidAt(pathText)));

		switch (opName)
		{
		case "add":
			return Add(doc, pathText, doc.CopyDetached(value.mDocument, value.mId), index);
		case "remove":
			if (pathText.IsEmpty)
				return .Err(.(.RemoveRoot, index, "path"));
			let node = Try!(Find(doc, pathText, index, "path"));
			node.Remove();
		case "replace":
			let node = Try!(Find(doc, pathText, index, "path"));
			node.SetValue(value);
		case "test":
			let node = Try!(Find(doc, pathText, index, "path"));
			if (!node.ValueEquals(value))
				return .Err(.(.TestFailed, index, "path"));
		case "move", "copy":
			let fromText = from.GetString();
			if (!JsonPointer.IsValid(fromText))
				return .Err(.(.InvalidPointer, index, "from", InvalidAt(fromText)));
			let source = Try!(Find(doc, fromText, index, "from"));
			if (opName == "move")
			{
				if (fromText == pathText)
					return .Ok;
				if (pathText.StartsWith(fromText) && pathText[fromText.Length] == '/')
					return .Err(.(.MoveIntoItself, index, "path"));
			}
			uint32 copy = doc.CopyDetached(doc, source.mId);
			if (opName == "move")
				source.Remove();
			return Add(doc, pathText, copy, index);
		}
		return .Ok;
	}

	/// The offset of a bad pointer's error (its start, or the token with the bad `~`).
	static int InvalidAt(StringView pointer)
	{
		if (pointer.IsEmpty || pointer[0] != '/')
			return 0;
		int token = 0;
		for (int i < pointer.Length)
		{
			if (pointer[i] == '/')
				token = i;
			else if (pointer[i] == '~' && (i + 1 >= pointer.Length || (pointer[i + 1] != '0' && pointer[i + 1] != '1')))
				return token;
		}
		return 0;
	}

	/// The value at `pointer`, which must exist.
	static Result<JsonNode, JsonPatchError> Find(JsonDocument doc, StringView pointer, int index, StringView member)
	{
		switch (JsonPointer.Evaluate(doc.Root, pointer))
		{
		case .Ok(let node):
			return node;
		case .Err(let error):
			return .Err(Convert(error, index, member));
		}
	}

	static JsonPatchError Convert(JsonPointerError error, int index, StringView member)
	{
		JsonPatchErrorKind kind;
		switch (error.mKind)
		{
		case .InvalidSyntax: kind = .InvalidPointer;
		case .InvalidIndex: kind = .InvalidIndex;
		case .NotFound: kind = .NotFound;
		case .NotAContainer: kind = .NotAContainer;
		}
		return .(kind, index, member, error.mOffset);
	}

	/// add: puts detached value `copy` at `pointer` (the whole document, a member set or added, an element
	/// inserted or appended with `-`). A failure leaves the copy unlinked (the rollback drops it).
	static Result<void, JsonPatchError> Add(JsonDocument doc, StringView pointer, uint32 copy, int index)
	{
		if (pointer.IsEmpty)
		{
			if (doc.IsEmpty)
				doc.CreateRoot();
			doc.Adopt(doc.mRoot, copy);
			return .Ok;
		}
		int tokenOffset = pointer.LastIndexOf('/');
		let parent = Try!(Find(doc, pointer.Substring(0, tokenOffset), index, "path"));
		int pos = tokenOffset + 1;
		let token = JsonPointer.NextToken(pointer, ref pos, scope .()).Value;
		switch (parent.Kind)
		{
		case .Object:
			let existing = parent[token];
			if (existing.IsValid)
			{
				doc.Adopt(existing.mId, copy);
				return .Ok;
			}
			ref JsonNodeRecord node = ref doc.mNodes[copy];
			node.mName = doc.AddText(token);
			node.mFlags |= .NameInTable;
			doc.LinkBefore(parent.mId, copy, 0);
		case .Array:
			uint32 before = 0;
			if (token != "-")
			{
				int at = JsonPointer.ParseIndex(token);
				if (at < 0)
					return .Err(.(.InvalidIndex, index, "path", tokenOffset));
				if (at > parent.Count)
					return .Err(.(.NotFound, index, "path", tokenOffset));
				before = at < parent.Count ? parent[at].mId : 0;
			}
			doc.LinkBefore(parent.mId, copy, before);
		default:
			return .Err(.(.NotAContainer, index, "path", tokenOffset));
		}
		return .Ok;
	}
}

extension JsonDocument
{
	/// The state a failed patch goes back to. The node table only grows and the string table only gains
	/// entries, so the records and styles are copied and the rest is counted.
	internal class Checkpoint
	{
		JsonDocument mDocument;
		List<JsonNodeRecord> mNodes = new .() ~ delete _;
		List<JsonNodeStyle> mStyles = new .() ~ delete _;
		int mStrings;
		int mRanges;
		uint32 mRoot;

		public this(JsonDocument document)
		{
			mDocument = document;
			mNodes.AddRange(document.mNodes.Span);
			mStyles.AddRange(document.mStyles);
			mStrings = document.mStrings.Count;
			mRanges = document.mRanges.Count;
			mRoot = document.mRoot;
		}

		public void Restore()
		{
			let doc = mDocument;
			doc.mNodes.Count = mNodes.Count;
			Internal.MemCpy(doc.mNodes.Ptr, mNodes.Ptr, mNodes.Count * strideof(JsonNodeRecord), alignof(JsonNodeRecord));
			doc.mStyles.Clear();
			doc.mStyles.AddRange(mStyles);
			doc.mStrings.Count = mStrings;
			doc.mRanges.Count = mRanges;
			doc.mRoot = mRoot;
			for (let index in doc.mIndexes.Values)
				delete index;
			doc.mIndexes.Clear();
		}
	}

	/// A copy of node `top` of `source` (this document or another) and everything under it, linked to
	/// nothing (its parent 0, not the root), without recursion. Its top has no name.
	internal uint32 CopyDetached(JsonDocument source, uint32 top)
	{
		uint32 copyTop = NewNode(0, .Null);
		CopyValue(source, top, copyTop);
		uint32 from = top;
		uint32 to = copyTop;
		while (true)
		{
			if (source.mNodes[from].IsContainer && source.mNodes[from].mFirstChild != 0)
			{
				from = source.mNodes[from].mFirstChild;
				to = CopyChild(source, from, to);
				continue;
			}
			while (from != top && source.mNodes[from].mNext == 0)
			{
				from = source.mNodes[from].mParent;
				to = mNodes[to].mParent;
			}
			if (from == top)
				return copyTop;
			from = source.mNodes[from].mNext;
			to = CopyChild(source, from, mNodes[to].mParent);
		}
	}

	/// A copy of `from`'s value (not its children) appended to `parent`, named as `from` in an object.
	uint32 CopyChild(JsonDocument source, uint32 from, uint32 parent)
	{
		uint32 id = NewNode(parent, .Null);
		CopyValue(source, from, id);
		if (mNodes[parent].mKind == .Object)
		{
			if (source == this)
			{
				mNodes[id].mName = mNodes[from].mName;
				mNodes[id].mFlags |= mNodes[from].mFlags & .NameInTable;
			}
			else
			{
				mNodes[id].mName = AddText(source.NameOf(from));
				mNodes[id].mFlags |= .NameInTable;
			}
		}
		LinkBefore(parent, id, 0);
		return id;
	}

	/// Copies the kind and value of `from` (in `source`) into new node `to`; a container's children come
	/// after.
	void CopyValue(JsonDocument source, uint32 from, uint32 to)
	{
		JsonNodeRecord original = source.mNodes[from];
		uint64 payload = 0;
		JsonNodeFlags flags = original.mFlags & (.NegativeZero | .Lexeme);
		if (!original.IsContainer)
		{
			payload = original.mPayload;
			if (original.mKind == .String || original.mFlags.HasFlag(.Lexeme))
			{
				if (source == this)
					flags |= original.mFlags & .ValueInTable;
				else
				{
					payload = AddText(source.ValueTextOf(from));
					flags |= .ValueInTable;
				}
			}
		}
		ref JsonNodeRecord node = ref mNodes[to];
		node.mKind = original.mKind;
		node.mNumberKind = original.mNumberKind;
		node.mPayload = payload;
		node.mFlags |= flags;
	}

	/// Node `target` takes the value of detached node `copy` (its children move over) and keeps its name
	/// and place; `copy` is then removed.
	internal void Adopt(uint32 target, uint32 copy)
	{
		if (mNodes[target].IsContainer)
			ClearChildren(target);
		JsonNodeRecord value = mNodes[copy];
		ref JsonNodeRecord node = ref mNodes[target];
		node.mKind = value.mKind;
		node.mNumberKind = value.mNumberKind;
		node.mPayload = value.mPayload;
		node.mFirstChild = value.mFirstChild;
		node.mFlags = (node.mFlags & ~(.ValueInTable | .Lexeme | .NegativeZero)) | (value.mFlags & (.ValueInTable | .Lexeme | .NegativeZero));
		uint32 child = value.mFirstChild;
		while (child != 0)
		{
			mNodes[child].mParent = target;
			child = mNodes[child].mNext;
		}
		ref JsonNodeRecord gone = ref mNodes[copy];
		gone.mFirstChild = 0;
		gone.mPayload = 0;
		gone.mFlags |= .Removed;
		DropIndex(copy);
		DropIndex(target);
		MarkValueChanged(target);
		if (node.IsContainer)
			MarkChildrenChanged(target);
	}
}

extension JsonNode
{
	/// @brief Make this value a copy of `source` and everything under it (from any document; `source` may
	/// be under this value). This value keeps its name and place.
	/// @param source The value to copy.
	/// @return This node, for chaining.
	public JsonNode SetValue(JsonNode source)
	{
		mDocument.Check(this, "SetValue");
		if (!source.IsValid)
			Runtime.FatalError("JsonNode.SetValue: the source handle is invalid");
		if (source == this)
			return this;
		mDocument.Adopt(mId, mDocument.CopyDetached(source.mDocument, source.mId));
		return this;
	}

	/// @brief Whether this value equals `other` as JSON values (RFC 6902 §4.6, the same documents or
	/// not): the same kind; strings with the same code points; numbers with the same value (`1`, `1.0`
	/// and `10e-1` are equal, as are `0` and `-0`; a double as the document holds it); arrays with equal
	/// elements in order; objects with the same names and equal values in any order (a name used more
	/// than once counts once, with its last value). False if either handle is invalid.
	public bool ValueEquals(JsonNode other)
	{
		if (!IsValid || !other.IsValid)
			return false;
		let pending = scope List<(JsonNode, JsonNode)>();
		pending.Add((this, other));
		let left = scope String();
		let right = scope String();
		while (!pending.IsEmpty)
		{
			let (a, b) = pending.PopBack();
			let kind = a.Kind;
			if (kind != b.Kind)
				return false;
			switch (kind)
			{
			case .String:
				if (a.GetString() != b.GetString())
					return false;
			case .Number:
				if (!NumbersEqual(a, b, left, right))
					return false;
			case .Array:
				if (a.Count != b.Count)
					return false;
				var element = b.FirstChild;
				for (let item in a.Children)
				{
					pending.Add((item, element));
					element = element.Next;
				}
			case .Object:
				int names = 0;
				for (let member in a.Members)
				{
					if (a[member.Name] != member.Value)
						continue;
					let match = b[member.Name];
					if (!match.IsValid)
						return false;
					pending.Add((member.Value, match));
					names++;
				}
				for (let member in b.Members)
				{
					if (b[member.Name] == member.Value)
						names--;
				}
				if (names != 0)
					return false;
			default:
			}
		}
		return true;
	}

	/// Numeric equality: integers and doubles directly, anything else (mixed kinds, big integers, texts
	/// beyond a double) by the exact decimal value of the number's text.
	static bool NumbersEqual(JsonNode a, JsonNode b, String left, String right)
	{
		ref JsonNodeRecord x = ref a.mDocument.mNodes[a.mId];
		ref JsonNodeRecord y = ref b.mDocument.mNodes[b.mId];
		bool lexemes = x.mFlags.HasFlag(.Lexeme) || y.mFlags.HasFlag(.Lexeme);
		if (x.mNumberKind == .NonFinite || y.mNumberKind == .NonFinite)
		{
			if (x.mNumberKind != y.mNumberKind)
				return false;
			double p = JsonNumber.FromBits(x.mPayload);
			double q = JsonNumber.FromBits(y.mPayload);
			return p == q || (p.IsNaN && q.IsNaN);
		}
		if (!lexemes && x.mNumberKind == y.mNumberKind)
		{
			if (x.mNumberKind == .Float)
				return JsonNumber.FromBits(x.mPayload) == JsonNumber.FromBits(y.mPayload);
			return x.mPayload == y.mPayload;
		}
		left.Clear();
		right.Clear();
		AppendExact(a, ref x, left);
		AppendExact(b, ref y, right);
		return DecimalEquals(left, right);
	}

	/// A number's exact value as text: its own text for integers and lexemes; a double's exact binary
	/// value in decimal (`2^64` is `18446744073709551616`, where its shortest digits are
	/// `18446744073709552000`).
	static void AppendExact(JsonNode number, ref JsonNodeRecord record, String output)
	{
		if (record.mFlags.HasFlag(.Lexeme) || record.mNumberKind != .Float)
		{
			number.AppendNumber(output);
			return;
		}
		BigDecimal.AppendExact(output, JsonNumber.FromBits(record.mPayload));
	}

	/// Whether two JSON number texts have the same value: both as sign, significant digits and the
	/// exponent of the first digit.
	static bool DecimalEquals(StringView a, StringView b)
	{
		let digitsA = scope String();
		let digitsB = scope String();
		Decompose(a, digitsA, var negativeA, var exponentA);
		Decompose(b, digitsB, var negativeB, var exponentB);
		return digitsA == digitsB && (digitsA.IsEmpty || (negativeA == negativeB && exponentA == exponentB));
	}

	/// A number text as its significant digits (no leading or trailing zeros; empty for zero), its sign
	/// and the power of ten of the place before the first digit. Exponents saturate far beyond any
	/// number's length.
	static void Decompose(StringView text, String digits, out bool negative, out int64 exponent)
	{
		int i = 0;
		negative = i < text.Length && text[i] == '-';
		if (negative)
			i++;
		int64 point = 0;
		bool afterPoint = false;
		for (; i < text.Length; i++)
		{
			char8 c = text[i];
			if (c == '.')
			{
				afterPoint = true;
				continue;
			}
			if (!JsonChar.IsDigit(c))
				break;
			if (digits.IsEmpty && c == '0')
			{
				if (afterPoint)
					point--;
				continue;
			}
			digits.Append(c);
			if (!afterPoint)
				point++;
		}
		int64 power = 0;
		if (i < text.Length && (text[i] == 'e' || text[i] == 'E'))
		{
			i++;
			bool negativePower = i < text.Length && text[i] == '-';
			if (i < text.Length && (text[i] == '-' || text[i] == '+'))
				i++;
			for (; i < text.Length; i++)
			{
				if (power < (int64)1 << 50)
					power = power * 10 + (text[i] - '0');
			}
			if (negativePower)
				power = -power;
		}
		while (!digits.IsEmpty && digits[digits.Length - 1] == '0')
			digits.RemoveFromEnd(1);
		exponent = point + power;
	}
}
