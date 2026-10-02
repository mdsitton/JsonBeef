using System;
using System.Collections;
using static JsonBeef.Tests.JsonTestUtil;

namespace JsonBeef.Tests;

/// Collect-errors (JsonReadConfig.CollectErrors), positions (JsonMetadataMode.Positions), the
/// document limits and JsonDiagnostic.
static class JsonCollectTests
{
	static JsonReadConfig Collect()
	{
		var config = JsonReadConfig();
		config.CollectErrors = true;
		return config;
	}

	/// The errors of a collect-errors read as `line:column Kind` lines, and the document read as compact
	/// JSON; from memory and through 1-byte stream reads, which must agree.
	static void Collected(StringView text, String errors, String written)
	{
		let doc = scope JsonDocument();
		doc.Read(text, Collect()).IgnoreError();
		for (let error in doc.Errors)
			errors.AppendF("{}:{} {}\n", error.mLine, error.mColumn, error.mKind);
		if (!doc.IsEmpty)
			Test.Assert(doc.Write(written) case .Ok);

		var config = Collect();
		config.StreamBufferBytes = 16;
		let stream = scope JsonTestStream(text, 1);
		let streamed = scope JsonDocument();
		streamed.Read(stream, config).IgnoreError();
		let streamErrors = scope String();
		for (let error in streamed.Errors)
			streamErrors.AppendF("{}:{} {}\n", error.mLine, error.mColumn, error.mKind);
		let streamWritten = scope String();
		if (!streamed.IsEmpty)
			Test.Assert(streamed.Write(streamWritten) case .Ok);
		Test.Assert(streamErrors == errors && streamWritten == written, scope $"`{text}`: the stream read differs");
	}

	[Test]
	public static void Collect_MissingCommasAndColons()
	{
		let errors = scope String();
		let written = scope String();
		Collected("{\"a\": 1 \"b\" 2, \"c\": [1 2, 3]}", errors, written);
		Test.Assert(errors == "1:9 InvalidStructure\n1:13 InvalidStructure\n1:24 InvalidStructure\n", errors);
		Test.Assert(written == "{\"a\":1,\"b\":2,\"c\":[1,2,3]}", written);
	}

	[Test]
	public static void Collect_BrokenValuesAreDropped()
	{
		let errors = scope String();
		let written = scope String();
		Collected("[1, tru, \"a\\qb\", 0x1F, 2, -, 3]", errors, written);
		Test.Assert(errors == "1:5 InvalidLiteral\n1:12 InvalidEscape\n1:19 InvalidNumber\n1:28 InvalidNumber\n", errors);
		Test.Assert(written == "[1,2,3]", written);
	}

	[Test]
	public static void Collect_BrokenMembersAreDropped()
	{
		let errors = scope String();
		let written = scope String();
		Collected("{\"a\": 1, b: [2], \"c\": nul, \"d\\x\": {\"e\": 5}, \"f\": 6,}", errors, written);
		Test.Assert(errors == "1:10 InvalidStructure\n1:23 InvalidLiteral\n1:30 InvalidEscape\n1:52 InvalidStructure\n", errors);
		Test.Assert(written == "{\"a\":1,\"f\":6}", written);
	}

	[Test]
	public static void Collect_TrailingCommasAndStrayClosers()
	{
		let errors = scope String();
		let written = scope String();
		Collected("[[1, 2,], {\"a\": [3}, 4]", errors, written);
		Test.Assert(errors == "1:8 InvalidStructure\n1:19 InvalidStructure\n", errors);
		Test.Assert(written == "[[1,2],{\"a\":[3]},4]", written);
	}

	[Test]
	public static void Collect_EndOfInputClosesEverything()
	{
		let errors = scope String();
		let written = scope String();
		Collected("{\"a\": [1, {\"b\": \"unterminated", errors, written);
		Test.Assert(errors == "1:30 UnterminatedString\n", errors);
		Test.Assert(written == "{\"a\":[1,{}]}", written);
	}

