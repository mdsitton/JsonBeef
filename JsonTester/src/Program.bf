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
/// Reading modes: -document (the default: build a JsonDocument, print from it), -events (print straight
/// from JsonReader's tokens), -stream N (read the file as a Stream in reads of N bytes, through an
/// N-byte buffer or the reader's minimum of 16; with either mode).
/// Output modes (from the document): -rewrite (write compact, read that back, print its canonical form;
/// exit 3 if the writer's output is rejected), -rewrite-pretty (the same, indented), -compact and
/// -pretty (print the writer's output as is), -jcs (RFC 8785), -pointer P (the canonical form of the
/// value at JSON Pointer P; a pointer error exits 1), -strings (every member name and string in order,
/// one per line), -echo (the document as Write(output) gives it: with -preserve, as it was read),
/// -mutate SEED (PreserveStyle, random edits, the preserving writer's output must read back into the
/// edited document; prints that output).
/// Metadata: -preserve (JsonMetadataMode.PreserveStyle).
/// Dialect: -comments, -trailing-commas, -jsonc (both).
/// Options: -no-bom, -max-depth N, -dup=keep|last|first|error, -collect (JsonReadConfig.CollectErrors:
/// every error is printed, the first one first, and the exit status is 1 if there was any); for the
/// batch modes -every K and -limit N.
/// Usage errors exit 2.
class Program
{
	enum Output
	{
		Canonical,
		Rewrite,
		RewritePretty,
		Compact,
		Pretty,
		Jcs,
		Pointer,
		Strings,
		Echo,
		Mutate
	}

	public static int Main(String[] args)
	{
		if (args.Count > 0 && (args[0] == "-fxx" || args[0] == "-es6"))
			return Numbers.Run(args);
		if (args.Count > 0 && (args[0] == "-bench" || args[0] == "-bench-loop"))
			return Bench.Run(args);
		if (args.Count > 0 && args[0] == "-fuzz")
			return Fuzz.Run(args);
		if (args.Count > 0 && args[0] == "-stream-sweep")
			return Fuzz.Sweep(args);

		var config = JsonReadConfig();
		int streamBuffer = 0;
		bool events = false;
		Output output = .Canonical;
		String pointer = null;
		int mutateSeed = 0;
		String path = null;
		for (int i < args.Count)
		{
			let arg = args[i];
			if (arg == "-events")
				events = true;
			else if (arg == "-document" || arg == "-canonical")
				events = false;
			else if (arg == "-stream" && i + 1 < args.Count && int.Parse(args[i + 1]) case .Ok(let size))
			{
				streamBuffer = Math.Max(size, 1);
				i++;
			}
			else if (arg == "-rewrite")
				output = .Rewrite;
			else if (arg == "-rewrite-pretty")
				output = .RewritePretty;
			else if (arg == "-compact")
				output = .Compact;
			else if (arg == "-pretty")
				output = .Pretty;
			else if (arg == "-jcs")
				output = .Jcs;
			else if (arg == "-strings")
				output = .Strings;
			else if (arg == "-preserve")
				config.MetadataMode = .PreserveStyle;
			else if (arg == "-echo")
				output = .Echo;
			else if (arg == "-mutate" && i + 1 < args.Count && int.Parse(args[i + 1]) case .Ok(let seed))
			{
				output = .Mutate;
				mutateSeed = seed;
				i++;
			}
			else if (arg == "-pointer" && i + 1 < args.Count)
			{
				output = .Pointer;
				pointer = args[++i];
			}
			else if (arg == "-no-bom")
				config.AllowBom = false;
			else if (arg == "-collect")
				config.CollectErrors = true;
			else if (arg == "-comments")
				config.Comments = true;
			else if (arg == "-trailing-commas")
				config.TrailingCommas = true;
			else if (arg == "-jsonc")
			{
				config.Comments = true;
				config.TrailingCommas = true;
			}
			else if (arg == "-max-depth" && i + 1 < args.Count && int.Parse(args[i + 1]) case .Ok(let depth))
			{
				config.MaxDepth = depth;
				i++;
			}
			else if (arg.StartsWith("-dup="))
			{
				switch (arg.Substring(5))
				{
				case "keep": config.DuplicateNames = .KeepAll;
				case "last": config.DuplicateNames = .LastWins;
				case "first": config.DuplicateNames = .FirstWins;
				case "error": config.DuplicateNames = .Error;
				default: return Usage(scope $"unknown duplicate policy `{arg}`");
				}
			}
			else if (!arg.StartsWith("-") && path == null)
				path = arg;
			else
				return Usage(scope $"unknown argument `{arg}`");
		}
		if (path == null)
			return Usage("no input file");
		if (events && output != .Canonical)
			return Usage("-events prints the canonical form only");

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
		}
		else if (File.ReadAll(path, input) case .Err)
		{
			Console.Error.WriteLine($"error: cannot read {path}");
			return 2;
		}
		StringView text = .((char8*)input.Ptr, input.Count);

