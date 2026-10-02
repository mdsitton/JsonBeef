using System;
using JsonBeef;

namespace JsonBeefBench;

/// JsonBeef (this repository): the JsonDocument DOM and the JsonReader pull reader.
static class JsonBeefBench
{
	/// One document object, read again for every run: it keeps its memory between reads (its intended
	/// use, as simdjson's parser is reused in that harness).
	static JsonDocument sDocument = new .() ~ delete _;
	static JsonReader sReader = new .() ~ delete _;

	static void Walk(JsonNode top, ref Program.Check c)
	{
		JsonNode node = top;
		while (true)
		{
			if (node != top && node.IsMember)
			{
				c.mKeys++;
				c.mChars += Program.Chars(node.Name);
			}
			switch (node.Kind)
			{
			case .Object:
				c.mObjects++;
			case .Array:
				c.mArrays++;
			case .String:
				c.mStrings++;
				c.mChars += Program.Chars(node.GetString());
			case .Number:
				// Integers (int64, uint64, big) round to the nearest double; floats are the parse's
				if (node.TryGetDouble(let value))
					c.Number(value);
				else
				{
					// Beyond a double's range: Python's float() gives the infinity
					let text = node.AppendNumber(.. scope String());
					c.Number(text[0] == '-' ? double.NegativeInfinity : double.PositiveInfinity);
				}
			case .True:
				c.mTrues++;
			case .False:
				c.mFalses++;
			case .Null:
				c.mNulls++;
			}
			if ((node.IsArray || node.IsObject) && node.Count > 0)
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

	/// Parses one document into the tree; with `check`, counts it.
	public static bool Dom(StringView text, Program.Check* check)
	{
		switch (sDocument.Read(text))
		{
		case .Ok:
			if (check != null)
				Walk(sDocument.Root, ref *check);
			return true;
		case .Err(let err):
			if (check != null)
				Console.Error.WriteLine(scope $"parse error: {err}");
			return false;
		}
	}

	/// One pass over the tokens: every key and string decoded (the reader decodes as it scans; lengths
	/// in code points when `exact`, else touched in bytes), every number converted to a double.
	public static bool Stream(StringView text, Program.Check* check, bool exact)
	{
		sReader.Reset(text);
		while (true)
		{
			switch (sReader.Next())
			{
			case .Ok(let token):
				switch (token)
				{
				case .StartObject:
					check.mObjects++;
				case .StartArray:
					check.mArrays++;
				case .PropertyName:
					check.mKeys++;
					check.mChars += exact ? Program.Chars(sReader.StringValue) : sReader.StringValue.Length;
				case .String:
					check.mStrings++;
					check.mChars += exact ? Program.Chars(sReader.StringValue) : sReader.StringValue.Length;
				case .Number:
					if (sReader.TryGetDouble(let value))
						check.Number(value);
					else
						check.Number(sReader.RawValue[0] == '-' ? double.NegativeInfinity : double.PositiveInfinity);
				case .True:
					check.mTrues++;
				case .False:
					check.mFalses++;
				case .Null:
					check.mNulls++;
				case .EndOfDocument:
					return true;
				default:
				}
			case .Err(let err):
				if (exact)
					Console.Error.WriteLine(scope $"parse error: {err}");
				return false;
			}
		}
	}
}
