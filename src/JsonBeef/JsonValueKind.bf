namespace JsonBeef;

/// @brief The kind of a JSON value. Placeholder public type until phase 1 (see docs/plan.md).
public enum JsonValueKind
{
	Null,
	False,
	True,
	Number,
	String,
	Array,
	Object
}
