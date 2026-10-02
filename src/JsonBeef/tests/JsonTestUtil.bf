using System;
using System.Collections;
using System.IO;

namespace JsonBeef.Tests;

/// A read-only stream over text that hands out at most `chunk` bytes per read, so a reader's refills
/// land everywhere.
class JsonTestStream : Stream
{
	StringView mText;
	int mPosition;
	int mChunk;

	public this(StringView text, int chunk)
	{
		mText = text;
		mChunk = Math.Max(chunk, 1);
	}

	public override int64 Position
	{
		get => mPosition;
		set => mPosition = (int)value;
	}

	public override int64 Length => mText.Length;

	public override bool CanRead => true;

	public override bool CanWrite => false;

	public override Result<int> TryRead(Span<uint8> data)
	{
		int count = Math.Min(Math.Min(data.Length, mChunk), mText.Length - mPosition);
		Internal.MemCpy(data.Ptr, mText.Ptr + mPosition, count);
		mPosition += count;
		return count;
	}

	public override Result<int> TryWrite(Span<uint8> data)
	{
		return .Err;
	}

	public override Result<void> Close()
	{
		return .Ok;
	}
}

/// Helpers that read a text to the end from memory and through 1-byte stream reads, check that both
/// agree, and return a compact trace of the tokens or the error.
static class JsonTestUtil
{
	/// Reads `text` to its end, appending a trace of the tokens: `{ } [ ] name: "s" 1 true false null`,
	/// numbers as written, separated by spaces.
	public static Result<void, JsonParseError> Trace(JsonReader reader, String trace)
	{
		while (true)
		{
			let token = Try!(reader.Next());
			if (!trace.IsEmpty && token != .EndOfDocument)
				trace.Append(' ');
			switch (token)
			{
			case .StartObject: trace.Append('{');
			case .EndObject: trace.Append('}');
			case .StartArray: trace.Append('[');
			case .EndArray: trace.Append(']');
			case .PropertyName: trace.AppendF("{}:", reader.StringValue);
			case .String: trace.AppendF("\"{}\"", reader.StringValue);
			case .Number, .True, .False, .Null: trace.Append(reader.RawValue);
			case .EndOfDocument: return .Ok;
			case .None:
			}
		}
	}

	/// The trace of `text` (memory), checked against the same read through 1-byte stream reads.
	public static Result<void, JsonParseError> Read(StringView text, String trace, JsonReadConfig config = .())
	{
		let reader = scope JsonReader(text, config);
		let result = Trace(reader, trace);
		let streamTrace = scope String();
		let stream = scope JsonTestStream(text, 1);
		var streamConfig = config;
		streamConfig.StreamBufferBytes = 16;
		let streamReader = scope JsonReader();
		streamReader.Reset(stream, streamConfig);
		let streamResult = Trace(streamReader, streamTrace);
		switch (result)
		{
		case .Ok:
			Test.Assert(streamResult case .Ok, scope $"the stream read failed: {text}");
			Test.Assert(streamTrace == trace, scope $"stream trace `{streamTrace}` != `{trace}`");
			return .Ok;
		case .Err(let error):
			// The same first error from a stream (the error's message buffer is per thread: compare
			// fields, the stream's error was made last)
			Test.Assert(streamResult case .Err, scope $"the stream read succeeded: {text}");
			if (streamResult case .Err(let streamError))
			{
				Test.Assert(streamError.mKind == error.mKind && streamError.mLine == error.mLine && streamError.mColumn == error.mColumn &&
					streamError.mOffset == error.mOffset, scope $"stream error differs: {text}");
			}
			// Re-read from memory so the returned error's message is this one's
			let again = scope JsonReader(text, config);
			let againTrace = scope String();
			if (Trace(again, againTrace) case .Err(let againError))
				return .Err(againError);
			return .Err(error);
		}
	}

	/// Asserts that `text` is read with exactly the token trace `expected`.
	public static void Accepts(StringView text, StringView expected, JsonReadConfig config = .())
	{
		let trace = scope String();
		switch (Read(text, trace, config))
		{
		case .Ok:
			Test.Assert(trace == expected, scope $"`{text}`: trace `{trace}`, expected `{expected}`");
		case .Err(let error):
			Test.FatalError(scope $"`{text}` was rejected: {error.mLine}:{error.mColumn}: {error.mKind}: {error.mMessage}");
		}
	}

