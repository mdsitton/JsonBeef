using System;
using System.Collections;
using JsonBeef;

namespace JsonBeef.Tests;

/// SkipValue, ReadRaw and the reader's Find: from memory and through streams that hand out a few bytes
/// per read, and always checking what they pass.
static class JsonOnDemandTests
{
	/// A reader that owns the stream it reads.
	class OwningReader : JsonReader
	{
		public JsonTestStream mInput ~ delete _;
	}

	/// A reader over `text` from memory (chunk 0) or through a stream giving `chunk` bytes per read with
	/// a 16-byte buffer.
	static JsonReader Open(StringView text, int chunk, JsonReadConfig config = .())
	{
		let reader = new OwningReader();
		if (chunk == 0)
		{
			reader.Reset(text, config);
			return reader;
		}
		var streamConfig = config;
		streamConfig.StreamBufferBytes = 16;
		reader.mInput = new JsonTestStream(text, chunk);
		reader.Reset(reader.mInput, streamConfig);
		return reader;
	}

	static void ExpectKind<T>(Result<T, JsonParseError> result, JsonErrorKind kind, int line = Compiler.CallerLineNum)
	{
		switch (result)
		{
		case .Ok:
			Test.FatalError(scope $"line {line}: no error, expected {kind}");
		case .Err(let error):
			if (error.mKind != kind)
				Test.FatalError(scope $"line {line}: got {error.mKind}: {error}");
		}
	}

	[Test]
	public static void SkipValue_PassesWholeValues()
	{
		let text = """
			{"a": {"x": [1, 2, {"y": "\\u00e9"}], "z": null}, "b": [[], {}], "c": "after"}
			""";
		for (int chunk in int[](0, 1, 3))
		{
			let reader = Open(text, chunk);
			defer delete reader;
			Test.Assert(reader.Next() case .Ok(.StartObject));
			Test.Assert(reader.Next() case .Ok(.PropertyName));
			// At a name: the member's value
			Test.Assert(reader.SkipValue() case .Ok);
			Test.Assert(reader.TokenType == .EndObject && reader.Depth == 1);
			Test.Assert(reader.Next() case .Ok(.PropertyName) && reader.StringValue == "b");
			Test.Assert(reader.Next() case .Ok(.StartArray));
			Test.Assert(reader.SkipValue() case .Ok);
			Test.Assert(reader.TokenType == .EndArray);
			Test.Assert(reader.Next() case .Ok(.PropertyName) && reader.StringValue == "c");
			Test.Assert(reader.Next() case .Ok(.String));
			// A scalar is its own last token
			Test.Assert(reader.SkipValue() case .Ok);
			Test.Assert(reader.TokenType == .String && reader.StringValue == "after");
			Test.Assert(reader.Next() case .Ok(.EndObject));
			Test.Assert(reader.Next() case .Ok(.EndOfDocument));
			// Nothing to skip at the end
			Test.Assert(reader.SkipValue() case .Ok);
		}
	}

	[Test]
	public static void SkipValue_BeforeTheFirstToken()
	{
		let reader = scope JsonReader("[1, [2, 3]] ");
		Test.Assert(reader.SkipValue() case .Ok);
		Test.Assert(reader.TokenType == .EndArray);
		Test.Assert(reader.Next() case .Ok(.EndOfDocument));
	}

	[Test]
	public static void SkipValue_ChecksWhatItSkips()
	{
		// Every kind of error inside a skipped value is still found (the "fully correct" rule)
		ExpectKind(SkipAll("{\"a\": [1, 2,]}"), .InvalidStructure);
		ExpectKind(SkipAll("{\"a\": [01]}"), .InvalidNumber);
		ExpectKind(SkipAll("{\"a\": \"\\x\"}"), .InvalidEscape);
		ExpectKind(SkipAll("{\"a\": \"\\ud800\"}"), .InvalidSurrogate);
		ExpectKind(SkipAll("{\"a\": \"\xff\"}"), .InvalidUtf8);
		ExpectKind(SkipAll("{\"a\": \"tab\there\"}"), .ControlCharacterInString);
		ExpectKind(SkipAll("{\"a\" 1}"), .InvalidStructure);
		ExpectKind(SkipAll("{\"a\": tru}"), .InvalidLiteral);
		ExpectKind(SkipAll("{\"a\": [1, 2"), .UnexpectedEndOfInput);
		ExpectKind(SkipAll("{\"a\": {\"b\": 1]}"), .InvalidStructure);
		var deep = JsonReadConfig();
		deep.MaxDepth = 3;
		ExpectKind(SkipAll("[[[[1]]]]", deep), .ResourceLimitExceeded);
	}

