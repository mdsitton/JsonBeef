using System;
using System.Collections;
using System.Diagnostics;
using System.IO;

namespace JsonBeefBench;

/// Benchmarks JsonBeef and the existing Beef JSON libraries, built into one program (Release):
///
///   JsonBeefBench <variant> <input> <min-samples>
///
///   jsonbeef       - DOM: JsonBeef's JsonDocument.Read(StringView) (RFC 8259, every check on; the
///                    document copies the input once, strings without escapes are views of the copy,
///                    numbers converted to int64/uint64/double), one document read again for every
///                    run (it keeps its memory, as simdjson's parser is reused).
///   jsonbeef-stream - streaming: JsonBeef's JsonReader over the text: every token, every key and string
///                    decoded (the reader decodes escapes as it scans), every number converted to a
///                    double (TryGetDouble).
///   bjson          - DOM: M0n7y5/BJSON's Json.Deserialize(StringView) into its JsonValue tree (a
///                    Deserializer per call, as Json.Deserialize does; keys in its bump allocator),
///                    then Dispose. Defaults (duplicate keys: the last one wins).
///   bjson-stream   - streaming: BJSON's JsonReader driving a counting IHandler (its SAX contract:
///                    every key, string and number reported in document order, no tree) over a
///                    StringStream that references the text. Every string's length is added and
///                    every number converted to double.
///   bjson-typed    - typed: BJSON's [JsonObject] classes (Typed.bf) through
///                    Json.Deserialize<T>(StringView, obj), which builds the JsonValue tree first and
///                    then binds it; the object is deleted afterwards. twitter and citm_catalog;
///                    canada is n/a (exit 3: Lists of Lists are not expressible).
///   structureddata - DOM: Beef's built-in Beefy.utils.StructuredData (what the IDE and BeefBuild
///                    use for workspace files), LoadFromString into its tree (it copies the text and
///                    keeps unescaped strings as views into that copy), then deleted. It stores
///                    fractions as float (32-bit) and integers as int64, and detects JSON only when
///                    the text starts with '{' or with '[' followed by '{' or '"'.
///   einscott-json  - DOM: EinScott/json's Json.ReadJson into a JsonTree (bump-allocated, values
///                    are JsonElement enums; strings are views of the input unless unescaped), then
///                    deleted. Its own number parser builds doubles digit by digit.
///
/// A .ndjson input is split into lines before timing (each line its own String; one run parses
/// every line once). Prints the check line (see ../../reference.py) first, then the timing, under
/// the rule every harness in bench/compare uses (Measure).
class Program
{
	public struct Measurement
	{
		public double mMedianNs;
		public int mSamples;
		public bool mConverged;
	}

	/// Warm up for at least 1 s (at least one run), then time single runs until at least `minSamples`
	/// were taken and at least 60% lie within ±10% of their median, or 10 s / 1000 samples have passed.
	/// (From XmlBeef's bench/compare/beef.)
	public static Measurement Measure(int minSamples, delegate void() op)
	{
		let watch = scope Stopwatch(true);
		repeat
			op();
		while (watch.Elapsed.TotalSeconds < 1);

		let samples = scope List<double>();
		let sorted = scope List<double>();
		watch.Restart();
		while (true)
		{
			let t0 = watch.Elapsed.Ticks;
			op();
			samples.Add((watch.Elapsed.Ticks - t0) * 100.0); // TimeSpan ticks are 100 ns
			sorted.Clear();
			sorted.AddRange(samples);
			sorted.Sort(scope (a, b) => a <=> b);
			int n = sorted.Count;
			double median = (n % 2 == 1) ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
			if (n >= minSamples)
			{
				int within = 0;
				for (let s in samples)
				{
					if (s >= median * 0.9 && s <= median * 1.1)
						within++;
				}
				if (within >= 0.6 * n)
					return .() { mMedianNs = median, mSamples = n, mConverged = true };
			}
			if (n >= 1000 || watch.Elapsed.TotalSeconds >= 10)
				return .() { mMedianNs = median, mSamples = n, mConverged = false };
		}
	}

	/// The dom/stream check line (see ../../reference.py)
	public struct Check
	{
		public int mObjects, mArrays, mKeys, mStrings, mNumbers, mTrues, mFalses, mNulls, mChars;
		public uint64 mNumSum;

		public void Number(double d) mut
		{
			mNumbers++;
			mNumSum &+= Bits(d);
		}

