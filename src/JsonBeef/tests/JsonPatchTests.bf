using System;
using JsonBeef;

namespace JsonBeef.Tests;

/// JSON Patch (RFC 6902, its Appendix A), Merge Patch (RFC 7396, its Appendix A), and what they rest
/// on: JsonNode.ValueEquals and SetValue.
static class JsonPatchTests
{
	static JsonDocument Doc(StringView text, JsonDocument doc, JsonReadConfig config = .())
	{
		if (doc.Read(text, config) case .Err(let error))
			Test.FatalError(scope $"`{text}` was rejected: {error.mLine}:{error.mColumn}: {error.mMessage}");
		return doc;
	}

	static String Compact(JsonDocument doc, String output)
	{
		Test.Assert(doc.Write(output, JsonWriteOptions()) case .Ok);
		return output;
	}

	/// Applies `patch` to `text`; the result must be `expected` (compact, member order included).
	static void Patched(StringView text, StringView patch, StringView expected)
	{
		let doc = Doc(text, scope .());
		let operations = Doc(patch, scope .());
		if (JsonPatch.Apply(doc, operations.Root) case .Err(let error))
			Test.FatalError(scope $"`{patch}` on `{text}`: {error}");
		let written = Compact(doc, scope .());
		Test.Assert(written == expected, scope $"`{patch}` on `{text}` gave `{written}`");
	}

	/// Applies `patch` to `text`: it must fail with `kind`, and leave the document as it was.
	static void Fails(StringView text, StringView patch, JsonPatchErrorKind kind)
	{
		let doc = Doc(text, scope .());
		let before = Compact(doc, scope .());
		let operations = Doc(patch, scope .());
		switch (JsonPatch.Apply(doc, operations.Root))
		{
		case .Ok:
			Test.FatalError(scope $"`{patch}` on `{text}` applied");
		case .Err(let error):
			Test.Assert(error.mKind == kind, scope $"`{patch}` on `{text}`: {error}");
		}
		Test.Assert(Compact(doc, scope .()) == before);
	}

