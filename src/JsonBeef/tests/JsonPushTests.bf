using System;
using System.Collections;
using JsonBeef;
using static JsonBeef.Tests.JsonTestUtil;

namespace JsonBeef.Tests;

/// JsonPushReader: tokens only once whole, exactly those (and the errors) of reading from memory.
static class JsonPushTests
{
	/// The trace of `text` fed `chunk` bytes at a time (Finish after the last), as JsonTestUtil.Trace
	/// writes it, or the error as `kind line:column`.
	static String PushTrace(StringView text, int chunk, String trace, JsonReadConfig config = .())
	{
		let reader = scope JsonPushReader(config);
		int fed = 0;
		while (true)
		{
			JsonToken token;
			switch (reader.Next())
			{
			case .Ok(let read):
				token = read;
			case .Err(let error):
				trace.Clear();
				trace.AppendF("{} {}:{}", error.mKind, error.mLine, error.mColumn);
				return trace;
			}
			if (token == .None)
			{
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
				return trace;
			if (!trace.IsEmpty)
				trace.Append(' ');
			switch (token)
			{
			case .StartObject: trace.Append('{');
			case .EndObject: trace.Append('}');
			case .StartArray: trace.Append('[');
			case .EndArray: trace.Append(']');
			case .PropertyName: trace.AppendF("{}:", reader.StringValue);
			case .String: trace.AppendF("\"{}\"", reader.StringValue);
			default: trace.Append(reader.RawValue);
			}
		}
	}

	/// The memory read's trace or error, in PushTrace's form.
	static String MemoryTrace(StringView text, String trace, JsonReadConfig config = .())
	{
		let reader = scope JsonReader(text, config);
		if (Trace(reader, trace) case .Err(let error))
		{
			trace.Clear();
			trace.AppendF("{} {}:{}", error.mKind, error.mLine, error.mColumn);
		}
		return trace;
	}

	[Test]
	public static void EveryChunkSize()
	{
		let texts = StringView[](
			"{\"a\": [1, -2.5e+3, true, null, \"x\\u00e9\\ud83d\\ude00\"], \"b\": {}, \"c\": 12345678901234567890}",
			"\xEF\xBB\xBF [ \"long string with \\\" escaped quotes \\\\ and more\" , 0 ] ",
			"[1,\n 2,]",
			"{\"a\" 1}",
			"[\"\xFF\"]",
			"123",
			"tru",
			"",
			"   ");
		for (let text in texts)
		{
			let expected = MemoryTrace(text, scope .());
			for (int chunk = 1; chunk <= 6; chunk++)
			{
				let got = PushTrace(text, chunk, scope .());
				Test.Assert(got == expected, scope $"`{text}` fed {chunk} at a time: `{got}`, from memory `{expected}`");
			}
		}
	}

	[Test]
	public static void WaitsForWholeTokens()
	{
		let reader = scope JsonPushReader();
		// The first four bytes decide the encoding (a BOM, UTF-16): nothing before them
		reader.Feed("[12");
		Test.Assert(reader.Next() case .Ok(.None));
		reader.Feed("3");
		Test.Assert(reader.Next() case .Ok(.StartArray));
		// The number may go on
		Test.Assert(reader.Next() case .Ok(.None));
		reader.Feed("]");
		Test.Assert(reader.Next() case .Ok(.Number));
		int64 value = 0;
		Test.Assert(reader.RawValue == "123" && reader.TryGetInt64(out value) && value == 123);
		Test.Assert(reader.Next() case .Ok(.EndArray));
		// More may follow the value (an error, if it comes): the end is known at Finish
		Test.Assert(reader.Next() case .Ok(.None));
		reader.Finish();
		Test.Assert(reader.Next() case .Ok(.EndOfDocument));
	}

	[Test]
	public static void LongStringByteByByte()
	{
		let text = scope String("[\"");
		for (int i < 5000)
			text.Append(((i % 7) == 0) ? "\\\"" : "ab");
		text.Append("\"]");
		let reader = scope JsonPushReader();
		int strings = 0;
		int fed = 0;
		while (true)
		{
			let token = reader.Next().Value;
			if (token == .EndOfDocument)
				break;
			if (token == .String)
			{
				strings++;
				Test.Assert(reader.StringValue.Length == 5000 * 2 - (5000 + 6) / 7);
			}
			if (token == .None)
			{
				if (fed < text.Length)
					reader.Feed(text.Substring(fed++, 1));
				else
					reader.Finish();
			}
		}
		Test.Assert(strings == 1);
	}

	[Test]
	public static void Limits()
	{
		var config = JsonReadConfig();
		config.MaxInputBytes = 8;
		Test.Assert(PushTrace("[1, 2, 3, 4]", 3, scope .(), config).StartsWith("ResourceLimitExceeded"));
		var token = JsonReadConfig();
		token.MaxTokenBytes = 16;
		Test.Assert(PushTrace("[\"0123456789012345678901234\"]", 2, scope .(), token).StartsWith("ResourceLimitExceeded"));
		// UTF-16 is told from its first bytes, however they are fed
		Test.Assert(PushTrace("\xFF\xFE[\x001\x00]\x00", 1, scope .()).StartsWith("UnsupportedEncoding"));
	}
}
