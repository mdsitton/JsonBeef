using System;
using System.Collections;
using System.IO;
using JsonBeef;

namespace JsonTester;

/// The test-suite CLI (docs/test-suites.md §9.1).
///
///   JsonTester [flags] FILE     parse FILE; print its canonical form (§9.2) and exit 0, or print the
///                               first error as `line:column: Kind: message` to stderr and exit 1
///   JsonTester -fxx FILE...     the parse-number-fxx corpus (one process, every line)
///   JsonTester -es6 FILE        the RFC 8785 number file: writes and reads
///
/// Flags: -events (read with JsonReader; the default until the document exists), -stream N (read the
/// file as a Stream in reads of N bytes, through an N-byte buffer, or the reader's minimum of 16),
/// -no-bom, -max-depth N, and for the batch modes -every K
/// (every K-th line) and -limit N (the first N lines). Usage errors exit 2.
class Program
{
	public static int Main(String[] args)
	{
		if (args.Count > 0 && (args[0] == "-fxx" || args[0] == "-es6"))
			return Numbers.Run(args);

		var config = JsonReadConfig();
		int streamBuffer = 0;
		String path = null;
		for (int i < args.Count)
		{
			let arg = args[i];
			if (arg == "-events" || arg == "-canonical")
			{
			}
			else if (arg == "-stream" && i + 1 < args.Count && int.Parse(args[i + 1]) case .Ok(let size))
			{
				streamBuffer = Math.Max(size, 1);
				i++;
			}
			else if (arg == "-no-bom")
				config.AllowBom = false;
			else if (arg == "-max-depth" && i + 1 < args.Count && int.Parse(args[i + 1]) case .Ok(let depth))
			{
				config.MaxDepth = depth;
				i++;
			}
			else if (!arg.StartsWith("-") && path == null)
				path = arg;
			else
				return Usage(scope $"unknown argument `{arg}`");
		}
		if (path == null)
			return Usage("no input file");

		let reader = scope JsonReader();
		let input = scope List<uint8>();
		FileStream file = null;
		TrickleStream stream = null;
		defer { delete stream; delete file; }
		if (streamBuffer > 0)
		{
			// N-byte reads into an N-byte buffer (raised to the reader's minimum): every refill boundary
			file = new FileStream();
			if (file.Open(path, .Read, .Read) case .Err)
			{
				Console.Error.WriteLine($"error: cannot open {path}");
				return 2;
			}
			stream = new TrickleStream(file, streamBuffer);
			config.StreamBufferBytes = streamBuffer;
			reader.Reset(stream, config);
		}
		else
		{
			if (File.ReadAll(path, input) case .Err)
			{
				Console.Error.WriteLine($"error: cannot read {path}");
				return 2;
			}
			reader.Reset(StringView((char8*)input.Ptr, input.Count), config);
		}

		let output = scope String();
		if (Canonical.Write(reader, output) case .Err(let error))
		{
			PrintError(error);
			return 1;
		}
		output.Append('\n');
		Console.Out.Write(output);
		Console.Out.Flush();
		return 0;
	}

	/// `line:column: Kind: message` on stderr.
	public static void PrintError(JsonParseError error)
	{
		let text = scope String();
		text.AppendF("{}:{}: {}: {}", error.mLine, error.mColumn, error.mKind, error.mMessage);
		Console.Error.WriteLine(text);
	}

	static int Usage(StringView message)
	{
		Console.Error.WriteLine($"JsonTester: {message}");
		Console.Error.WriteLine("usage: JsonTester [-events] [-stream N] [-no-bom] [-max-depth N] FILE");
		Console.Error.WriteLine("       JsonTester -fxx [-every K] FILE...");
		Console.Error.WriteLine("       JsonTester -es6 [-limit N] [-every K] FILE");
		return 2;
	}
}
