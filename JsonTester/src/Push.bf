using System;
using System.Collections;
using JsonBeef;

namespace JsonTester;

/// `-push N`: the input fed to a JsonPushReader N bytes at a time, the canonical form printed from its
/// tokens (Canonical.Write's rules), so the suite can require exactly the memory read's output and
/// first error.
static class Push
{
	public static Result<void, JsonParseError> Canonical(StringView text, int chunk, JsonReadConfig config, String output)
	{
		let reader = scope JsonPushReader(config);
		let hasElement = scope List<bool>();
		bool afterName = false;
		int fed = 0;
		while (true)
		{
			let token = Try!(reader.Next());
			if (token == .None)
			{
				// More input, or the end of it
				if (fed < text.Length)
				{
					int count = Math.Min(chunk, text.Length - fed);
					reader.Feed(text.Substring(fed, count));
					fed += count;
				}
				else
					reader.Finish();
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
				JsonTester.Canonical.AppendString(output, reader.StringValue);
				output.Append(':');
				afterName = true;
			case .String:
				JsonTester.Canonical.AppendString(output, reader.StringValue);
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

	static void AppendNumber(String output, JsonPushReader reader)
	{
		switch (reader.NumberKind)
		{
		case .Integer:
			if (reader.StringValue == "-0")
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
			JsonTester.Canonical.AppendDouble(output, reader.StringValue);
		case .NonFinite:
			reader.TryGetDouble(let value);
			output.Append(value.IsNaN ? "NaN" : value < 0 ? "-Infinity" : "Infinity");
		}
	}
}
