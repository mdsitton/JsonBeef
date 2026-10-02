using System;
using System.Collections;
using System.IO;
using JsonBeef;

namespace JsonTester;

/// Differential fuzzing (`JsonTester -fuzz SEED ROUNDS FILE...`): each file is mutated ROUNDS times
/// (bytes replaced, inserted, deleted or duplicated, biased toward JSON's structural characters,
/// escapes, digits and UTF-8 lead bytes), and every mutation is read three ways: JsonDocument from
/// memory (the fast build, with the reader's report on failure), JsonReader's tokens from memory, and a
/// JsonDocument built through 1-byte stream reads (the reader's builder). All three must agree: the same
/// canonical form when accepted, the same error kind, line, column and offset when rejected. So must
/// collect-errors from memory and from a stream, and SkipValue from memory (its fast loop) and from a
/// stream (the token loop), skipping the whole value or the first one inside it. Prints the number of
/// runs and disagreements (with the input of the first ones) and exits 1 on any.
static class Fuzz
{
	const String cInteresting = "{}[],:\"\\/-+.0123456789eEtrufalsn \t\r\nbx\u{E9}";

	public static int Run(String[] args)
	{
		int seed = 0;
		int rounds = 0;
		if (args.Count < 4 || !(int.Parse(args[1]) case .Ok(out seed)) || !(int.Parse(args[2]) case .Ok(out rounds)))
		{
			Console.Error.WriteLine("usage: JsonTester -fuzz SEED ROUNDS FILE...");
			return 2;
		}
		let random = scope Random(seed);
		int runs = 0;
		int disagreements = 0;
		let data = scope List<uint8>();
		let mutated = scope String();
		for (int f = 3; f < args.Count; f++)
		{
			data.Clear();
			if (File.ReadAll(args[f], data) case .Err)
				continue;
			for (int round < rounds)
			{
				mutated.Clear();
				mutated.Append((char8*)data.Ptr, data.Count);
				int edits = 1 + random.Next(0, 4);
				for (int e < edits)
					Mutate(mutated, random);
				runs++;
				if (!Agree(mutated))
				{
					disagreements++;
					if (disagreements <= 5)
					{
						Console.WriteLine($"disagreement on a mutation of {args[f]} (round {round}):");
						Console.WriteLine(scope String()..Append(mutated, 0, Math.Min(mutated.Length, 300)));
					}
				}
			}
		}
		Console.WriteLine($"fuzz: {runs} runs, {disagreements} disagreements");
		return disagreements == 0 ? 0 : 1;
	}

	static void Mutate(String text, Random random)
	{
		int pos = text.IsEmpty ? 0 : random.Next(0, text.Length);
		char8 c;
		switch (random.Next(0, 5))
		{
		case 0: c = cInteresting[random.Next(0, cInteresting.Length)];
		case 1: c = (char8)random.Next(0, 256);
		case 2: c = (char8)(0xC0 + random.Next(0, 0x40));
		case 3: c = (char8)(0x80 + random.Next(0, 0x40));
		default: c = (char8)random.Next(0x20, 0x7F);
		}
		switch (random.Next(0, 4))
		{
		case 0:
			if (pos < text.Length)
				text[pos] = c;
		case 1:
			text.Insert(pos, c);
		case 2:
			if (pos < text.Length)
				text.Remove(pos, Math.Min(random.Next(1, 4), text.Length - pos));
		default:
			if (pos < text.Length)
			{
				int length = Math.Min(random.Next(1, 16), text.Length - pos);
				let copy = scope String(text, pos, length);
				text.Insert(Math.Min(pos + length, text.Length), copy);
			}
		}
	}

	/// The outcome of one way of reading: the canonical form, or the error.
	static void Outcome(Result<void, JsonParseError> result, JsonDocument doc, String output)
	{
		switch (result)
		{
		case .Ok:
			Canonical.Write(doc.Root, output);
		case .Err(let error):
			output.AppendF("error {} {}:{} @{}", error.mKind, error.mLine, error.mColumn, error.mOffset);
		}
	}