		let result = scope String();
		if (events)
		{
			let reader = scope JsonReader();
			if (stream != null)
				reader.Reset(stream, config);
			else
				reader.Reset(text, config);
			let errors = scope String();
			if (Canonical.Write(reader, result, config.CollectErrors ? errors : null) case .Err(let readerError))
				return PrintError(readerError);
			if (!errors.IsEmpty)
			{
				Console.Error.Write(errors);
				return 1;
			}
			result.Append('\n');
			return Print(result);
		}

		if (output == .Mutate)
		{
			if (stream != null)
				return Usage("-mutate reads from memory");
			int status = Mutate.Run(text, config, mutateSeed, result);
			if (status != 0)
				return status;
			return Print(result);
		}

		let doc = scope JsonDocument();
		let read = stream != null ? doc.Read(stream, config) : doc.Read(text, config);
		if (!doc.Errors.IsEmpty)
		{
			// Collect-errors: every error, the first one first
			for (let error in doc.Errors)
				PrintError(error);
			return 1;
		}
		if (read case .Err(let readError))
			return PrintError(readError);

		switch (output)
		{
		case .Canonical:
			Canonical.Write(doc.Root, result);
			result.Append('\n');
		case .Rewrite, .RewritePretty:
			let written = scope String();
			if (doc.Write(written, output == .Rewrite ? .Compact : .Pretty) case .Err(let writeError))
			{
				Console.Error.WriteLine($"write error: {writeError.mKind}: {writeError.mMessage}");
				return 3;
			}
			let again = scope JsonDocument();
			if (again.Read(written, config) case .Err(let againError))
			{
				Console.Error.Write("the rewritten document is rejected: ");
				PrintError(againError);
				return 3;
			}
			Canonical.Write(again.Root, result);
			result.Append('\n');
		case .Compact, .Pretty, .Jcs:
			JsonWriteOptions options = output == .Compact ? .Compact : output == .Pretty ? .Pretty : .Jcs;
			if (doc.Write(result, options) case .Err(let writeError))
			{
				Console.Error.WriteLine($"write error: {writeError.mKind}: {writeError.mMessage}");
				return 1;
			}
		case .Pointer:
			switch (doc.Root.Find(pointer))
			{
			case .Ok(let node):
				Canonical.Write(node, result);
				result.Append('\n');
			case .Err(let pointerError):
				Console.Error.WriteLine($"pointer error: {pointerError}");
				return 1;
			}
		case .Strings:
			Canonical.WriteStrings(doc.Root, result);
		case .Echo:
			// The document written back with Write(output): with -preserve, as it was read
			if (doc.Write(result) case .Err(let writeError))
			{
				Console.Error.WriteLine($"write error: {writeError.mKind}: {writeError.mMessage}");
				return 1;
			}
		case .Mutate:
		}
		return Print(result);
	}

	static int Print(String text)
	{
		Console.Out.Write(text);
		Console.Out.Flush();
		return 0;
	}

	/// `line:column: Kind: message` on stderr; exit status 1.
	public static int PrintError(JsonParseError error)
	{
		let text = scope String();
		text.AppendF("{}:{}: {}: {}", error.mLine, error.mColumn, error.mKind, error.mMessage);
		Console.Error.WriteLine(text);
		return 1;
	}

	static int Usage(StringView message)
	{
		Console.Error.WriteLine($"JsonTester: {message}");
		Console.Error.WriteLine("usage: JsonTester [-document|-events] [-stream N] [output mode] [options] FILE");
		Console.Error.WriteLine("       output modes: -rewrite -rewrite-pretty -compact -pretty -jcs -pointer P -strings");
		Console.Error.WriteLine("       options: -no-bom -max-depth N -dup=keep|last|first|error");
		Console.Error.WriteLine("       JsonTester -fxx [-every K] FILE...");
		Console.Error.WriteLine("       JsonTester -es6 [-limit N] [-every K] FILE");
		return 2;
	}
}