	[Test]
	public static void Rfc6902_AppendixA()
	{
		// A.1 to A.16, as in the RFC
		Patched("{\"foo\": \"bar\"}", "[{\"op\": \"add\", \"path\": \"/baz\", \"value\": \"qux\"}]", "{\"foo\":\"bar\",\"baz\":\"qux\"}");
		Patched("{\"foo\": [\"bar\", \"baz\"]}", "[{\"op\": \"add\", \"path\": \"/foo/1\", \"value\": \"qux\"}]", "{\"foo\":[\"bar\",\"qux\",\"baz\"]}");
		Patched("{\"baz\": \"qux\", \"foo\": \"bar\"}", "[{\"op\": \"remove\", \"path\": \"/baz\"}]", "{\"foo\":\"bar\"}");
		Patched("{\"foo\": [\"bar\", \"qux\", \"baz\"]}", "[{\"op\": \"remove\", \"path\": \"/foo/1\"}]", "{\"foo\":[\"bar\",\"baz\"]}");
		Patched("{\"baz\": \"qux\", \"foo\": \"bar\"}", "[{\"op\": \"replace\", \"path\": \"/baz\", \"value\": \"boo\"}]", "{\"baz\":\"boo\",\"foo\":\"bar\"}");
		Patched("{\"foo\": {\"bar\": \"baz\", \"waldo\": \"fred\"}, \"qux\": {\"corge\": \"grault\"}}",
			"[{\"op\": \"move\", \"from\": \"/foo/waldo\", \"path\": \"/qux/thud\"}]",
			"{\"foo\":{\"bar\":\"baz\"},\"qux\":{\"corge\":\"grault\",\"thud\":\"fred\"}}");
		Patched("{\"foo\": [\"all\", \"grass\", \"cows\", \"eat\"]}", "[{\"op\": \"move\", \"from\": \"/foo/1\", \"path\": \"/foo/3\"}]",
			"{\"foo\":[\"all\",\"cows\",\"eat\",\"grass\"]}");
		Patched("{\"baz\": \"qux\", \"foo\": [\"a\", 2, \"c\"]}",
			"[{\"op\": \"test\", \"path\": \"/baz\", \"value\": \"qux\"}, {\"op\": \"test\", \"path\": \"/foo/1\", \"value\": 2}]",
			"{\"baz\":\"qux\",\"foo\":[\"a\",2,\"c\"]}");
		Fails("{\"baz\": \"qux\"}", "[{\"op\": \"test\", \"path\": \"/baz\", \"value\": \"bar\"}]", .TestFailed);
		Patched("{\"foo\": \"bar\"}", "[{\"op\": \"add\", \"path\": \"/child\", \"value\": {\"grandchild\": {}}}]", "{\"foo\":\"bar\",\"child\":{\"grandchild\":{}}}");
		Patched("{\"foo\": \"bar\"}", "[{\"op\": \"add\", \"path\": \"/baz\", \"value\": \"qux\", \"xyz\": 123}]", "{\"foo\":\"bar\",\"baz\":\"qux\"}");
		Fails("{\"foo\": \"bar\"}", "[{\"op\": \"add\", \"path\": \"/baz/bat\", \"value\": \"qux\"}]", .NotFound);
		Fails("{\"foo\": \"bar\"}", "[{\"op\": \"add\", \"path\": \"/baz\", \"value\": \"qux\", \"op\": \"remove\"}]", .InvalidOperation);
		Patched("{\"/\": 9, \"~1\": 10}", "[{\"op\": \"test\", \"path\": \"/~01\", \"value\": 10}]", "{\"/\":9,\"~1\":10}");
		Fails("{\"/\": 9, \"~1\": 10}", "[{\"op\": \"test\", \"path\": \"/~01\", \"value\": \"10\"}]", .TestFailed);
		Patched("{\"foo\": [\"bar\"]}", "[{\"op\": \"add\", \"path\": \"/foo/-\", \"value\": [\"abc\", \"def\"]}]", "{\"foo\":[\"bar\",[\"abc\",\"def\"]]}");
	}