	/// Asserts that `text` is read to its end (from memory and from a stream).
	public static void Accepts(StringView text, JsonReadConfig config = .())
	{
		let trace = scope String();
		if (Read(text, trace, config) case .Err(let error))
			Test.FatalError(scope $"`{text}` was rejected: {error.mLine}:{error.mColumn}: {error.mKind}: {error.mMessage}");
	}

	/// The decoded text of `text`, a string document.
	public static String StringOf(StringView text, String output)
	{
		let reader = scope JsonReader(text);
		Test.Assert(reader.Next() case .Ok(let token) && token == .String, scope $"`{text}` is not a string");
		output.Append(reader.StringValue);
		Test.Assert(reader.Next() case .Ok(let end) && end == .EndOfDocument);
		// The same through a stream
		let stream = scope JsonTestStream(text, 1);
		let streamReader = scope JsonReader();
		streamReader.Reset(stream);
		Test.Assert(streamReader.Next() case .Ok(let streamToken) && streamToken == .String && streamReader.StringValue == output);
		return output;
	}

	/// Asserts that `text` is rejected with `kind` at `line`:`column` (and `offset` when not -1).
	public static void Rejects(StringView text, JsonErrorKind kind, int line, int column, int offset = -1, JsonReadConfig config = .())
	{
		let trace = scope String();
		switch (Read(text, trace, config))
		{
		case .Ok:
			Test.FatalError(scope $"`{text}` was accepted: {trace}");
		case .Err(let error):
			Test.Assert(error.mKind == kind, scope $"`{text}`: {error.mKind}, expected {kind} ({error.mMessage})");
			Test.Assert(error.mLine == line && error.mColumn == column, scope $"`{text}`: at {error.mLine}:{error.mColumn}, expected {line}:{column}");
			if (offset >= 0)
				Test.Assert(error.mOffset == offset, scope $"`{text}`: offset {error.mOffset}, expected {offset}");
		}
	}

	/// Asserts that `text` is rejected with `kind` (wherever).
	public static void Rejects(StringView text, JsonErrorKind kind, JsonReadConfig config = .())
	{
		let trace = scope String();
		switch (Read(text, trace, config))
		{
		case .Ok:
			Test.FatalError(scope $"`{text}` was accepted: {trace}");
		case .Err(let error):
			Test.Assert(error.mKind == kind, scope $"`{text}`: {error.mKind}, expected {kind} ({error.mMessage})");
		}
	}

	/// The first token of `text`, which must be a number, positioned on it.
	public static void ReadNumber(JsonReader reader, StringView text)
	{
		reader.Reset(text);
		Test.Assert(reader.Next() case .Ok(let token) && token == .Number, scope $"`{text}` is not a number");
	}

	/// Whether the reader's number is the int64 `expected` (NumberKind Integer).
	public static bool IsInt64(JsonReader reader, int64 expected)
	{
		int64 value = 0;
		return reader.NumberKind == .Integer && reader.TryGetInt64(out value) && value == expected;
	}

	/// Whether the reader's number is the uint64 `expected` beyond int64 (NumberKind UInteger).
	public static bool IsUInt64(JsonReader reader, uint64 expected)
	{
		uint64 value = 0;
		return reader.NumberKind == .UInteger && reader.TryGetUInt64(out value) && value == expected;
	}

	/// Whether the reader's number's double is `expected`.
	public static bool IsDouble(JsonReader reader, double expected)
	{
		double value = 0;
		return reader.TryGetDouble(out value) && value == expected;
	}

	/// The IEEE bits of the double of `text` (a number), asserting it is finite.
	public static uint64 DoubleBits(StringView text)
	{
		let reader = scope JsonReader();
		ReadNumber(reader, text);
		Test.Assert(reader.TryGetDouble(let value), scope $"`{text}` is out of range");
		return JsonNumber.ToBits(value);
	}

	/// The text of a double in a layout.
	public static String Format(double value, JsonFloatFormat format, String output)
	{
		JsonNumber.AppendDouble(output, value, format);
		return output;
	}

	/// `count` copies of `text`.
	public static String Repeat(StringView text, int count, String output)
	{
		for (int i < count)
			output.Append(text);
		return output;
	}
}
