using System;
using Json;

namespace JsonBeefBench;

/// EinScott/json: Json.ReadJson into a JsonTree of JsonElement values
static class EinScottBench
{
	static void Walk(JsonElement v, ref Program.Check c)
	{
		switch (v)
		{
		case .Null:
			c.mNulls++;
		case .Bool(let b):
			if (b)
				c.mTrues++;
			else
				c.mFalses++;
		case .Number(let d):
			c.Number(d);
		case .String(let s):
			c.mStrings++;
			c.mChars += Program.Chars(s);
		case .Object(let obj):
			c.mObjects++;
			for (let (key, value) in obj)
			{
				c.mKeys++;
				c.mChars += Program.Chars(key);
				Walk(value, ref c);
			}
		case .Array(let arr):
			c.mArrays++;
			for (let value in arr)
				Walk(value, ref c);
		}
	}

	public static bool Dom(StringView text, Program.Check* check)
	{
		let tree = scope JsonTree();
		if (Json.ReadJson(text, tree) case .Err(let err))
		{
			if (check != null)
				Console.Error.WriteLine(scope $"parse error: {err}");
			return false;
		}
		if (check != null)
			Walk(tree.root, ref *check);
		return true;
	}
}