	[Test]
	public static void Operations()
	{
		// The whole document
		Patched("{\"a\": 1}", "[{\"op\": \"add\", \"path\": \"\", \"value\": [1]}]", "[1]");
		Patched("{\"a\": 1}", "[{\"op\": \"replace\", \"path\": \"\", \"value\": \"x\"}]", "\"x\"");
		Patched("{\"a\": 1}", "[{\"op\": \"test\", \"path\": \"\", \"value\": {\"a\": 1.0}}]", "{\"a\":1}");
		Fails("{\"a\": 1}", "[{\"op\": \"remove\", \"path\": \"\"}]", .RemoveRoot);
		// add replaces a member in place; the empty name
		Patched("{\"a\": 1, \"b\": 2}", "[{\"op\": \"add\", \"path\": \"/a\", \"value\": 3}]", "{\"a\":3,\"b\":2}");
		Patched("{}", "[{\"op\": \"add\", \"path\": \"/\", \"value\": 1}]", "{\"\":1}");
		// Arrays: the end, past it, not indexes
		Patched("[1, 2]", "[{\"op\": \"add\", \"path\": \"/2\", \"value\": 3}]", "[1,2,3]");
		Fails("[1, 2]", "[{\"op\": \"add\", \"path\": \"/3\", \"value\": 3}]", .NotFound);
		Fails("[1, 2]", "[{\"op\": \"add\", \"path\": \"/01\", \"value\": 3}]", .InvalidIndex);
		Fails("[1, 2]", "[{\"op\": \"remove\", \"path\": \"/-\"}]", .NotFound);
		Fails("[1, 2]", "[{\"op\": \"replace\", \"path\": \"/1e0\", \"value\": 3}]", .InvalidIndex);
		Fails("{\"a\": 1}", "[{\"op\": \"add\", \"path\": \"/a/b\", \"value\": 3}]", .NotAContainer);
		// move and copy
		Patched("{\"a\": {\"b\": [1]}}", "[{\"op\": \"move\", \"from\": \"/a/b\", \"path\": \"/a\"}]", "{\"a\":[1]}");
		Patched("{\"a\": 1}", "[{\"op\": \"move\", \"from\": \"/a\", \"path\": \"/a\"}]", "{\"a\":1}");
		Fails("{\"a\": {\"b\": 1}}", "[{\"op\": \"move\", \"from\": \"/a\", \"path\": \"/a/c\"}]", .MoveIntoItself);
		Patched("{\"a\": {\"b\": 1}}", "[{\"op\": \"copy\", \"from\": \"/a\", \"path\": \"/a/c\"}]", "{\"a\":{\"b\":1,\"c\":{\"b\":1}}}");
		Patched("{\"ab\": 1, \"a\": {}}", "[{\"op\": \"move\", \"from\": \"/a\", \"path\": \"/ab\"}]", "{\"ab\":{}}");
		// Operations that are not
		Fails("{}", "{\"op\": \"add\", \"path\": \"/a\", \"value\": 1}", .InvalidOperation);
		Fails("{}", "[1]", .InvalidOperation);
		Fails("{}", "[{\"op\": \"spam\", \"path\": \"/a\"}]", .InvalidOperation);
		Fails("{}", "[{\"op\": \"add\", \"path\": null, \"value\": 1}]", .InvalidOperation);
		Fails("{}", "[{\"op\": \"add\", \"path\": \"/a\"}]", .InvalidOperation);
		Fails("{\"a\": 1}", "[{\"op\": \"copy\", \"path\": \"/b\"}]", .InvalidOperation);
		Fails("{}", "[{\"op\": \"add\", \"path\": \"a\", \"value\": 1}]", .InvalidPointer);
		Fails("{}", "[{\"op\": \"add\", \"path\": \"/~2\", \"value\": 1}]", .InvalidPointer);
		// An empty document has a value only after add at ""
		let empty = scope JsonDocument();
		Test.Assert(JsonPatch.Apply(empty, Doc("[{\"op\": \"add\", \"path\": \"\", \"value\": {\"x\": 1}}]", scope .()).Root) case .Ok);
		Test.Assert(Compact(empty, scope .()) == "{\"x\":1}");
	}

	[Test]
	public static void AllOrNothing()
	{
		let doc = Doc("{\"a\": [1, 2, {\"b\": \"c\"}], \"big\": {\"m0\": 0, \"m1\": 1, \"m2\": 2, \"m3\": 3, \"m4\": 4, \"m5\": 5, \"m6\": 6, \"m7\": 7, \"m8\": 8, \"m9\": 9, \"m10\": 10, \"m11\": 11, \"m12\": 12, \"m13\": 13, \"m14\": 14, \"m15\": 15, \"m16\": 16}}", scope .());
		let before = Compact(doc, scope .());
		let element = doc.Root["a"][2];
		Test.Assert(doc.Root["big"]["m16"].GetInt64() == 16);
		// Changes everywhere, a lookup that builds the member index, then a failure
		let patch = Doc("""
			[{"op": "remove", "path": "/a/0"},
			 {"op": "add", "path": "/a/-", "value": {"new": [true]}},
			 {"op": "replace", "path": "/a/1/b", "value": "d"},
			 {"op": "move", "from": "/big/m3", "path": "/big/m99"},
			 {"op": "test", "path": "/big/m99", "value": 3},
			 {"op": "copy", "from": "/a", "path": "/copy"},
			 {"op": "test", "path": "/copy/0", "value": 3}]
			""", scope .());
		switch (JsonPatch.Apply(doc, patch.Root))
		{
		case .Ok:
			Test.FatalError("applied");
		case .Err(let error):
			Test.Assert(error.mKind == .TestFailed && error.mOperation == 6);
		}
		Test.Assert(Compact(doc, scope .()) == before);
		// Handles from before still work, lookups too
		Test.Assert(element.IsValid && element["b"].GetString() == "c");
		Test.Assert(doc.Root["big"]["m3"].GetInt64() == 3 && !doc.Root["big"]["m99"].IsValid);
		Test.Assert(!doc.Root["copy"].IsValid);
		// And it can be patched afterwards
		Patched(before, "[{\"op\": \"remove\", \"path\": \"/big\"}]", "{\"a\":[1,2,{\"b\":\"c\"}]}");
	}