	static Result<void, JsonParseError> SkipAll(StringView text, JsonReadConfig config = .())
	{
		for (int chunk in int[](0, 1))
		{
			let reader = Open(text, chunk, config);
			defer delete reader;
			let result = reader.SkipValue();
			if (result case .Err)
				return result;
		}
		return .Ok;
	}

	[Test]
	public static void ReadRaw_SourceText()
	{
		let text = "{\"s\": \"a\\\"b\\u00e9\", \"n\": -1.50e+3, \"o\": { \"x\" : [ 1 , 2 ] }, \"t\": true}";
		for (int chunk in int[](0, 1, 5))
		{
			let reader = Open(text, chunk);
			defer delete reader;
			Test.Assert(reader.Next() case .Ok(.StartObject));
			Test.Assert(reader.Next() case .Ok(.PropertyName));
			// At a name: the member's value
			Test.Assert(reader.ReadRaw() case .Ok(let s) && s == "\"a\\\"b\\u00e9\"");
			Test.Assert(reader.Next() case .Ok(.PropertyName));
			Test.Assert(reader.Next() case .Ok(.Number));
			Test.Assert(reader.ReadRaw() case .Ok(let n) && n == "-1.50e+3");
			Test.Assert(reader.Next() case .Ok(.PropertyName));
			Test.Assert(reader.Next() case .Ok(.StartObject));
			// A container through a stream's refills: kept whole in the buffer
			Test.Assert(reader.ReadRaw() case .Ok(let o) && o == "{ \"x\" : [ 1 , 2 ] }");
			Test.Assert(reader.TokenType == .EndObject);
			Test.Assert(reader.Next() case .Ok(.PropertyName));
			Test.Assert(reader.ReadRaw() case .Ok(let t) && t == "true");
			Test.Assert(reader.Next() case .Ok(.EndObject));
		}
	}

	[Test]
	public static void ReadRaw_StreamBoundedByMaxTokenBytes()
	{
		let text = "[{\"a\": \"0123456789012345678901234567890123456789\"}]";
		var config = JsonReadConfig();
		config.MaxTokenBytes = 32;
		let reader = Open(text, 4, config);
		defer delete reader;
		Test.Assert(reader.Next() case .Ok(.StartArray));
		Test.Assert(reader.Next() case .Ok(.StartObject));
		ExpectKind(reader.ReadRaw(), .ResourceLimitExceeded);
	}

	[Test]
	public static void ReadRaw_ChecksWhatItReads()
	{
		let reader = scope JsonReader("[{\"a\": [1 2]}]");
		Test.Assert(reader.Next() case .Ok(.StartArray));
		Test.Assert(reader.Next() case .Ok(.StartObject));
		ExpectKind(reader.ReadRaw(), .InvalidStructure);
	}

