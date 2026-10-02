using System;
using System.Collections;
using System.IO;
using JsonBeef;

namespace JsonTester;

/// The number corpora in one process (docs/test-suites.md §3, §9.5).
///
/// -fxx: each line of nigeltao/parse-number-fxx-test-data is `f16 f32 f64 string`. The string goes
/// through JsonReader as a whole document: it must be accepted exactly when it matches the JSON number
/// grammar (checked here by an independent matcher), and then give the f64 bits (an overflow line:
/// TryGetDouble fails and ParseDouble gives +∞) and, parsed as a float, the f32 bits.
///
/// -es6: each line of the RFC 8785 number file is `hex-bits,text`. Writing the double in ECMAScript
/// layout must give the text; reading the text must give the bits back (except negative zero, written
/// `0`).
static class Numbers
{
	const int cMaxReported = 20;

	public static int Run(String[] args)
	{
		bool es6 = args[0] == "-es6";
		int every = 1;
		int limit = 0;
		let files = scope List<String>();
		for (int i = 1; i < args.Count; i++)
		{
			if (args[i] == "-every" && i + 1 < args.Count && int.Parse(args[i + 1]) case .Ok(let k))
			{
				every = Math.Max(k, 1);
				i++;
			}
			else if (args[i] == "-limit" && i + 1 < args.Count && int.Parse(args[i + 1]) case .Ok(let n))
			{
				limit = n;
				i++;
			}
			else
				files.Add(args[i]);
		}
		if (files.IsEmpty)
		{
			Console.Error.WriteLine("usage: JsonTester -fxx|-es6 [-every K] [-limit N] FILE...");
			return 2;
		}
		var stats = Stats();
		let reader = scope JsonReader();
		let data = scope List<uint8>();
		for (let path in files)
		{
			data.Clear();
			if (File.ReadAll(path, data) case .Err)
			{
				Console.Error.WriteLine($"error: cannot read {path}");
				return 2;
			}
			StringView text = .((char8*)data.Ptr, data.Count);
			int lineNumber = 0;
			for (var line in text.Split('\n'))
			{
				if (line.EndsWith('\r'))
					line.RemoveFromEnd(1);
				if (line.IsEmpty)
					continue;
				lineNumber++;
				if (limit > 0 && lineNumber > limit)
					break;
				if ((lineNumber - 1) % every != 0)
					continue;
				if (es6)
					CheckEs6(line, reader, ref stats);
				else
					CheckFxx(line, reader, ref stats);
			}
		}
		if (es6)
			Console.WriteLine($"es6: {stats.mChecked} lines checked (writes and reads), {stats.mMismatches} mismatches");
		else
			Console.WriteLine($"fxx: {stats.mChecked} lines checked, {stats.mMismatches} mismatches ({stats.mNumbers} numbers, {stats.mRejected} rejected as non-JSON, {stats.mOverflow} overflow)");
		return stats.mMismatches == 0 ? 0 : 1;
	}

	struct Stats
	{
		public int mChecked;
		public int mMismatches;
		public int mNumbers;
		public int mRejected;
		public int mOverflow;

		public void Mismatch(StringView what) mut
		{
			mMismatches++;
			if (mMismatches <= cMaxReported)
				Console.WriteLine(what);
		}
	}