	static bool Agree(StringView text)
	{
		let document = scope JsonDocument();
		let a = scope String();
		Outcome(document.Read(text), document, a);

		let reader = scope JsonReader(text);
		let b = scope String();
		if (Canonical.Write(reader, b) case .Err(let error))
		{
			b.Clear();
			b.AppendF("error {} {}:{} @{}", error.mKind, error.mLine, error.mColumn, error.mOffset);
		}

		let stream = scope TrickleStream(scope FixedMemoryStream(Span<uint8>((uint8*)text.Ptr, text.Length)), 1);
		var config = JsonReadConfig();
		config.StreamBufferBytes = 16;
		let streamed = scope JsonDocument();
		let c = scope String();
		Outcome(streamed.Read(stream, config), streamed, c);

		// Collect-errors from memory and from 1-byte stream reads: the same errors (the first one the
		// error above) and the same document read around them
		var collectConfig = JsonReadConfig();
		collectConfig.CollectErrors = true;
		let collected = scope JsonDocument();
		let d = scope String();
		CollectOutcome(collected.Read(text, collectConfig), collected, d);
		let collectStream = scope TrickleStream(scope FixedMemoryStream(Span<uint8>((uint8*)text.Ptr, text.Length)), 1);
		collectConfig.StreamBufferBytes = 16;
		let collectedStream = scope JsonDocument();
		let e = scope String();
		CollectOutcome(collectedStream.Read(collectStream, collectConfig), collectedStream, e);
		bool firstAgrees = a.StartsWith("error") ? d.StartsWith(a) : d == a;

		// SkipValue (from memory its fast loop, from a stream the token loop) finds what reading finds:
		// the same first error, or the end of the document. Skipping the whole value, and skipping the
		// first value inside it.
		let expected = b.StartsWith("error") ? b : "ok";
		bool skipsAgree = true;
		for (int inside < 2)
		{
			let skipped = scope String();
			SkipOutcome(scope JsonReader(text), inside == 1, skipped);
			let skipStream = scope TrickleStream(scope FixedMemoryStream(Span<uint8>((uint8*)text.Ptr, text.Length)), 1);
			let streamReader = scope JsonReader();
			streamReader.Reset(skipStream, config);
			let skippedStream = scope String();
			SkipOutcome(streamReader, inside == 1, skippedStream);
			if (skipped != expected || skippedStream != expected)
			{
				Console.WriteLine($"  skip{(inside == 1 ? " inside" : "")}: {skipped} / from a stream: {skippedStream}");
				skipsAgree = false;
			}
		}

		// The replacement modes (U+FFFD for ill-formed UTF-8, WTF-8 for lone surrogates): a document from
		// memory, from 1-byte stream reads and the reader's tokens agree too
		var lenient = JsonReadConfig();
		lenient.InvalidUtf8 = .Replace;
		lenient.InvalidSurrogates = .Wtf8;
		let lenientDoc = scope JsonDocument();
		let f = scope String();
		Outcome(lenientDoc.Read(text, lenient), lenientDoc, f);
		let lenientStream = scope TrickleStream(scope FixedMemoryStream(Span<uint8>((uint8*)text.Ptr, text.Length)), 1);
		var lenientStreamConfig = lenient;
		lenientStreamConfig.StreamBufferBytes = 16;
		let lenientStreamed = scope JsonDocument();
		let g = scope String();
		Outcome(lenientStreamed.Read(lenientStream, lenientStreamConfig), lenientStreamed, g);
		let lenientReader = scope JsonReader(text, lenient);
		let h = scope String();
		if (Canonical.Write(lenientReader, h) case .Err(let lenientError))
		{
			h.Clear();
			h.AppendF("error {} {}:{} @{}", lenientError.mKind, lenientError.mLine, lenientError.mColumn, lenientError.mOffset);
		}
		bool lenientAgrees = f == g && g == h;
		if (!lenientAgrees)
			Console.WriteLine($"  replace/wtf8: document {f.Substring(0, Math.Min(f.Length, 200))} / stream {g.Substring(0, Math.Min(g.Length, 200))} / reader {h.Substring(0, Math.Min(h.Length, 200))}");

		if (a == b && b == c && d == e && firstAgrees && skipsAgree && lenientAgrees)
			return true;
		Console.WriteLine($"  document: {a.Substring(0, Math.Min(a.Length, 200))}");
		Console.WriteLine($"  reader:   {b.Substring(0, Math.Min(b.Length, 200))}");
		Console.WriteLine($"  stream:   {c.Substring(0, Math.Min(c.Length, 200))}");
		Console.WriteLine($"  collect:  {d.Substring(0, Math.Min(d.Length, 300))}");
		Console.WriteLine($"  collect stream: {e.Substring(0, Math.Min(e.Length, 300))}");
		return false;
	}