	[Test]
	public static void Collect_ContentAfterTheValueEndsTheRead()
	{
		let errors = scope String();
		let written = scope String();
		Collected("[1] [2] x", errors, written);
		Test.Assert(errors == "1:5 InvalidStructure\n", errors);
		Test.Assert(written == "[1]", written);
	}

	[Test]
	public static void Collect_ReaderReportsEachErrorOnce()
	{
		let reader = scope JsonReader("[1 2, x]", Collect());
		let trace = scope String();
		int errors = 0;
		while (true)
		{
			switch (reader.Next())
			{
			case .Ok(let token):
				if (token == .EndOfDocument)
					break;
				trace.AppendF("{} ", token);
				continue;
			case .Err:
				errors++;
				Test.Assert(!reader.IsStopped);
				continue;
			}
			break;
		}
		Test.Assert(errors == 2 && trace == "StartArray Number Number EndArray ", trace);
	}

	[Test]
	public static void Collect_FatalErrorsStop()
	{
		var config = Collect();
		config.MaxDepth = 2;
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("[1, x, [[[]]], 2]", config) case .Err(let error) && error.mKind == .InvalidLiteral);
		Test.Assert(doc.Errors.Length == 2 && doc.Errors[1].mKind == .ResourceLimitExceeded);
		// MaxErrors
		config = Collect();
		config.MaxErrors = 3;
		Test.Assert(doc.Read("[x, x, x, x, x, x]", config) case .Err);
		Test.Assert(doc.Errors.Length == 3);
		// UTF-16 input stops at once
		Test.Assert(doc.Read("\xFF\xFE[\0]\0", Collect()) case .Err(let encoding) && encoding.mKind == .UnsupportedEncoding);
	}

	[Test]
	public static void Collect_ValidInputIsUnchanged()
	{
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("{\"a\": [1, 2.5, \"x\"]}", Collect()) case .Ok);
		Test.Assert(doc.Errors.IsEmpty && doc.Write(.. scope .()) == "{\"a\":[1,2.5,\"x\"]}");
	}

	[Test]
	public static void Collect_ErrorsOwnTheirText()
	{
		let doc = scope JsonDocument();
		doc.Read("[x, y]", Collect()).IgnoreError();
		// Another error on the thread does not change the document's
		scope JsonReader("[").Next().IgnoreError();
		Test.Assert(doc.Errors.Length == 2 && doc.Errors[0].mMessage.Contains("`x`") && doc.Errors[1].mMessage.Contains("`y`"));
		let diagnostic = scope JsonDiagnostic(doc.Errors[1]);
		doc.Clear();
		Test.Assert(diagnostic.mMessage.Contains("`y`") && diagnostic.ToString(.. scope .()) == "1:5: Invalid literal `y` (JSON's literals are `true`, `false` and `null`)");
	}

	// Positions

	static JsonReadConfig Positions()
	{
		var config = JsonReadConfig();
		config.MetadataMode = .Positions;
		config.SourceName = "doc.json";
		return config;
	}

	[Test]
	public static void Positions_ValuesAndNames()
	{
		let text = "{\n  \"name\": \"Ada\",\n  \"list\": [1, {\"é\": true}]\n}";
		for (int stream < 2)
		{
			let doc = scope:: JsonDocument();
			if (stream == 0)
				Test.Assert(doc.Read(text, Positions()) case .Ok);
			else
			{
				var config = Positions();
				config.StreamBufferBytes = 16;
				Test.Assert(doc.Read(scope:: JsonTestStream(text, 3), config) case .Ok);
			}
			Test.Assert(doc.Root.TryGetSourceRange(let root) && root.mLine == 1 && root.mColumn == 1 && root.mLength == text.Length);
			Test.Assert(!doc.Root.TryGetNameRange(?));
			let name = doc.Root["name"];
			Test.Assert(name.TryGetNameRange(let nameRange) && nameRange.mLine == 2 && nameRange.mColumn == 3 && nameRange.mLength == 6);
			Test.Assert(name.TryGetSourceRange(let value) && value.mLine == 2 && value.mColumn == 11 && value.mLength == 5 && value.mSource == "doc.json");
			let list = doc.Root["list"];
			Test.Assert(list.TryGetSourceRange(let listRange) && listRange.mLine == 3 && listRange.mColumn == 11 && listRange.mLength == 17);
			let inner = list[1]["é"];
			Test.Assert(inner.TryGetNameRange(let innerName) && innerName.mLine == 3 && innerName.mColumn == 16 && innerName.mOffset == 34);
			Test.Assert(inner.TryGetSourceRange(let innerValue) && innerValue.mColumn == 21 && innerValue.ToString(.. scope .()) == "doc.json:3:21");
		}
	}

	[Test]
	public static void Positions_OffByDefault()
	{
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("[1]") case .Ok);
		Test.Assert(!doc.Root.TryGetSourceRange(?) && !doc.Root[0].TryGetSourceRange(?));
	}

	[Test]
	public static void Positions_CrLfAndBom()
	{
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("\xEF\xBB\xBF[1,\r\n 2,\r 3]", Positions()) case .Ok);
		Test.Assert(doc.Root.TryGetSourceRange(let root) && root.mLine == 1 && root.mColumn == 1 && root.mOffset == 3);
		Test.Assert(doc.Root[1].TryGetSourceRange(let two) && two.mLine == 2 && two.mColumn == 2);
		Test.Assert(doc.Root[2].TryGetSourceRange(let three) && three.mLine == 3 && three.mColumn == 2);
	}

	// Document limits

	[Test]
	public static void Limits_MaxNodes()
	{
		var config = JsonReadConfig();
		config.MaxNodes = 4;
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("[1, 2, 3]", config) case .Ok);
		Test.Assert(doc.Read("[1, 2, 3, 4]", config) case .Err(let error) && error.mKind == .ResourceLimitExceeded && error.mColumn == 11);
		Test.Assert(doc.Read(scope JsonTestStream("[[], [], [], []]", 1), config) case .Err(let streamError) && streamError.mColumn == 14);
	}

	[Test]
	public static void Limits_MaxMembers()
	{
		var config = JsonReadConfig();
		config.MaxMembers = 2;
		let doc = scope JsonDocument();
		Test.Assert(doc.Read("{\"a\": {\"x\": 1, \"y\": 2}, \"b\": 2}", config) case .Ok);
		Test.Assert(doc.Read("{\"a\": 1, \"b\": 2, \"c\": 3}", config) case .Err(let error) && error.mKind == .ResourceLimitExceeded && error.mColumn == 18);
	}

	[Test]
	public static void Limits_UntrustedPreset()
	{
		let doc = scope JsonDocument();
		let config = JsonReadConfig.Untrusted;
		Test.Assert(doc.Read("{\"a\": 1, \"a\": 2}", config) case .Err(let error) && error.mKind == .DuplicateName);
		let deep = scope String();
		Repeat("[", 129, deep);
		Repeat("]", 129, deep);
		Test.Assert(doc.Read(deep, config) case .Err(let depth) && depth.mKind == .ResourceLimitExceeded);
	}

	[Test]
	public static void Stream_SweepReadSizes()
	{
		let text = "{\"s\": \"a\\u00e9\\uD834\\uDD1E\\n\u{4E2D}\u{1F600}\", \"n\": [-0.000123e-45, 18446744073709551616, 1e400, 7],\r\n \"t\": [true, false, null, {}, []], \"long\": \"0123456789012345678901234567890123456789\"}";
		let expected = scope String();
		Test.Assert(Read(text, expected) case .Ok);
		for (int chunk = 1; chunk <= 31; chunk++)
		{
			var config = JsonReadConfig();
			config.StreamBufferBytes = 15 + chunk;
			let reader = scope:: JsonReader();
			reader.Reset(scope:: JsonTestStream(text, chunk), config);
			let trace = scope:: String();
			Test.Assert(Trace(reader, trace) case .Ok && trace == expected, scope $"{chunk}-byte reads");
		}
	}
}