	[Test]
	public static void Find_Paths()
	{
		let text = """
			{"store": {"book": [{"title": "A", "price": 8.95}, {"title": "B", "price": 12.99}], "a/b": 1, "m~n": 2, "": 3},
			 "after": true}
			""";
		for (int chunk in int[](0, 1, 7))
		{
			let reader = Open(text, chunk);
			defer delete reader;
			Test.Assert(reader.Find("/store/book/1/title") case .Ok(true));
			Test.Assert(reader.TokenType == .String && reader.StringValue == "B");
			// From there on: the next Find is relative to the current value (the string: not a container)
			Test.Assert(reader.Find("/x") case .Ok(false));
			Test.Assert(reader.TokenType == .String);
			// Going on with Next after it
			Test.Assert(reader.Next() case .Ok(.PropertyName) && reader.StringValue == "price");
		}
		for (int chunk in int[](0, 3))
		{
			let reader = Open(text, chunk);
			defer delete reader;
			Test.Assert(reader.Find("/store/a~1b") case .Ok(true) && reader.RawValue == "1");
		}
		{
			let reader = scope JsonReader(text);
			Test.Assert(reader.Find("/store/m~0n") case .Ok(true) && reader.RawValue == "2");
		}
		{
			let reader = scope JsonReader(text);
			Test.Assert(reader.Find("/store/") case .Ok(true) && reader.RawValue == "3");
		}
		{
			// The whole document
			let reader = scope JsonReader(text);
			Test.Assert(reader.Find("") case .Ok(true) && reader.TokenType == .StartObject);
		}
	}

	[Test]
	public static void Find_NotFound()
	{
		let text = "{\"a\": [10, 20], \"b\": {\"c\": 1}, \"z\": 0}";
		{
			// A missing member: the reader is at the end of its object
			let reader = scope JsonReader(text);
			Test.Assert(reader.Find("/b/x") case .Ok(false));
			Test.Assert(reader.TokenType == .EndObject && reader.Depth == 1);
			Test.Assert(reader.Next() case .Ok(.PropertyName) && reader.StringValue == "z");
		}
		{
			// Past the end of an array
			let reader = scope JsonReader(text);
			Test.Assert(reader.Find("/a/2") case .Ok(false));
			Test.Assert(reader.TokenType == .EndArray);
		}
		{
			// `-` and indexes that are not canonical find nothing (the array is skipped)
			let reader = scope JsonReader(text);
			Test.Assert(reader.Find("/a/-") case .Ok(false));
			Test.Assert(reader.TokenType == .EndArray);
			let again = scope JsonReader(text);
			Test.Assert(again.Find("/a/01") case .Ok(false));
		}
		{
			// Through a scalar
			let reader = scope JsonReader(text);
			Test.Assert(reader.Find("/a/0/x") case .Ok(false));
			Test.Assert(reader.TokenType == .Number && reader.RawValue == "10");
		}
		{
			// An array index into an object is a member name
			let reader = scope JsonReader("{\"0\": \"zero\"}");
			Test.Assert(reader.Find("/0") case .Ok(true) && reader.StringValue == "zero");
		}
	}

	[Test]
	public static void Find_FirstOfRepeatedNames()
	{
		// Forward only: the first member of a repeated name (JsonNode lookups find the last)
		let reader = scope JsonReader("{\"k\": 1, \"k\": 2}");
		Test.Assert(reader.Find("/k") case .Ok(true) && reader.RawValue == "1");
	}

	[Test]
	public static void Find_ChecksWhatItSkips()
	{
		// The members before the one found are checked
		let reader = scope JsonReader("{\"a\": [1, 2,], \"b\": 3}");
		ExpectKind(reader.Find("/b"), .InvalidStructure);
		let escaped = scope JsonReader("{\"a\": \"\\q\", \"b\": 3}");
		ExpectKind(escaped.Find("/b"), .InvalidEscape);
	}

	[Test]
	public static void Find_ThenBind()
	{
		// A [JsonObject] type read where Find stopped, then the reader goes on
		let text = "{\"meta\": {\"n\": 1}, \"servers\": [{\"Host\": \"a\", \"Port\": 1}, {\"Host\": \"b\", \"Port\": 2}], \"tail\": 0}";
		for (int chunk in int[](0, 2))
		{
			let reader = Open(text, chunk);
			defer delete reader;
			Test.Assert(reader.Find("/servers/1") case .Ok(true));
			let server = scope TestServer();
			Test.Assert(server.JsonRead(reader) case .Ok);
			Test.Assert(server.Host == "b" && server.Port == 2);
			Test.Assert(reader.Next() case .Ok(.EndArray));
			Test.Assert(reader.Next() case .Ok(.PropertyName) && reader.StringValue == "tail");
		}
	}
}
