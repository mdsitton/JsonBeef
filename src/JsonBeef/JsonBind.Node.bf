using System;
using System.Collections;
using internal JsonBeef;

namespace JsonBeef;

/// Where the text JsonBind.NodeText writes for a node holds each value and member name: an error in that
/// text is located at the node it came from.
internal struct JsonNodeSpan
{
	public int mOffset;
	public uint32 mId;
	public bool mName;

	public this(int offset, uint32 id, bool name)
	{
		mOffset = offset;
		mId = id;
		mName = name;
	}
}

/// @brief Walks the elements of an array being written in place (generated JsonWrite into a node): the
/// existing ones by position, then new ones; Trim removes those left over.
public struct JsonArrayCursor
{
	JsonNode mArray;
	JsonNode mNext;

	/// @brief Start at the first element of `array` (made an array if it is not one).
	/// @param array The node.
	public this(JsonNode array)
	{
		if (!array.IsArray)
			array.SetArray();
		mArray = array;
		mNext = array.FirstChild;
	}

	/// @brief The next element: an existing one, or a new one appended.
	/// @return The element.
	public JsonNode Next() mut
	{
		if (mNext.IsValid)
		{
			let node = mNext;
			mNext = node.Next;
			return node;
		}
		return mArray.Add();
	}

	/// @brief Remove the elements Next did not reach.
	public void Trim() mut
	{
		while (mNext.IsValid)
		{
			let node = mNext;
			mNext = node.Next;
			node.Remove();
		}
	}
}

/// @brief Writes an object's members in place by name (generated JsonWrite of a Dictionary into a node):
/// Finish removes the members Member did not name.
public class JsonMemberWriter
{
	JsonNode mObject;
	HashSet<uint32> mWritten = new .() ~ delete _;

	/// @brief Write into `node` (made an object if it is not one).
	/// @param node The node.
	public this(JsonNode node)
	{
		if (!node.IsObject)
			node.SetObject();
		mObject = node;
	}

	/// @brief The value of the member `name`: the existing one (the last of that name), or a new one.
	/// @param name The member's name.
	/// @return Its value.
	public JsonNode Member(StringView name)
	{
		let node = mObject.Set(name);
		mWritten.Add(node.Id.Value);
		return node;
	}

	/// @brief Remove the members Member did not return (other keys, earlier members of a repeated name).
	public void Finish()
	{
		var node = mObject.FirstChild;
		while (node.IsValid)
		{
			let next = node.Next;
			if (!mWritten.Contains(node.Id.Value))
				node.Remove();
			node = next;
		}
	}
}

extension JsonBind
{
	// Reading a node: its text through the reader

	/// Writes the value `node` compactly into `text` for the reader, noting where each value and member
	/// name starts. Numbers are written as their source text when the document kept it (Positions or
	/// PreserveStyle) and it still holds the node's value, so a float field reads the text, not a double
	/// rounded twice.
	internal static void NodeText(JsonNode node, String text, List<JsonNodeSpan> spans)
	{
		JsonNode current = node;
		while (true)
		{
			if (current != node && current.IsMember)
			{
				spans.Add(.(text.Length, current.mId, true));
				AppendQuotedText(text, current.Name);
				text.Append(':');
			}
			spans.Add(.(text.Length, current.mId, false));
			switch (current.Kind)
			{
			case .Object, .Array:
				bool isObject = current.Kind == .Object;
				text.Append(isObject ? '{' : '[');
				let first = current.FirstChild;
				if (first.IsValid)
				{
					current = first;
					continue;
				}
				text.Append(isObject ? '}' : ']');
			case .String:
				AppendQuotedText(text, current.GetString());
			case .Number:
				AppendNumberText(text, current);
			case .True:
				text.Append("true");
			case .False:
				text.Append("false");
			default:
				text.Append("null");
			}
			// Up to the next sibling, closing the containers left
			while (true)
			{
				if (current == node)
					return;
				let next = current.Next;
				if (next.IsValid)
				{
					text.Append(',');
					current = next;
					break;
				}
				current = current.Parent;
				text.Append(current.Kind == .Object ? '}' : ']');
			}
		}
	}