		public void Print()
		{
			let hex = scope String();
			for (int shift = 60; shift >= 0; shift -= 4)
				hex.Append("0123456789abcdef"[(int)((mNumSum >> (uint64)shift) & 0xF)]);
			Console.WriteLine(scope $"check: {mObjects} {mArrays} {mKeys} {mStrings} {mNumbers} {mTrues} {mFalses} {mNulls} {mChars} {hex}");
			Console.Out.Flush();
		}
	}

	/// The bit pattern of a double, -0 counted as +0
	public static uint64 Bits(double d)
	{
		double v = d + 0.0;
		return *(uint64*)&v;
	}

	/// Code points in UTF-8 text
	public static int Chars(StringView s)
	{
		int n = 0;
		for (let c in s.RawChars)
		{
			if (((uint8)c & 0xC0) != 0x80)
				n++;
		}
		return n;
	}

	/// Set by a timed run that hit a parse error
	static bool failed;

	public static int Main(String[] args)
	{
		if (args.Count < 3)
		{
			Console.Error.WriteLine("usage: JsonBeefBench <jsonbeef|jsonbeef-stream|bjson|bjson-stream|bjson-typed|structureddata|einscott-json> <input> <min-samples>");
			return 2;
		}
		let variant = args[0];
		let path = args[1];
		let file = scope String();
		if (File.ReadAllText(path, file) case .Err)
		{
			Console.Error.WriteLine(scope $"cannot read {path}");
			return 2;
		}
		int total = 0;
		{
			// The file's size in bytes (ReadAllText would have dropped a BOM)
			let raw = scope List<uint8>();
			if (File.ReadAll(path, raw) case .Ok)
				total = raw.Count;
		}
		let docs = scope List<String>();
		defer { ClearAndDeleteItems!(docs); }
		if (path.EndsWith(".ndjson"))
		{
			for (let line in file.Split('\n'))
			{
				if (!line.IsEmpty)
					docs.Add(new String(line));
			}
		}
		else
			docs.Add(new String(file));
		int minSamples = int.Parse(args[2]) case .Ok(let v) ? v : 5;

		Check check = default;
		delegate void() op;
		switch (variant)
		{
		case "bjson":
			for (let d in docs)
			{
				if (!BJSONBench.Dom(d, &check))
					return 1;
			}
			op = scope:: () => { for (let d in docs) if (!BJSONBench.Dom(d, null)) failed = true; };
		case "jsonbeef":
			for (let d in docs)
			{
				if (!JsonBeefBench.Dom(d, &check))
					return 1;
			}
			op = scope:: () => { for (let d in docs) if (!JsonBeefBench.Dom(d, null)) failed = true; };
		case "jsonbeef-stream":
			for (let d in docs)
			{
				if (!JsonBeefBench.Stream(d, &check, true))
					return 1;
			}
			op = scope:: () => { Check c = default; for (let d in docs) if (!JsonBeefBench.Stream(d, &c, false)) failed = true; };
		case "bjson-stream":
			for (let d in docs)
			{
				if (!BJSONBench.Stream(d, &check, true))
					return 1;
			}
			op = scope:: () => { Check c = default; for (let d in docs) if (!BJSONBench.Stream(d, &c, false)) failed = true; };
		case "structureddata":
			for (let d in docs)
			{
				if (!StructuredDataBench.Dom(d, &check))
					return 1;
			}
			op = scope:: () => { for (let d in docs) if (!StructuredDataBench.Dom(d, null)) failed = true; };
		case "einscott-json":
			for (let d in docs)
			{
				if (!EinScottBench.Dom(d, &check))
					return 1;
			}
			op = scope:: () => { for (let d in docs) if (!EinScottBench.Dom(d, null)) failed = true; };
		case "bjson-typed":
			{
				let fileName = Path.GetFileName(path, .. scope String());
				if (fileName != "twitter.json" && fileName != "citm_catalog.json")
					return 3;
				let kind = fileName == "twitter.json" ? "twitter" : "citm_catalog";
				let text = docs[0];
				if (!Typed.Run(kind, text, true))
					return 1;
				Console.Out.Flush();
				op = scope:: () => { if (!Typed.Run(kind, text, false)) failed = true; };
			}
		default:
			Console.Error.WriteLine(scope $"unknown variant {variant}");
			return 2;
		}
		if (variant != "bjson-typed")
			check.Print();
		let m = Measure(minSamples, op);
		if (failed)
			return 1;
		double ms = m.mMedianNs / 1e6;
		Console.WriteLine(scope String()..AppendF("{0:F3} ms/op {1:F1} MB/s (n={2}, {3})", ms, total / 1048576.0 / (ms / 1000.0),
			m.mSamples, m.mConverged ? "converged" : "capped"));
		return 0;
	}
}
