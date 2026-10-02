using System;
using System.IO;
using static JsonBeef.Tests.JsonTestUtil;

namespace JsonBeef.Tests;

/// JsonReader's API: token properties, depth and offsets, raw and decoded strings, stickiness of errors,
/// the limits of JsonReadConfig, and streams (buffer growth, MaxTokenBytes, I/O-like ends).
static class JsonReaderTests
{
	[Test]
	public static void Tokens_DepthAndOffsets()
	{
		let reader = scope JsonReader("{\"a\": [1, \"x\"], \"b\": {}}");
		(JsonToken token, int depth, int offset, int end)[?] expected = .(
			(.StartObject, 0, 0, 1), (.PropertyName, 1, 1, 4), (.StartArray, 1, 6, 7), (.Number, 2, 7, 8),
			(.String, 2, 10, 13), (.EndArray, 1, 13, 14), (.PropertyName, 1, 16, 19), (.StartObject, 1, 21, 22),
			(.EndObject, 1, 22, 23), (.EndObject, 0, 23, 24), (.EndOfDocument, 0, 24, 24));
		for (let e in expected)
		{
			Test.Assert(reader.Next() case .Ok(let token) && token == e.token, scope $"expected {e.token}");
			Test.Assert(reader.TokenType == e.token);
			Test.Assert(reader.Depth == e.depth && reader.Offset == e.offset && reader.EndOffset == e.end,
				scope $"{e.token}: depth {reader.Depth}, {reader.Offset}..{reader.EndOffset}");
		}
		// EndOfDocument again
		Test.Assert(reader.Next() case .Ok(.EndOfDocument));
	}

	[Test]
	public static void Strings_RawAndDecoded()
	{
		let reader = scope JsonReader("[\"plain\", \"a\\nb\\u00e9\"]");
		Test.Assert(reader.Next() case .Ok(.StartArray));
		Test.Assert(reader.Next() case .Ok(.String) && reader.StringValue == "plain" && reader.RawValue == "plain" && !reader.ValueIsEscaped);
		Test.Assert(reader.Next() case .Ok(.String) && reader.StringValue == "a\nb\u{E9}" && reader.RawValue == "a\\nb\\u00e9" && reader.ValueIsEscaped);
		let copy = scope String();
		reader.GetString(copy);
		Test.Assert(copy == "a\nb\u{E9}");
	}

	[Test]
	public static void Numbers_RawText()
	{
		let reader = scope JsonReader("[1.50e+03, -0, 18446744073709551616]");
		Test.Assert(reader.Next() case .Ok(.StartArray));
		Test.Assert(reader.Next() case .Ok(.Number) && reader.RawValue == "1.50e+03" && reader.NumberKind == .Float && IsDouble(reader, 1500));
		Test.Assert(reader.Next() case .Ok(.Number) && reader.RawValue == "-0" && reader.NumberKind == .Integer);
		Test.Assert(reader.Next() case .Ok(.Number) && reader.NumberKind == .BigInteger);
		// A conversion asked of another token fails
		Test.Assert(reader.Next() case .Ok(.EndArray) && !reader.TryGetDouble(?) && !reader.TryGetInt64(?));
	}

	[Test]
	public static void Errors_AreSticky()
	{
		let reader = scope JsonReader("[1,]");
		Test.Assert(reader.Next() case .Ok(.StartArray));
		Test.Assert(reader.Next() case .Ok(.Number));
		Test.Assert(reader.Next() case .Err(let first) && first.mKind == .InvalidStructure);
		Test.Assert(reader.IsStopped);
		Test.Assert(reader.Next() case .Err(let again) && again.mKind == .InvalidStructure && again.mColumn == 4);
	}

	[Test]
	public static void Errors_SourceNameAndText()
	{
		var config = JsonReadConfig();
		config.SourceName = "settings.json";
		let reader = scope JsonReader("{\n  \"a\": tru\n}", config);
		JsonParseError error = default;
		while (true)
		{
			if (reader.Next() case .Err(out error))
				break;
		}
		Test.Assert(error.mSource == "settings.json" && error.mLine == 2 && error.mColumn == 8);
		let text = error.ToString(.. scope .());
		Test.Assert(text == "settings.json:2:8: Invalid literal `tru` (expected `true`)", text);
	}

