using System;
using JsonBeef;

namespace Other;

/// A second user of JsonBeef in the fixture workspace: its presence is what made the generator's old
/// AlwaysVisible lookups miss the Fixtures project's converters and subclasses.
[JsonObject]
class OtherThing
{
	public int32 value;
}
