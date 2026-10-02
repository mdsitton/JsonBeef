using System;

namespace JsonBeef;

static class JsonSmokeTests
{
	[Test]
	public static void Workspace_Builds()
	{
		Test.Assert(JsonValueKind.Object != JsonValueKind.Array);
	}
}
