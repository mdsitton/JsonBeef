using System;
using System.Collections;
using System.Diagnostics;
using System.IO;
using JsonBeef;

namespace JsonTester;

/// Loops for profiling and instruction counts (bench/instructions.sh, `perf record`):
///
///   JsonTester -bench-loop <mode> <file> <iterations> [buffer=N]
///   JsonTester -bench <mode> <file> [seconds]       (rough MB/s; real figures come from bench/compare)
///
/// Modes: events (JsonReader over the text: every string decoded, every number converted to a
/// double), document (JsonDocument.Read, the document reused), stream (events from a Stream through
/// the default buffer, or buffer=N), write (the document written compact), pretty (written indented).
/// A .ndjson file is split into lines, each its own document.
static class Bench
{
	public static int Run(String[] args)
	{
		bool loop = args[0] == "-bench-loop";
		if (args.Count < 3)
		{
			Console.Error.WriteLine("usage: JsonTester -bench-loop <events|document|stream|write|pretty> <file> <iterations> [buffer=N]");
			Console.Error.WriteLine("       JsonTester -bench <mode> <file> [seconds]");
			return 2;
		}
		let mode = args[1];
		let path = args[2];
		int count = loop ? 1 : 3;
		if (args.Count >= 4 && int.Parse(args[3]) case .Ok(let parsed))
			count = parsed;
		var config = JsonReadConfig();
		for (int i = 4; i < args.Count; i++)
		{
			if (args[i].StartsWith("buffer=") && int.Parse(args[i].Substring(7)) case .Ok(let size))
				config.StreamBufferBytes = size;
		}
		let data = scope List<uint8>();
		if (File.ReadAll(path, data) case .Err)
		{
			Console.Error.WriteLine($"cannot read {path}");
			return 2;
		}
		let docs = scope List<StringView>();
		StringView all = .((char8*)data.Ptr, data.Count);
		if (path.EndsWith(".ndjson"))
		{
			for (let line in all.Split('\n'))
			{
				if (!line.IsEmpty)
					docs.Add(line);
			}
		}
		else
			docs.Add(all);

		let reader = scope JsonReader();
		let doc = scope JsonDocument();
		let output = scope String();
		double sink = 0;
		int checksum = 0;
		delegate bool() op;
		switch (mode)
		{
		case "events":
			op = scope:: [&] () =>
			{
				for (let text in docs)
				{
					reader.Reset(text, config);
					if (!Drain(reader, ref sink, ref checksum))
						return false;
				}
				return true;
			};
		case "stream":
			op = scope:: [&] () =>
			{
				for (let text in docs)
				{
					let stream = scope FixedMemoryStream(Span<uint8>((uint8*)text.Ptr, text.Length));
					reader.Reset(stream, config);
					if (!Drain(reader, ref sink, ref checksum))
						return false;
				}
				return true;
			};
		case "document":
			op = scope:: [&] () =>
			{
				for (let text in docs)
				{
					if (doc.Read(text, config) case .Err)
						return false;
					checksum += doc.NodeCount;
				}
				return true;
			};
		case "write", "pretty":
			if (docs.Count != 1 || doc.Read(docs[0], config) case .Err)
			{
				Console.Error.WriteLine("write: one valid document needed");
				return 1;
			}
			JsonWriteOptions options = mode == "write" ? .Compact : .Pretty;
			op = scope:: [&] () =>
			{
				output.Clear();
				if (doc.Write(output, options) case .Err)
					return false;
				checksum += output.Length;
				return true;
			};
		default:
			Console.Error.WriteLine($"unknown mode {mode}");
			return 2;
		}

		if (loop)
		{
			for (int i < count)
			{
				if (!op())
				{
					Console.Error.WriteLine("parse error");
					return 1;
				}
			}
			Console.WriteLine($"{checksum} {sink}");
			return 0;
		}
		// Rough timing: warm up 1 s, then the best of runs over `count` seconds
		let watch = scope Stopwatch(true);
		while (watch.Elapsed.TotalSeconds < 1)
			op();
		double best = double.MaxValue;
		watch.Restart();
		while (watch.Elapsed.TotalSeconds < count)
		{
			let start = watch.Elapsed.Ticks;
			op();
			best = Math.Min(best, (watch.Elapsed.Ticks - start) * 100.0);
		}
		double ms = best / 1e6;
		Console.WriteLine(scope String()..AppendF("{0}: {1:F3} ms, {2:F1} MB/s (best run; the machine's load is not accounted for)", mode, ms,
			data.Count / 1048576.0 / (ms / 1000.0)));
		return 0;
	}

	/// Every token: strings are decoded by the reader (their length is touched), numbers converted.
	static bool Drain(JsonReader reader, ref double sink, ref int checksum)
	{
		while (true)
		{
			switch (reader.Next())
			{
			case .Ok(let token):
				switch (token)
				{
				case .String, .PropertyName:
					checksum += reader.StringValue.Length;
				case .Number:
					if (reader.TryGetDouble(let value))
						sink += value;
				case .EndOfDocument:
					return true;
				default:
				}
			case .Err:
				return false;
			}
		}
	}
}
