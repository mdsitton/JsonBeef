using System;
using System.Collections;
using System.IO;
using internal JsonBeef;

namespace JsonBeef;

extension JsonDocument
{
	/// @brief Write the document: a document read with JsonMetadataMode.PreserveStyle as it was read
	/// (byte for byte when unchanged; comments, layout and number and string spellings kept, changes
	/// regenerated in their surroundings' style), any other compact.
	/// @param output The string to append to.
	/// @return .Ok, or the first error (an empty document).
	public Result<void, JsonWriteError> Write(String output)
	{
		if (mPreserve)
			return WritePreserving(output);
		return Write(output, JsonWriteOptions());
	}

	/// @brief Write the document as JSON in a given layout: compact by default, indented with
	/// `options.Indented`, RFC 8785 canonical with `options.Canonical` (a PreserveStyle document too:
	/// its comments and spellings are not kept). Members are written in document order (duplicates
	/// included), big integers and numbers beyond a double's range as their text, other numbers exactly
	/// (integers) or as their shortest round-trip digits (doubles). The walk is iterative: depth costs no
	/// stack.
	/// @param output The string to append to.
	/// @param options Layout, escaping and number options.
	/// @return .Ok, or the first error (an empty document, a canonical-mode violation).
	public Result<void, JsonWriteError> Write(String output, JsonWriteOptions options)
	{
		let writer = scope JsonWriter(output, options);
		if (mRoot == 0)
			return .Err(JsonWriteError(.InvalidStructure, "The document is empty"));
		if (options.Canonical)
			WriteCanonical(writer, mRoot);
		else
			WriteTree(writer, mRoot);
		return writer.Finish();
	}

	/// @brief Write the value `node` (and everything under it) as a JSON text of its own.
	/// @param node A value of this document.
	/// @param output The string to append to.
	/// @param options Layout, escaping and number options.
	/// @return .Ok, or the first error.
	public Result<void, JsonWriteError> Write(JsonNode node, String output, JsonWriteOptions options = .())
	{
		if (!node.IsValid || node.mDocument != this)
			return .Err(JsonWriteError(.InvalidStructure, "The node is not a value of this document"));
		let writer = scope JsonWriter(output, options);
		if (options.Canonical)
			WriteCanonical(writer, node.mId);
		else
			WriteTree(writer, node.mId);
		return writer.Finish();
	}

	/// @brief Write the document to a file (UTF-8; a PreserveStyle document as Write(output) gives it,
	/// its BOM included if it had one).
	/// @param path The file's path.
	/// @return .Ok, or the first error (I/O errors as InvalidStructure with the message).
	public Result<void, JsonWriteError> WriteFile(StringView path)
	{
		let output = scope String();
		Try!(Write(output));
		if (File.WriteAllText(path, output) case .Err)
			return .Err(JsonWriteError(.InvalidStructure, scope $"Cannot write the file {path}"));
		return .Ok;
	}

	/// @brief Write the document to a file (UTF-8, no BOM) in a given layout.
	/// @param path The file's path.
	/// @param options Layout, escaping and number options.
	/// @return .Ok, or the first error (I/O errors as InvalidStructure with the message).
	public Result<void, JsonWriteError> WriteFile(StringView path, JsonWriteOptions options)
	{
		let output = scope String();
		Try!(Write(output, options));
		if (File.WriteAllText(path, output) case .Err)
			return .Err(JsonWriteError(.InvalidStructure, scope $"Cannot write the file {path}"));
		return .Ok;
	}

	/// The value `top` and its subtree, in document order, without recursion.
	void WriteTree(JsonWriter writer, uint32 top)
	{
		uint32 id = top;
		while (true)
		{
			ref JsonNodeRecord node = ref mNodes[id];
			if (id != top && mNodes[node.mParent].mKind == .Object)
				writer.WritePropertyName(NameOf(id));
			switch (node.mKind)
			{
			case .Object, .Array:
				if (node.mKind == .Object)
					writer.WriteStartObject();
				else
					writer.WriteStartArray();
				if (node.mFirstChild != 0)
				{
					id = node.mFirstChild;
					continue;
				}
				EndContainer(writer, node.mKind);
			default:
				WriteScalar(writer, id, false);
			}
			// Up to the next sibling, closing the containers left
			while (true)
			{
				if (id == top)
					return;
				ref JsonNodeRecord done = ref mNodes[id];
				if (done.mNext != 0)
				{
					id = done.mNext;
					break;
				}
				id = done.mParent;
				EndContainer(writer, mNodes[id].mKind);
			}
			if (writer.HasError)
				return;
		}
	}

	[Inline]
	static void EndContainer(JsonWriter writer, JsonValueKind kind)
	{
		if (kind == .Object)
			writer.WriteEndObject();
		else
			writer.WriteEndArray();
	}