	/// Skips the document's value with SkipValue (`inside`: its first member's value or element, after
	/// reading into it), then reads to the end: "ok", or the error as Outcome writes it.
	static void SkipOutcome(JsonReader reader, bool inside, String output)
	{
		Result<void, JsonParseError> result = .Ok;
		if (inside)
		{
			if (reader.Next() case .Err(let first))
				result = .Err(first);
			else if (reader.TokenType == .StartObject || reader.TokenType == .StartArray)
			{
				if (reader.Next() case .Err(let second))
					result = .Err(second);
			}
		}
		if (result case .Ok)
			result = reader.SkipValue();
		while (result case .Ok)
		{
			switch (reader.Next())
			{
			case .Ok(let token):
				if (token == .EndOfDocument)
				{
					output.Append("ok");
					return;
				}
			case .Err(let error):
				result = .Err(error);
			}
		}
		if (result case .Err(let error))
			output.AppendF("error {} {}:{} @{}", error.mKind, error.mLine, error.mColumn, error.mOffset);
	}

	/// `JsonTester -stream-sweep FILE...`: every file read as a document from memory, then through streams
	/// fed 1 to 31 bytes per read with buffers of 16 to 46 bytes (yajl's test pattern): every read must
	/// give the memory read's outcome.
	public static int Sweep(String[] args)
	{
		int runs = 0;
		int disagreements = 0;
		let data = scope List<uint8>();
		for (int f = 1; f < args.Count; f++)
		{
			data.Clear();
			if (File.ReadAll(args[f], data) case .Err)
				continue;
			StringView text = .((char8*)data.Ptr, data.Count);
			let memory = scope JsonDocument();
			let expected = scope String();
			Outcome(memory.Read(text), memory, expected);
			for (int chunk = 1; chunk <= 31; chunk++)
			{
				let stream = scope TrickleStream(scope FixedMemoryStream(Span<uint8>((uint8*)text.Ptr, text.Length)), chunk);
				var config = JsonReadConfig();
				config.StreamBufferBytes = 15 + chunk;
				let streamed = scope JsonDocument();
				let actual = scope String();
				Outcome(streamed.Read(stream, config), streamed, actual);
				runs++;
				if (actual != expected)
				{
					disagreements++;
					if (disagreements <= 5)
						Console.WriteLine($"{args[f]}: {chunk}-byte reads give `{actual.Substring(0, Math.Min(actual.Length, 200))}`, memory `{expected.Substring(0, Math.Min(expected.Length, 200))}`");
				}
			}
		}
		Console.WriteLine($"stream sweep: {runs} runs, {disagreements} disagreements");
		return disagreements == 0 ? 0 : 1;
	}

	/// A collect-errors read's outcome: every error, then the canonical form of what was read.
	static void CollectOutcome(Result<void, JsonParseError> result, JsonDocument doc, String output)
	{
		for (let error in doc.Errors)
			output.AppendF("error {} {}:{} @{}\n", error.mKind, error.mLine, error.mColumn, error.mOffset);
		if (doc.Errors.IsEmpty && result case .Err(let fatal))
			output.AppendF("error {} {}:{} @{}\n", fatal.mKind, fatal.mLine, fatal.mColumn, fatal.mOffset);
		if (!doc.IsEmpty)
			Canonical.Write(doc.Root, output);
	}
}
