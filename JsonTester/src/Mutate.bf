using System;
using System.Collections;
using JsonBeef;

namespace JsonTester;

/// `JsonTester -mutate SEED [dialect flags] FILE`: the file is read with PreserveStyle, edited at random
/// (values set, members renamed, values removed, added and inserted, containers replaced), and written
/// back by the preserving writer; that text must read back (in the same dialect) into exactly the
/// edited document (their canonical forms equal). Exit 1 on any difference, printing both.
static class Mutate
{
	public static int Run(StringView text, JsonReadConfig baseConfig, int seed, String output)
	{
		var config = baseConfig;
		config.MetadataMode = .PreserveStyle;
		let doc = scope JsonDocument();
		if (doc.Read(text, config) case .Err(let error))
		{
			Program.PrintError(error);
			return 1;
		}
		let random = scope Random(seed);
		int edits = 1 + random.Next(0, 8);
		let log = scope String();
		for (int i < edits)
			Edit(doc, random, log);
		if (doc.IsEmpty)
			return 0;
		let written = scope String();
		if (doc.Write(written) case .Err(let writeError))
		{
			Console.Error.WriteLine($"write error: {writeError.mMessage}");
			return 1;
		}
		let expected = scope String();
		Canonical.Write(doc.Root, expected);
		var plainConfig = baseConfig;
		plainConfig.MetadataMode = .None;
		let again = scope JsonDocument();
		let actual = scope String();
		if (again.Read(written, plainConfig) case .Err(let againError))
			actual.AppendF("error {}:{}: {}", againError.mLine, againError.mColumn, againError.mMessage);
		else
			Canonical.Write(again.Root, actual);
		if (actual != expected)
		{
			Console.Error.WriteLine($"edits: {log}");
			Console.Error.WriteLine($"written:\n{written}");
			Console.Error.WriteLine($"read back: {actual}");
			Console.Error.WriteLine($"expected:  {expected}");
			return 1;
		}
		output.Append(written);
		return 0;
	}

	/// One random edit of a random value.
	static void Edit(JsonDocument doc, Random random, String log)
	{
		if (doc.IsEmpty)
			return;
		let nodes = scope List<JsonNode>();
		Collect(doc.Root, nodes);
		let node = nodes[random.Next(0, nodes.Count)];
		bool container = node.IsArray || node.IsObject;
		switch (random.Next(0, 10))
		{
		case 0:
			log.AppendF("number@{} ", node.Id);
			node.SetNumber((int64)random.Next(-1000, 1000));
		case 1:
			log.AppendF("string@{} ", node.Id);
			node.SetString(random.Next(0, 2) == 0 ? "new \"text\"\n" : "é");
		case 2:
			log.AppendF("float@{} ", node.Id);
			node.SetNumber(random.Next(0, 1000) / 8.0);
		case 3:
			if (node.IsMember)
			{
				log.AppendF("rename@{} ", node.Id);
				node.Rename(random.Next(0, 2) == 0 ? "renamed" : "a/b");
			}
		case 4, 5:
			if (node != doc.Root)
			{
				log.AppendF("remove@{} ", node.Id);
				node.Remove();
			}
		case 6:
			if (container)
			{
				log.AppendF("add@{} ", node.Id);
				if (node.IsArray)
					node.Add().SetNumber((int64)random.Next(0, 100));
				else
					node.Add(scope $"k{random.Next(0, 100)}").SetString("added");
			}
		case 7:
			if (node != doc.Root)
			{
				log.AppendF("insert@{} ", node.Id);
				let inserted = node.IsMember ? (random.Next(0, 2) == 0 ? node.InsertBefore("before") : node.InsertAfter("after")) :
					(random.Next(0, 2) == 0 ? node.InsertBefore() : node.InsertAfter());
				inserted.SetBool(true);
			}
		case 8:
			log.AppendF("object@{} ", node.Id);
			let obj = node.SetObject();
			obj.Add("x").SetArray().Add().SetNull();
			obj.Add("y").SetNumber((int64)1);
		default:
			log.AppendF("null@{} ", node.Id);
			node.SetNull();
		}
	}

	static void Collect(JsonNode top, List<JsonNode> nodes)
	{
		JsonNode node = top;
		while (true)
		{
			nodes.Add(node);
			if ((node.IsArray || node.IsObject) && node.Count > 0)
			{
				node = node.FirstChild;
				continue;
			}
			while (true)
			{
				if (node == top)
					return;
				let next = node.Next;
				if (next.IsValid)
				{
					node = next;
					break;
				}
				node = node.Parent;
			}
		}
	}
}