	/// A scalar value.
	void WriteScalar(JsonWriter writer, uint32 id, bool canonical)
	{
		ref JsonNodeRecord node = ref mNodes[id];
		switch (node.mKind)
		{
		case .Null:
			writer.WriteNull();
		case .True:
			writer.WriteBool(true);
		case .False:
			writer.WriteBool(false);
		case .String:
			writer.WriteString(ValueTextOf(id));
		case .Number:
			if (node.mFlags.HasFlag(.Lexeme))
			{
				writer.WriteNumberText(ValueTextOf(id));
				return;
			}
			switch (node.mNumberKind)
			{
			case .Integer:
				if (node.mFlags.HasFlag(.NegativeZero) && !canonical)
					writer.WriteNumberText("-0");
				else
					writer.WriteNumber((int64)node.mPayload);
			case .UInteger:
				writer.WriteNumber(node.mPayload);
			default:
				writer.WriteNumber(JsonNumber.FromBits(node.mPayload));
			}
		default:
		}
	}

	/// RFC 8785: members sorted by their names' UTF-16 code units (recursively), duplicates an error.
	void WriteCanonical(JsonWriter writer, uint32 top)
	{
		// The sorted members of each open object, one after another, and per open container where its
		// children start in `order` and which is next
		let order = scope List<uint32>();
		let frames = scope List<(int start, int next, int end, bool isObject)>();
		uint32 id = top;
		while (true)
		{
			ref JsonNodeRecord node = ref mNodes[id];
			switch (node.mKind)
			{
			case .Object, .Array:
				bool isObject = node.mKind == .Object;
				int start = order.Count;
				uint32 child = node.mFirstChild;
				while (child != 0)
				{
					order.Add(child);
					child = mNodes[child].mNext;
				}
				if (isObject)
				{
					Span<uint32> members = .(order.Ptr + start, order.Count - start);
					members.Sort(scope (a, b) => CompareUtf16(NameOf(a), NameOf(b)));
					for (int i = start + 1; i < order.Count; i++)
					{
						if (NameOf(order[i - 1]) == NameOf(order[i]))
						{
							let message = scope String();
							message.Append("Canonical JSON (RFC 8785) cannot hold the duplicate member name `");
							message.Append(NameOf(order[i]));
							message.Append('`');
							writer.Fail(.DuplicateName, message);
							return;
						}
					}
					writer.WriteStartObject();
				}
				else
					writer.WriteStartArray();
				frames.Add((start, start, order.Count, isObject));
			default:
				WriteScalar(writer, id, true);
			}
			if (writer.HasError)
				return;
			// The next child of the innermost open container, closing the finished ones
			while (true)
			{
				if (frames.IsEmpty)
					return;
				int last = frames.Count - 1;
				if (frames[last].next < frames[last].end)
				{
					id = order[frames[last].next];
					frames[last].next++;
					if (frames[last].isObject)
						writer.WritePropertyName(NameOf(id));
					break;
				}
				EndContainer(writer, frames[last].isObject ? .Object : .Array);
				order.Count = frames[last].start;
				frames.PopBack();
			}
		}
	}

	/// Compares two UTF-8 names as sequences of UTF-16 code units (RFC 8785 §3.2.3): code point order,
	/// except that a supplementary character (a surrogate pair, D800-DBFF first) sorts below U+E000-U+FFFF.
	internal static int CompareUtf16(StringView a, StringView b)
	{
		int i = 0;
		int j = 0;
		while (i < a.Length && j < b.Length)
		{
			if (a[i] == b[j] && (uint8)a[i] < 0x80)
			{
				i++;
				j++;
				continue;
			}
			uint32 x = (uint32)JsonChar.Decode(a.Ptr, i, var lengthA);
			uint32 y = (uint32)JsonChar.Decode(b.Ptr, j, var lengthB);
			i += lengthA;
			j += lengthB;
			if (x == y)
				continue;
			uint32 unitX = x >= 0x10000 ? 0xD800 + ((x - 0x10000) >> 10) : x;
			uint32 unitY = y >= 0x10000 ? 0xD800 + ((y - 0x10000) >> 10) : y;
			if (unitX != unitY)
				return unitX < unitY ? -1 : 1;
			// The same high surrogate: the low ones decide
			return (x & 0x3FF) < (y & 0x3FF) ? -1 : 1;
		}
		if (i < a.Length)
			return 1;
		if (j < b.Length)
			return -1;
		return 0;
	}

	/// The text of number `id` (see JsonNode.AppendNumber).
	internal void AppendNumber(String output, uint32 id, JsonFloatFormat format)
	{
		ref JsonNodeRecord node = ref mNodes[id];
		if (node.mFlags.HasFlag(.Lexeme))
		{
			output.Append(ValueTextOf(id));
			return;
		}
		switch (node.mNumberKind)
		{
		case .Integer:
			if (node.mFlags.HasFlag(.NegativeZero))
				output.Append("-0");
			else
				((int64)node.mPayload).ToString(output);
		case .UInteger:
			node.mPayload.ToString(output);
		default:
			JsonNumber.AppendDouble(output, JsonNumber.FromBits(node.mPayload), format);
		}
	}
}