	[Test]
	public static void ValueEquals()
	{
		let a = scope JsonDocument();
		let b = scope JsonDocument();
		void Check(StringView left, StringView right, bool equal)
		{
			Doc(left, a);
			Doc(right, b);
			Test.Assert(a.Root.ValueEquals(b.Root) == equal, scope $"`{left}` and `{right}`");
			Test.Assert(b.Root.ValueEquals(a.Root) == equal, scope $"`{right}` and `{left}`");
		}
		Check("1", "1.0", true);
		Check("1", "10e-1", true);
		Check("0", "-0", true);
		Check("0", "-0.0e5", true);
		Check("0.5", "5e-1", true);
		Check("100", "1E2", true);
		Check("1", "2", false);
		Check("1", "-1", false);
		Check("0.1", "0.10", true);
		Check("10000000000000000000000", "1e22", true);
		// A float in a double's range is held as the double: rounded
		Check("12345678901234567890123", "1.2345678901234567890123e22", false);
		Check("1.2345678901234567890123e22", "1.2345678901234567e22", true);
		Check("12345678901234567890123", "12345678901234567890124", false);
		Check("1e400", "10e399", true);
		Check("1e400", "1e401", false);
		// Doubles by their exact value: 2^64, 2^-1074, 0.1
		Check("18446744073709551616", "1.8446744073709551616e19", true);
		Check("18446744073709551615", "1.8446744073709551615e19", false);
		Check("18446744073709552000", "1.8446744073709551616e19", false);
		Check("5e-324", "4.9406564584124654e-324", true);
		Check("0.1", "0.1000000000000000055511151231257827021181583404541015625", true);
		Check("0.1", "0.1000000000000000055511151231257827021181583404541015626", true);
		Check("2.5", "2", false);
		Check("1e-300", "1e400", false);
		Check("12345678912345678912", "12345678912345678912.0", false);
		Check("4611686018427387904", "4.611686018427387904e18", true);
		Check("9223372036854775807", "9223372036854775808", false);
		Check("\"a\\u00e9\"", "\"a\u{E9}\"", true);
		Check("\"1\"", "1", false);
		Check("null", "false", false);
		Check("true", "true", true);
		Check("[1, [2]]", "[1, [2]]", true);
		Check("[1, 2]", "[2, 1]", false);
		Check("[1]", "[1, 1]", false);
		Check("{\"a\": 1, \"b\": [true]}", "{\"b\": [true], \"a\": 1.0}", true);
		Check("{\"a\": 1}", "{\"a\": 1, \"b\": 2}", false);
		Check("{\"a\": 1}", "{\"b\": 1}", false);
		Check("{}", "[]", false);
		// A name used twice counts once, with its last value
		Check("{\"a\": 1, \"a\": 2}", "{\"a\": 2}", true);
		Check("{\"a\": 1, \"a\": 2}", "{\"a\": 1}", false);
		// Nested deeper than a recursion would like
		let deep = scope String();
		for (int i < 5000)
			deep.Append('[');
		for (int i < 5000)
			deep.Append(']');
		var config = JsonReadConfig();
		config.MaxDepth = 10000;
		Doc(deep, a, config);
		Doc(deep, b, config);
		Test.Assert(a.Root.ValueEquals(b.Root));
		Test.Assert(!a.Root.ValueEquals(default));
	}