	[Test]
	public static void Reset_ReusesTheReader()
	{
		let reader = scope JsonReader("[1");
		Test.Assert(reader.Next() case .Ok(.StartArray));
		Test.Assert(reader.Next() case .Ok(.Number));
		Test.Assert(reader.Next() case .Err);
		reader.Reset("{}");
		Test.Assert(!reader.IsStopped);
		Test.Assert(reader.Next() case .Ok(.StartObject));
		Test.Assert(reader.Next() case .Ok(.EndObject));
		Test.Assert(reader.Next() case .Ok(.EndOfDocument));
	}

	[Test]
	public static void Limits_MaxDepth()
	{
		var config = JsonReadConfig();
		config.MaxDepth = 2;
		Accepts("[[1]]", config);
		Rejects("[[[1]]]", .ResourceLimitExceeded, 1, 3, 2, config);
		Rejects("{\"a\":{\"b\":[]}}", .ResourceLimitExceeded, 1, 11, 10, config);
		// 0: unlimited (depth is a bit per level)
		config.MaxDepth = 0;
		let deep = scope String();
		Repeat("[", 100000, deep);
		Repeat("]", 100000, deep);
		Accepts(deep, config);
	}

	[Test]
	public static void Limits_MaxInputBytes()
	{
		var config = JsonReadConfig();
		config.MaxInputBytes = 8;
		Accepts("[1,2,3]", config);
		// From memory the size is checked up front
		let memory = scope JsonReader("[1,2,3,4]", config);
		Test.Assert(memory.Next() case .Err(let sizeError) && sizeError.mKind == .ResourceLimitExceeded && sizeError.mOffset == 0);
		// A stream fails when it reads past the limit, after the tokens before it
		let text = "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]";
		config.MaxInputBytes = 30;
		config.StreamBufferBytes = 16;
		let stream = scope JsonTestStream(text, 1);
		let reader = scope JsonReader();
		reader.Reset(stream, config);
		JsonParseError error = default;
		while (true)
		{
			if (reader.Next() case .Err(out error))
				break;
		}
		Test.Assert(error.mKind == .ResourceLimitExceeded);
	}

	[Test]
	public static void Limits_MaxStringBytes()
	{
		var config = JsonReadConfig();
		config.MaxStringBytes = 4;
		Accepts("[\"abcd\", \"\\u00e9\\u00e9\"]", config);
		Rejects("[\"abcde\"]", .ResourceLimitExceeded, 1, 2, 1, config);
		Rejects("{\"abcde\":1}", .ResourceLimitExceeded, 1, 2, 1, config);
		// Decoded length: three é are six bytes
		Rejects("[\"\\u00e9\\u00e9\\u00e9\"]", .ResourceLimitExceeded, 1, 2, 1, config);
	}

	[Test]
	public static void Limits_MaxNumberLength()
	{
		var config = JsonReadConfig();
		config.MaxNumberLength = 5;
		Accepts("[12345, -1234, 1.5e3]", config);
		Rejects("[123456]", .ResourceLimitExceeded, 1, 2, 1, config);
		Rejects("[1.5e-10]", .ResourceLimitExceeded, 1, 2, 1, config);
	}

	[Test]
	public static void Stream_LongTokensGrowTheBuffer()
	{
		// Strings, numbers and escapes much longer than the 16-byte buffer, read 1 and 7 bytes at a time
		let text = scope String("[\"");
		Repeat("abcdefghij\\u00e9\\uD834\\uDD1E", 20, text);
		text.Append("\", ");
		Repeat("1234567890", 10, text);
		text.Append(".5e-3, ");
		Repeat("\"x\", ", 30, text);
		text.Append("true]");
		let expected = scope String();
		Test.Assert(Read(text, expected) case .Ok);
		for (int chunk in int[](1, 7, 64))
		{
			var config = JsonReadConfig();
			config.StreamBufferBytes = 16;
			let stream = scope:: JsonTestStream(text, chunk);
			let reader = scope:: JsonReader();
			reader.Reset(stream, config);
			let trace = scope:: String();
			Test.Assert(Trace(reader, trace) case .Ok);
			Test.Assert(trace == expected);
		}
	}

	[Test]
	public static void Stream_MaxTokenBytes()
	{
		var config = JsonReadConfig();
		config.StreamBufferBytes = 16;
		config.MaxTokenBytes = 32;
		let ok = scope String("[\"");
		Repeat("a", 28, ok);
		ok.Append("\"]");
		let stream = scope JsonTestStream(ok, 3);
		let reader = scope JsonReader();
		reader.Reset(stream, config);
		Test.Assert(Trace(reader, scope .()) case .Ok);

		let long = scope String("[\"");
		Repeat("a", 100, long);
		long.Append("\"]");
		let longStream = scope JsonTestStream(long, 3);
		reader.Reset(longStream, config);
		Test.Assert(Trace(reader, scope .()) case .Err(let error) && error.mKind == .ResourceLimitExceeded);
		// Memory input has no token limit
		Accepts(long);
	}