	static void CheckFxx(StringView line, JsonReader reader, ref Stats stats)
	{
		stats.mChecked++;
		uint64 f32Bits = 0;
		uint64 f64Bits = 0;
		if (line.Length < 32 || !ParseHex(line.Substring(5, 8), out f32Bits) || !ParseHex(line.Substring(14, 16), out f64Bits))
		{
			stats.Mismatch(scope $"malformed line: {line}");
			return;
		}
		StringView number = line.Substring(31);
		bool grammar = IsJsonNumber(number);
		reader.Reset(number);
		bool accepted = false;
		if (reader.Next() case .Ok(let token) && token == .Number)
			accepted = reader.Next() case .Ok(let end) && end == .EndOfDocument;
		if (accepted != grammar)
		{
			stats.Mismatch(scope $"`{number}`: {(grammar ? "valid JSON but rejected" : "not JSON but accepted")}");
			return;
		}
		if (!accepted)
		{
			stats.mRejected++;
			return;
		}
		stats.mNumbers++;
		reader.Reset(number);
		reader.Next().IgnoreError();
		bool finite = reader.TryGetDouble(let value);
		bool expectFinite = (f64Bits & 0x7FF0000000000000UL) != 0x7FF0000000000000UL;
		if (!expectFinite)
			stats.mOverflow++;
		if (finite != expectFinite)
		{
			stats.Mismatch(scope $"`{number}`: TryGetDouble gave {finite}, expected {expectFinite}");
			return;
		}
		JsonNumber.ParseDouble(number, let parsed);
		if (JsonNumber.ToBits(parsed) != f64Bits || (finite && JsonNumber.ToBits(value) != f64Bits))
		{
			stats.Mismatch(scope $"`{number}`: f64 {JsonNumber.ToBits(parsed):X16}, expected {f64Bits:X16}");
			return;
		}
		JsonNumber.ParseFloat(number, let single);
		var single;
		uint32 singleBits = *(uint32*)&single;
		if (singleBits != (uint32)f32Bits)
			stats.Mismatch(scope $"`{number}`: f32 {singleBits:X8}, expected {f32Bits:X8}");
	}

	static void CheckEs6(StringView line, JsonReader reader, ref Stats stats)
	{
		stats.mChecked++;
		int comma = line.IndexOf(',');
		uint64 bits = 0;
		if (comma < 1 || !ParseHex(line.Substring(0, comma), out bits))
		{
			stats.Mismatch(scope $"malformed line: {line}");
			return;
		}
		StringView expected = line.Substring(comma + 1);
		double value = JsonNumber.FromBits(bits);
		let written = scope String();
		JsonNumber.AppendDouble(written, value, .EcmaScript);
		if (written != expected)
		{
			stats.Mismatch(scope $"{bits:X16}: wrote `{written}`, expected `{expected}`");
			return;
		}
		if (bits == 0x8000000000000000UL)
			return;
		reader.Reset(expected);
		double read = 0;
		bool ok = reader.Next() case .Ok(let token) && token == .Number && reader.TryGetDouble(out read);
		if (!ok || JsonNumber.ToBits(read) != bits)
			stats.Mismatch(scope $"`{expected}`: read back wrong, expected {bits:X16}");
	}

	static bool ParseHex(StringView text, out uint64 value)
	{
		value = 0;
		if (text.IsEmpty || text.Length > 16)
			return false;
		for (let c in text)
		{
			uint64 digit;
			if (c >= '0' && c <= '9')
				digit = (uint64)(c - '0');
			else if (c >= 'a' && c <= 'f')
				digit = (uint64)(c - 'a' + 10);
			else if (c >= 'A' && c <= 'F')
				digit = (uint64)(c - 'A' + 10);
			else
				return false;
			value = (value << 4) | digit;
		}
		return true;
	}

	/// RFC 8259's number production, matched independently of the reader.
	static bool IsJsonNumber(StringView s)
	{
		int i = 0;
		int n = s.Length;
		if (i < n && s[i] == '-')
			i++;
		if (i >= n)
			return false;
		if (s[i] == '0')
			i++;
		else if (s[i] >= '1' && s[i] <= '9')
		{
			while (i < n && s[i] >= '0' && s[i] <= '9')
				i++;
		}
		else
			return false;
		if (i < n && s[i] == '.')
		{
			i++;
			int start = i;
			while (i < n && s[i] >= '0' && s[i] <= '9')
				i++;
			if (i == start)
				return false;
		}
		if (i < n && (s[i] == 'e' || s[i] == 'E'))
		{
			i++;
			if (i < n && (s[i] == '+' || s[i] == '-'))
				i++;
			int start = i;
			while (i < n && s[i] >= '0' && s[i] <= '9')
				i++;
			if (i == start)
				return false;
		}
		return i == n;
	}
}