	[Test]
	public static void SetValue()
	{
		let doc = Doc("{\"a\": {\"b\": [1, \"x\", {\"c\": null}]}, \"d\": 2}", scope .());
		let other = Doc("{\"long\": \"a string with \\\"escapes\\\"\", \"n\": 1e400, \"big\": 123456789012345678901234567890}", scope .());
		// From another document (its text copied)
		doc.Root["d"].SetValue(other.Root);
		other.Clear();
		Test.Assert(Compact(doc, scope .()) == "{\"a\":{\"b\":[1,\"x\",{\"c\":null}]},\"d\":{\"long\":\"a string with \\\"escapes\\\"\",\"n\":1e400,\"big\":123456789012345678901234567890}}");
		// From under itself
		doc.Root["a"].SetValue(doc.Root["a"]["b"][2]);
		Test.Assert(Compact(doc, scope .()) == "{\"a\":{\"c\":null},\"d\":{\"long\":\"a string with \\\"escapes\\\"\",\"n\":1e400,\"big\":123456789012345678901234567890}}");
		// Its parent into it
		let tree = Doc("{\"x\": {\"y\": 1}}", scope .());
		tree.Root["x"]["y"].SetValue(tree.Root);
		Test.Assert(Compact(tree, scope .()) == "{\"x\":{\"y\":{\"x\":{\"y\":1}}}}");
		Test.Assert(tree.Root.At("/x/y/x/y").GetInt64() == 1);
		// Lookups after a copy into a large object
		let large = scope String("{");
		for (int i < 40)
			large.AppendF("{}\"k{}\": {}", i == 0 ? "" : ", ", i, i);
		large.Append('}');
		let source = Doc(large, scope .());
		let target = Doc("{\"t\": 0}", scope .());
		target.Root["t"].SetValue(source.Root);
		Test.Assert(target.Root["t"]["k39"].GetInt64() == 39 && target.Root["t"].Count == 40);
		target.Root["t"]["k5"].Remove();
		Test.Assert(!target.Root["t"]["k5"].IsValid && target.Root["t"]["k6"].GetInt64() == 6);
	}

	[Test]
	public static void PreserveStyle()
	{
		var config = JsonReadConfig.Jsonc;
		config.MetadataMode = .PreserveStyle;
		let doc = Doc("{\n  // the port\n  \"port\": 8080,\n  \"hosts\": [\"a\", \"b\"], /* kept */\n  \"old\": true\n}\n", scope .(), config);
		let patch = Doc("""
			[{"op": "replace", "path": "/port", "value": 8443},
			 {"op": "add", "path": "/hosts/1", "value": "c"},
			 {"op": "remove", "path": "/old"}]
			""", scope .());
		Test.Assert(JsonPatch.Apply(doc, patch.Root) case .Ok);
		let written = doc.Write(.. scope .());
		Test.Assert(written == "{\n  // the port\n  \"port\": 8443,\n  \"hosts\": [\"a\", \"c\", \"b\"] /* kept */\n}\n", scope $"wrote `{written}`");
		// A failed patch leaves the source as it was written
		let unchanged = Doc("{\n  \"a\": 1, // one\n  \"b\": 2\n}", scope .(), config);
		Test.Assert(JsonPatch.Apply(unchanged, Doc("[{\"op\": \"replace\", \"path\": \"/a\", \"value\": 5}, {\"op\": \"remove\", \"path\": \"/c\"}]", scope .()).Root) case .Err);
		Test.Assert(unchanged.Write(.. scope .()) == "{\n  \"a\": 1, // one\n  \"b\": 2\n}");
	}

	/// Merges `patch` into `text`: the result must be `expected` (compact).
	static void Merged(StringView text, StringView patch, StringView expected)
	{
		let doc = Doc(text, scope .());
		JsonPatch.Merge(doc, Doc(patch, scope .()).Root);
		let written = Compact(doc, scope .());
		Test.Assert(written == expected, scope $"`{patch}` merged into `{text}` gave `{written}`");
	}