	static void AppendQuotedText(String text, StringView value)
	{
		text.Append('"');
		JsonWriter.AppendEscaped(text, value, .());
		text.Append('"');
	}

	/// The number's source text when the document has it and it is still the node's value, else its
	/// value written as JsonDocument.Write does.
	static void AppendNumberText(String text, JsonNode node)
	{
		let doc = node.mDocument;
		uint32 id = node.mId;
		if (doc.mSource != null && id < (uint32)doc.mRanges.Count)
		{
			ref JsonRangeRecord range = ref doc.mRanges[id];
			if (range.mLength > 0 && range.mOffset + range.mLength <= doc.mSourceLength)
			{
				StringView lexeme = .(doc.mSource + range.mOffset, range.mLength);
				if (JsonWriter.IsNumberText(lexeme) && SameNumber(node, lexeme))
				{
					text.Append(lexeme);
					return;
				}
			}
		}
		node.AppendNumber(text);
	}

	/// Whether `lexeme` reads as the node's number.
	static bool SameNumber(JsonNode node, StringView lexeme)
	{
		let written = scope String();
		node.AppendNumber(written);
		if (written == lexeme)
			return true;
		switch (node.NumberKind)
		{
		case .Integer:
			int64 value = 0;
			int64 own = 0;
			return JsonNumber.Classify(lexeme) == .Integer && JsonNumber.TryParseInt64(lexeme, out value) && node.TryGetInt64(out own) && value == own;
		case .Float:
			double value = 0;
			double own = 0;
			if (!JsonNumber.ParseDouble(lexeme, out value) || !node.TryGetDouble(out own))
				return false;
			return JsonNumber.ToBits(value) == JsonNumber.ToBits(own);
		default:
			return false;
		}
	}

	/// The error of reading the text NodeText wrote for `node`, located at the node it came from: its
	/// source range when the document has positions, else no position (the path still says where).
	internal static JsonParseError Relocate(JsonNode node, List<JsonNodeSpan> spans, JsonParseError error)
	{
		var error;
		// The last span starting at or before the error
		int low = 0;
		int high = spans.Count - 1;
		while (low < high)
		{
			int mid = (low + high + 1) / 2;
			if (spans[mid].mOffset <= error.mOffset)
				low = mid;
			else
				high = mid - 1;
		}
		error.mLine = 0;
		error.mColumn = 0;
		error.mOffset = 0;
		error.mLength = 0;
		error.mSource = default;
		if (spans.IsEmpty)
			return error;
		let span = spans[low];
		let at = JsonNode(node.mDocument, span.mId);
		JsonSourceRange range = default;
		bool located = span.mName ? at.TryGetNameRange(out range) : at.TryGetSourceRange(out range);
		if (located)
		{
			error.mLine = (int32)range.mLine;
			error.mColumn = (int32)range.mColumn;
			error.mOffset = range.mOffset;
			error.mLength = (int32)range.mLength;
			if (!range.mSource.IsEmpty)
				error.SetSource(range.mSource);
		}
		return error;
	}

	// Writing into a node: values set only when they change

	/// @brief Make `node` an object, unless it is one.
	/// @param node The node.
	public static void MakeObject(JsonNode node)
	{
		if (!node.IsObject)
			node.SetObject();
	}

	/// @brief Rename a member found under an older name `alias` to `name`, unless `name` is there.
	/// @param node The object.
	/// @param name The current name.
	/// @param alias The older name.
	public static void RenameAlias(JsonNode node, StringView name, StringView alias)
	{
		if (node[name].IsValid)
			return;
		let old = node[alias];
		if (old.IsValid)
			old.Rename(name);
	}

	/// @brief `null`.
	public static void SetNull(JsonNode node)
	{
		if (!node.IsNull)
			node.SetNull();
	}

