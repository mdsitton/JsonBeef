using System;
using Beefy.utils;

namespace JsonBeefBench;

/// Beef's built-in Beefy.utils.StructuredData (src/beefy, copied from the installed Beef by
/// ../../fetch.sh), walked with its own cursor API (GetCurrent and Enumerate)
static class StructuredDataBench
{
	static void Walk(StructuredData sd, ref Program.Check c)
	{
		Object v = sd.GetCurrent();
		if (v == null)
		{
			c.mNulls++;
			return;
		}
		if (v is StructuredData.NamedValues)
		{
			c.mObjects++;
			for (let key in sd.Enumerate())
			{
				c.mKeys++;
				c.mChars += Program.Chars(key);
				Walk(sd, ref c);
			}
			return;
		}
		if (v is StructuredData.Values)
		{
			c.mArrays++;
			for (let _ in sd.Enumerate())
				Walk(sd, ref c);
			return;
		}
		if (let s = v as String)
		{
			c.mStrings++;
			c.mChars += Program.Chars(s);
		}
		else if (v is StringView)
		{
			c.mStrings++;
			c.mChars += Program.Chars((StringView)v);
		}
		else if (v is bool)
		{
			if ((bool)v)
				c.mTrues++;
			else
				c.mFalses++;
		}
		else if (v is int64)
			c.Number((double)(int64)v);
		else if (v is float)
			c.Number((double)(float)v);
		else
			c.mNulls += 1000000; // an unknown representation: make the check fail
	}

	public static bool Dom(StringView text, Program.Check* check)
	{
		let sd = scope StructuredData();
		if (sd.LoadFromString(text) case .Err(let err))
		{
			if (check != null)
				Console.Error.WriteLine(scope $"parse error: {err}");
			return false;
		}
		if (check != null)
			Walk(sd, ref *check);
		return true;
	}
}