	[Test]
	public static void Rfc7396_AppendixA()
	{
		Merged("{\"a\":\"b\"}", "{\"a\":\"c\"}", "{\"a\":\"c\"}");
		Merged("{\"a\":\"b\"}", "{\"b\":\"c\"}", "{\"a\":\"b\",\"b\":\"c\"}");
		Merged("{\"a\":\"b\"}", "{\"a\":null}", "{}");
		Merged("{\"a\":\"b\",\"b\":\"c\"}", "{\"a\":null}", "{\"b\":\"c\"}");
		Merged("{\"a\":[\"b\"]}", "{\"a\":\"c\"}", "{\"a\":\"c\"}");
		Merged("{\"a\":\"c\"}", "{\"a\":[\"b\"]}", "{\"a\":[\"b\"]}");
		Merged("{\"a\":{\"b\":\"c\"}}", "{\"a\":{\"b\":\"d\",\"c\":null}}", "{\"a\":{\"b\":\"d\"}}");
		Merged("{\"a\":[{\"b\":\"c\"}]}", "{\"a\":[1]}", "{\"a\":[1]}");
		Merged("[\"a\",\"b\"]", "[\"c\",\"d\"]", "[\"c\",\"d\"]");
		Merged("{\"a\":\"b\"}", "[\"c\"]", "[\"c\"]");
		Merged("{\"a\":\"foo\"}", "null", "null");
		Merged("{\"a\":\"foo\"}", "\"bar\"", "\"bar\"");
		Merged("{\"e\":null}", "{\"a\":1}", "{\"e\":null,\"a\":1}");
		Merged("[1,2]", "{\"a\":\"b\",\"c\":null}", "{\"a\":\"b\"}");
		Merged("{}", "{\"a\":{\"bb\":{\"ccc\":null}}}", "{\"a\":{\"bb\":{}}}");
		// §3's example
		Merged("""
			{"title": "Goodbye!", "author": {"givenName": "John", "familyName": "Doe"}, "tags": ["example", "sample"], "content": "This will be unchanged"}
			""", """
			{"title": "Hello!", "phoneNumber": "+01-123-456-7890", "author": {"familyName": null}, "tags": ["example"]}
			""",
			"{\"title\":\"Hello!\",\"author\":{\"givenName\":\"John\"},\"tags\":[\"example\"],\"content\":\"This will be unchanged\",\"phoneNumber\":\"+01-123-456-7890\"}");
	}

	[Test]
	public static void Merge()
	{
		// Members of the same name in the patch apply in order
		Merged("{}", "{\"a\": {\"x\": 1}, \"a\": {\"x\": 2, \"y\": 3}}", "{\"a\":{\"x\":2,\"y\":3}}");
		Merged("{\"a\": {\"b\": 1}}", "{\"a\": {\"c\": 1}, \"a\": null}", "{}");
		Merged("{}", "{\"a\": null, \"a\": [1]}", "{\"a\":[1]}");
		// An empty document's value is null
		let empty = scope JsonDocument();
		JsonPatch.Merge(empty, Doc("{\"a\": {\"b\": null, \"c\": 1}}", scope .()).Root);
		Test.Assert(Compact(empty, scope .()) == "{\"a\":{\"c\":1}}");
		// Into a value: name and place stay
		let doc = Doc("{\"x\": 1, \"y\": {\"z\": 2}, \"w\": 3}", scope .());
		JsonPatch.Merge(doc.Root["y"], Doc("{\"z\": null, \"n\": [true]}", scope .()).Root);
		Test.Assert(Compact(doc, scope .()) == "{\"x\":1,\"y\":{\"n\":[true]},\"w\":3}");
		// Deep patches without recursion
		let deep = scope String();
		for (int i < 3000)
			deep.Append("{\"a\":");
		deep.Append('1');
		for (int i < 3000)
			deep.Append('}');
		var config = JsonReadConfig();
		config.MaxDepth = 10000;
		let target = scope JsonDocument();
		JsonPatch.Merge(target, Doc(deep, scope .(), config).Root);
		Test.Assert(target.Root.ValueEquals(Doc(deep, scope .(), config).Root));
	}
}
