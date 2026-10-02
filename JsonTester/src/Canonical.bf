using System;
using System.Collections;
using JsonBeef;

namespace JsonTester;

/// The canonical output form of docs/test-suites.md §9.2: no whitespace, members in document order with
/// duplicates, JCS string escaping, integers that fit 64 bits exactly (`-0` as `-0`), every other
/// number as its double in ECMAScript layout with negative zero `-0` and overflow as ±`Infinity`.
static class Canonical
{
	/// Reads the whole document from `reader` and appends its canonical form (without the final newline).
	/// With `errors` (a reader with CollectErrors), each error is appended to it as a line
	/// `line:column: Kind: message` and the read goes on until the reader stops.
	public static Result<void, JsonParseError> Write(JsonReader reader, String output, String errors = null)
	{
		// Whether the open container already has an element (a comma goes before the next)
		let hasElement = scope List<bool>();
		bool afterName = false;
		while (true)
		{
			JsonToken token;
			switch (reader.Next())
			{
			case .Ok(let next):
				token = next;
			case .Err(let error):
				if (errors == null)
					return .Err(error);
				errors.AppendF("{}:{}: {}: {}\n", error.mLine, error.mColumn, error.mKind, error.mMessage);
				if (reader.IsStopped)
					return .Ok;
				continue;
			}
			if (token == .EndOfDocument)
				return .Ok;
			if (token == .EndObject || token == .EndArray)
			{
				output.Append(token == .EndObject ? '}' : ']');
				hasElement.PopBack();
				afterName = false;
				continue;
			}
			if (afterName)
				afterName = false;
			else if (hasElement.Count > 0)
			{
				if (hasElement.Back)
					output.Append(',');
				hasElement.Back = true;
			}
			switch (token)
			{
			case .StartObject:
				output.Append('{');
				hasElement.Add(false);
			case .StartArray:
				output.Append('[');
				hasElement.Add(false);
			case .PropertyName:
				AppendString(output, reader.StringValue);
				output.Append(':');
				afterName = true;
			case .String:
				AppendString(output, reader.StringValue);
			case .Number:
				AppendNumber(output, reader);
			case .True:
				output.Append("true");
			case .False:
				output.Append("false");
			case .Null:
				output.Append("null");
			default:
			}
		}
	}

	/// The canonical form of a document's value and its subtree, walked without recursion.
	public static void Write(JsonNode top, String output)
	{
		JsonNode node = top;
		while (true)
		{
			if (node != top && node.IsMember)
			{
				AppendString(output, node.Name);
				output.Append(':');
			}
			switch (node.Kind)
			{
			case .Object, .Array:
				output.Append(node.Kind == .Object ? '{' : '[');
				if (node.Count > 0)
				{
					node = node.FirstChild;
					continue;
				}
				output.Append(node.Kind == .Object ? '}' : ']');
			case .String:
				AppendString(output, node.GetString());
			case .Number:
				AppendNumber(output, node);
			case .True:
				output.Append("true");
			case .False:
				output.Append("false");
			case .Null:
				output.Append("null");
			}
			// Up to the next sibling, closing the containers left
			while (true)
			{
				if (node == top)
					return;
				let next = node.Next;
				if (next.IsValid)
				{
					output.Append(',');
					node = next;
					break;
				}
				node = node.Parent;
				output.Append(node.Kind == .Object ? '}' : ']');
			}
		}
	}

	/// Every member name and string of the subtree in document order, one per line (canonically escaped).
	public static void WriteStrings(JsonNode top, String output)
	{
		JsonNode node = top;
		while (true)
		{
			if (node != top && node.IsMember)
			{
				AppendString(output, node.Name);
				output.Append('\n');
			}
			if (node.IsString)
			{
				AppendString(output, node.GetString());
				output.Append('\n');
			}
			if (node.Count > 0 && (node.IsArray || node.IsObject))
			{
				node = node.FirstChild;
				continue;
			}
			while (true)
			{
				if (node == top)
					return;
				let next = node.Next;
				if (next.IsValid)
				{
					node = next;
					break;
				}
				node = node.Parent;
			}
		}
	}

	/// A document number in canonical form.
	public static void AppendNumber(String output, JsonNode node)
	{
		switch (node.NumberKind)
		{
		case .Integer, .UInteger:
			node.AppendNumber(output);
		case .Float, .BigInteger:
			if (node.TryGetDouble(let value))
				JsonNumber.AppendCanonical(output, value);
			else
			{
				let text = node.AppendNumber(.. scope .());
				output.Append(text[0] == '-' ? "-Infinity" : "Infinity");
			}
		}
	}

	/// A string in JCS escaping (RFC 8785 §3.2.2.2): `\"`, `\\`, `\b \t \n \f \r`, other controls as
	/// `\u00xx` in lowercase hex, everything else raw.
	public static void AppendString(String output, StringView text)
	{
		output.Append('"');
		int runStart = 0;
		for (int i < text.Length)
		{
			char8 c = text[i];
			if (c != '"' && c != '\\' && (uint8)c >= 0x20)
				continue;
			output.Append(text.Ptr + runStart, i - runStart);
			runStart = i + 1;
			switch (c)
			{
			case '"': output.Append("\\\"");
			case '\\': output.Append("\\\\");
			case '\b': output.Append("\\b");
			case '\t': output.Append("\\t");
			case '\n': output.Append("\\n");
			case '\f': output.Append("\\f");
			case '\r': output.Append("\\r");
			default:
				const String hex = "0123456789abcdef";
				output.Append("\\u00");
				output.Append(hex[(uint8)c >> 4]);
				output.Append(hex[(uint8)c & 0xF]);
			}
		}
		output.Append(text.Ptr + runStart, text.Length - runStart);
		output.Append('"');
	}

	/// The current number token in canonical form.
	public static void AppendNumber(String output, JsonReader reader)
	{
		switch (reader.NumberKind)
		{
		case .Integer:
			if (reader.RawValue == "-0")
			{
				output.Append("-0");
				return;
			}
			reader.TryGetInt64(let value);
			output.AppendF("{}", value);
		case .UInteger:
			reader.TryGetUInt64(let value);
			output.AppendF("{}", value);
		case .Float, .BigInteger:
			AppendDouble(output, reader.RawValue);
		}
	}

	/// The double of a number token in ECMAScript layout, negative zero `-0`, overflow ±`Infinity`.
	public static void AppendDouble(String output, StringView token)
	{
		if (!JsonNumber.ParseDouble(token, let value))
		{
			output.Append(value < 0 ? "-Infinity" : "Infinity");
			return;
		}
		JsonNumber.AppendCanonical(output, value);
	}
}