	/// @brief A boolean.
	public static void SetBool(JsonNode node, bool value)
	{
		if (!(node.TryGetBool(let current) && current == value))
			node.SetBool(value);
	}

	/// @brief An integer (an equal integer, however written, is kept).
	public static void SetInteger(JsonNode node, int64 value)
	{
		if (!(node.NumberKind == .Integer && node.TryGetInt64(let current) && current == value))
			node.SetNumber(value);
	}

	/// @brief An unsigned integer.
	public static void SetUInt64(JsonNode node, uint64 value)
	{
		if (!(node.NumberKind != .Float && node.TryGetUInt64(let current) && current == value))
			node.SetNumber(value);
	}

	/// @brief A double (a number of the same value, `2` for 2.0 too, is kept); NaN and ±∞ are an error.
	/// @return .Ok, or InvalidValue (the node is left as it was).
	public static Result<void, JsonWriteError> SetDouble(JsonNode node, double value)
	{
		if (!value.IsFinite)
			return .Err(JsonWriteError(.InvalidValue, scope $"{value} cannot be written as JSON"));
		if (!(node.TryGetDouble(let current) && current == value && JsonNumber.IsNegative(current) == JsonNumber.IsNegative(value)))
			node.SetNumber(value);
		return .Ok;
	}

	/// @brief A float, as its own shortest digits (a number that reads as the same float is kept).
	/// @return .Ok, or InvalidValue for NaN and ±∞.
	public static Result<void, JsonWriteError> SetFloat(JsonNode node, float value)
	{
		if (!value.IsFinite)
			return .Err(JsonWriteError(.InvalidValue, scope $"{value} cannot be written as JSON"));
		if (node.TryGetDouble(let current) && (float)current == value && JsonNumber.IsNegative(current) == JsonNumber.IsNegative(value))
			return .Ok;
		let text = scope String();
		JsonNumber.AppendFloat(text, value);
		node.SetNumberText(text);
		return .Ok;
	}

	/// @brief A string, or `null` for a null String.
	public static void SetString(JsonNode node, String value)
	{
		if (value == null)
			SetNull(node);
		else if (!(node.TryGetString(let current) && current == value))
			node.SetString(value);
	}

	/// @brief A string (an enum case name).
	public static void SetText(JsonNode node, StringView value)
	{
		if (!(node.TryGetString(let current) && current == value))
			node.SetString(value);
	}

	/// @brief The value of the JSON text `json` (a converter's output), unless the node already holds
	/// the same (compared as compact text).
	/// @param node The node.
	/// @param json One JSON value.
	/// @return .Ok, or an error if `json` is not JSON.
	public static Result<void, JsonWriteError> SetJson(JsonNode node, StringView json)
	{
		let current = scope String();
		if (node.Document.Write(node, current) case .Ok && current == json)
			return .Ok;
		var config = JsonReadConfig();
		config.MaxDepth = 0;
		let reader = scope JsonReader(json, config);
		let open = scope List<JsonNode>();
		JsonNode slot = node;
		while (true)
		{
			JsonToken token;
			switch (reader.Next())
			{
			case .Ok(let read):
				token = read;
			case .Err(let error):
				return .Err(JsonWriteError(.InvalidStructure, scope $"A converter wrote text that is not JSON: {error}"));
			}
			if (token == .EndOfDocument)
				return .Ok;
			if (!open.IsEmpty && open.Back.IsArray && token != .EndArray)
				slot = open.Back.Add();
			switch (token)
			{
			case .PropertyName:
				slot = open.Back.Add(reader.StringValue);
				continue;
			case .StartObject:
				slot.SetObject();
				open.Add(slot);
			case .StartArray:
				slot.SetArray();
				open.Add(slot);
			case .EndObject, .EndArray:
				open.PopBack();
			case .String:
				slot.SetString(reader.StringValue);
			case .Number:
				slot.SetNumberText(reader.RawValue);
			case .True:
				slot.SetBool(true);
			case .False:
				slot.SetBool(false);
			default:
				slot.SetNull();
			}
		}
	}
}