	[Test]
	public static void Stream_InvalidUtf8AfterTokens()
	{
		// An encoding error beyond the first buffer comes after the tokens before it, located exactly
		let text = scope String("[");
		Repeat("1, ", 20, text);
		text.Append("\"\xFF\"]");
		var config = JsonReadConfig();
		config.StreamBufferBytes = 16;
		let stream = scope JsonTestStream(text, 1);
		let reader = scope JsonReader();
		reader.Reset(stream, config);
		int numbers = 0;
		JsonParseError error = default;
		while (true)
		{
			switch (reader.Next())
			{
			case .Ok(let token):
				if (token == .Number)
					numbers++;
				continue;
			case .Err(out error):
			}
			break;
		}
		Test.Assert(numbers == 20 && error.mKind == .InvalidUtf8 && error.mLine == 1 && error.mColumn == 63);
		// From memory, the whole input is checked first
		Rejects(text, .InvalidUtf8, 1, 63);
	}

	[Test]
	public static void Stream_CrLfAcrossRefills()
	{
		// Line counting stays right when a refill splits a CRLF
		let text = "[1,\r\n2,\r\n3,\r\n4,\r\n5,\r\n6,\r\n7,\r\n8,\r\n x]";
		Rejects(text, .InvalidLiteral, 9, 2);
	}

	[Test]
	public static void Values_GetDoubleOnIntegers()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "-9007199254740993");
		Test.Assert(IsInt64(reader, -9007199254740993));
		Test.Assert(reader.TryGetDouble(let value) && JsonNumber.ToBits(value) == JsonNumber.ToBits(-9007199254740992.0));
		ReadNumber(reader, "12345");
		Test.Assert(IsDouble(reader, 12345));
		ReadNumber(reader, "18446744073709551615");
		Test.Assert(IsDouble(reader, 18446744073709551616.0));
	}

	[Test]
	public static void Values_UInt64OfNonNegativeIntegers()
	{
		let reader = scope JsonReader();
		ReadNumber(reader, "42");
		Test.Assert(reader.TryGetUInt64(let value) && value == 42);
		ReadNumber(reader, "-1");
		Test.Assert(!reader.TryGetUInt64(?));
		ReadNumber(reader, "1.0");
		Test.Assert(!reader.TryGetUInt64(?) && !reader.TryGetInt64(?) && IsDouble(reader, 1));
	}

	[Test]
	public static void Numbers_StaticConversions()
	{
		Test.Assert(JsonNumber.TryParseInt64("-9223372036854775808", let min) && min == int64.MinValue);
		Test.Assert(!JsonNumber.TryParseInt64("9223372036854775808", ?));
		Test.Assert(JsonNumber.TryParseUInt64("18446744073709551615", let max) && max == uint64.MaxValue);
		Test.Assert(!JsonNumber.TryParseUInt64("18446744073709551616", ?));
		Test.Assert(JsonNumber.TryParseUInt64("-0", let zero) && zero == 0);
		Test.Assert(JsonNumber.Classify("1") == .Integer && JsonNumber.Classify("9223372036854775808") == .UInteger);
		Test.Assert(JsonNumber.Classify("1e2") == .Float && JsonNumber.Classify("-9223372036854775809") == .BigInteger);
	}

	[Test]
	public static void Numbers_PlainLayout()
	{
		(double value, StringView text)[?] samples = .((1.0, "1.0"), (100.0, "100.0"), (0.0, "0.0"), (-0.0, "-0.0"),
			(1e21, "1e21"), (1e20, "100000000000000000000.0"), (1.5e-7, "1.5e-7"), (5e-324, "5e-324"),
			(1.7976931348623157e308, "1.7976931348623157e308"), (-1.2345, "-1.2345"), (0.000001, "0.000001"),
			(2.225073858507201e-308, "2.225073858507201e-308"));
		for (let sample in samples)
		{
			let text = Format(sample.value, .Plain, scope .());
			Test.Assert(text == sample.text, scope $"`{text}`, expected `{sample.text}`");
		}
	}
}
