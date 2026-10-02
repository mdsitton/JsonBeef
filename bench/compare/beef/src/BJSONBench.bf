using System;
using System.IO;
using BJSON;
using BJSON.Models;

namespace JsonBeefBench;

/// M0n7y5/BJSON: its JsonValue DOM and its JsonReader + IHandler streaming contract
static class BJSONBench
{
	static void Walk(JsonValue v, ref Program.Check c)
	{
		switch (v.type)
		{
		case .NULL:
			c.mNulls++;
		case .BOOL:
			if (v.data.boolean)
				c.mTrues++;
			else
				c.mFalses++;
		case .NUMBER:
			c.Number(v.data.number);
		case .NUMBER_SIGNED:
			c.Number((double)v.data.signedNumber);
		case .NUMBER_UNSIGNED:
			c.Number((double)v.data.unsignedNumber);
		case .STRING:
			c.mStrings++;
			var copy = v;
			StringView s = copy;
			c.mChars += Program.Chars(s);
		case .OBJECT:
			c.mObjects++;
			for (let kv in v.data.object)
			{
				c.mKeys++;
				c.mChars += Program.Chars(kv.key);
				Walk(kv.value, ref c);
			}
		case .ARRAY:
			c.mArrays++;
			for (let x in v.data.array)
				Walk(x, ref c);
		}
	}

	/// Parses one document into the tree and disposes it; with `check`, counts it first
	public static bool Dom(StringView text, Program.Check* check)
	{
		switch (BJSON.Json.Deserialize(text))
		{
		case .Ok(var value):
			if (check != null)
				Walk(value, ref *check);
			value.Dispose();
			return true;
		case .Err(let err):
			if (check != null)
				Console.Error.WriteLine(scope $"parse error: {err}");
			return false;
		}
	}

	/// Counts every event; lengths in code points when `exact`, else in bytes (the timed runs only
	/// need to touch each string)
	class CountingHandler : IHandler
	{
		public Program.Check mCheck;
		public bool mExact;

		public bool Null() { mCheck.mNulls++; return true; }

		public bool Bool(bool b)
		{
			if (b)
				mCheck.mTrues++;
			else
				mCheck.mFalses++;
			return true;
		}

		public bool Number(double n) { mCheck.Number(n); return true; }
		public bool Number(int64 n) { mCheck.Number((double)n); return true; }
		public bool Number(uint64 n) { mCheck.Number((double)n); return true; }

		public bool String(StringView str, bool copy)
		{
			mCheck.mStrings++;
			mCheck.mChars += mExact ? Program.Chars(str) : str.Length;
			return true;
		}

		public bool Key(StringView str, bool copy)
		{
			mCheck.mKeys++;
			mCheck.mChars += mExact ? Program.Chars(str) : str.Length;
			return true;
		}

		public bool StartObject() { mCheck.mObjects++; return true; }
		public bool EndObject() => true;
		public bool StartArray() { mCheck.mArrays++; return true; }
		public bool EndArray() => true;
	}

	/// One pass over the document's events, added to `check`
	public static bool Stream(StringView text, Program.Check* check, bool exact)
	{
		let handler = scope CountingHandler();
		handler.mCheck = *check;
		handler.mExact = exact;
		let reader = scope JsonReader(handler);
		if (reader.Parse(scope StringStream(text, .Reference)) case .Err(let err))
		{
			if (exact)
				Console.Error.WriteLine(scope $"parse error: {err}");
			return false;
		}
		*check = handler.mCheck;
		return true;
	}
}
