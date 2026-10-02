namespace JsonBeef;

/// @brief The kind of a JSON value in a JsonDocument.
public enum JsonValueKind : uint8
{
	/// @brief `null`.
	Null,
	/// @brief `false`.
	False,
	/// @brief `true`.
	True,
	/// @brief A number (see JsonNumberKind for what it holds).
	Number,
	/// @brief A string.
	String,
	/// @brief An array: its elements are the node's children.
	Array,
	/// @brief An object: its members are the node's children, each with its name.
	Object
}
