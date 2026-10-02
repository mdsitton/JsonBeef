using System;

namespace JsonBeef;

/// @brief Generates JSON reading and writing for a class or struct at compile time.
///
/// ```
/// [JsonObject(Naming = .CamelCase)]
/// class Server
/// {
/// 	public String HostName ~ delete _;                           // "hostName": "example.org"
/// 	public int32 Port = 8080;                                    // "port": 8080
/// 	public List<String> Tags ~ DeleteContainerAndItems!(_);      // "tags": ["a", "b"]
/// 	public Dictionary<String, int32> Limits ~ DeleteDictionaryAndKeys!(_);   // "limits": {"cpu": 2}
/// 	public Tls Tls ~ delete _;                                   // "tls": {...}
/// 	public double? Ratio;                                        // "ratio": 0.5 or null
/// }
/// ```
///
/// The type gets IJsonSerializable: JsonRead from a JsonReader (no document in between), JsonWrite to a
/// JsonWriter, and JsonWrite into a JsonNode (updating it in place). JsonSerializer reads and writes whole
/// texts, files, streams and document nodes. Its public instance fields are its members:
/// - scalars: bool, integers (range-checked; a fraction is not an integer), float and double (a number
///   beyond their range is an error, never an infinity), String, enums (their case names), converter
///   types (IJsonConverter);
/// - `T?` of a scalar or struct: `null` or the value;
/// - other [JsonObject] classes and structs: objects;
/// - List<T>: arrays; Dictionary<K, T> (K a String, integer or enum): objects keyed by K; nested to
///   any depth (`List<List<double>>`, `Dictionary<String, List<int>>`).
///
/// Names are the declared ones by default (see Naming, JsonName, JsonAlias). Any other field type stops
/// the build with an error naming the field; [JsonIgnore] leaves a field out.
///
/// Reading fills an existing object: a member that is absent leaves its field as it was (unless
/// [JsonRequired]); unknown members are skipped (checked as everything is) unless the type is Strict; a
/// member that appears twice is an error unless JsonReadConfig.DuplicateNames is FirstWins or LastWins.
/// `null` sets a String, object, List, Dictionary or `T?` field to null and is an error for the others.
/// A String, object, List or Dictionary field that is null when read gets a new instance, which the
/// object then owns (declare such fields with `~ delete _` or a container delete); an existing List or
/// Dictionary is emptied first, its items deleted.
///
/// Polymorphism: a base class with a Discriminator has its subclasses (the visible [JsonObject] ones)
/// read and written with that member first: `{"kind": "circle", "r": 2}`, each subclass named by its
/// TypeName. Reading from a JsonReader needs the discriminator to be the object's first member (JsonWrite
/// puts it there); reading a document node finds it anywhere.
[AttributeUsage(.Class | .Struct)]
public struct JsonObjectAttribute : Attribute, IComptimeTypeApply
{
	/// @brief How field names and enum case names become member names and strings ([JsonName] on a field
	/// overrides).
	public JsonNaming Naming;

	/// @brief Reading fails (located at its name) at a member no field maps.
	public bool Strict;

	/// @brief Writing leaves out members whose value is null (a String, object, List, Dictionary or `T?`
	/// field that is null; JsonWrite into a node removes them).
	public bool OmitNulls;

	/// @brief Enum fields are written and read as their integer values instead of their case names
	/// (reading accepts only the values of declared cases).
	public bool EnumsAsNumbers;

	/// @brief On a base class: the member that names each object's type (`"kind"`), whose value is the
	/// TypeName of one of the base's [JsonObject] subclasses. Subclasses inherit it.
	public String Discriminator;

	/// @brief This class's value of its base's Discriminator. Unset, the type's name through Naming.
	public String TypeName;

	/// @brief Also emit the generated code as text, `static StringView JsonGeneratedSource`, to read or
	/// print when debugging a mapping (the IDE shows emitted code too; the command line does not).
	public bool ShowGenerated;

	/// @brief Checks the type's fields and emits IJsonSerializable into it.
	/// @param type The type carrying the attribute.
	[Comptime]
	public void ApplyToType(Type type)
	{
		JsonSerializerCodeGen.Emit(type, this);
	}
}

/// @brief How [JsonObject] turns declared names into member names. Words split at case changes, keeping
/// acronyms together (`HTTPPort` is `http_port` in SnakeCase), and at underscores.
public enum JsonNaming
{
	/// @brief The name as written: `poolSize`, `PoolSize`, `pool_size` (the default).
	AsDeclared,
	/// @brief `poolSize`.
	CamelCase,
	/// @brief `PoolSize`.
	PascalCase,
	/// @brief `pool_size`.
	SnakeCase,
	/// @brief `pool-size`.
	KebabCase
}

/// @brief Maps a field to the member `name` instead of its own name.
[AttributeUsage(.Field)]
public struct JsonNameAttribute : Attribute
{
	/// @brief The member name.
	public String mName;

	/// @brief Use `name` for the field.
	/// @param name The member name (any text).
	public this(String name)
	{
		mName = name;
	}
}

/// @brief An older name, so documents written before a rename still read. Repeatable. Reading accepts
/// the current name and each alias (one member in all: two are a duplicate); writing uses the current
/// name, and JsonWrite into a node renames a member found under an alias.
[AttributeUsage(.Field)]
public struct JsonAliasAttribute : Attribute
{
	/// @brief The older name.
	public String mName;

	/// @brief Also accept `name`.
	/// @param name The older member name.
	public this(String name)
	{
		mName = name;
	}
}

/// @brief Leaves a field out of the generated reading and writing.
[AttributeUsage(.Field)]
public struct JsonIgnoreAttribute : Attribute
{
}

/// @brief Makes reading fail (located at the object) when the field's member is absent.
[AttributeUsage(.Field)]
public struct JsonRequiredAttribute : Attribute
{
}

/// @brief A type that reads itself from a JsonReader and writes itself to a JsonWriter or into a
/// JsonNode. [JsonObject] generates it; a type can also implement it by hand.
public interface IJsonSerializable
{
	/// @brief Fill this object's fields from the value the reader's current token starts (before the
	/// first token: the document's value), reading through its last token.
	/// @param reader The reader.
	/// @param allocator Where the objects the read creates (Strings, nested objects, Lists) come from,
	/// for example a `scope BumpAllocator`; null for the heap, and then this object owns them.
	/// @return .Ok, or the first error, located in the input, with the path of the value in error.
	Result<void, JsonParseError> JsonRead(JsonReader reader, ITypedAllocator allocator = null) mut;

	/// @brief Write this object as a JSON value.
	/// @param writer The writer; its errors are its own (see JsonWriter.Finish).
	void JsonWrite(JsonWriter writer);

	/// @brief Write this object into `node`, updating what is there: members set (a value that did not
	/// change is not touched), members no field maps kept, so a document read with PreserveStyle keeps
	/// its formatting and comments. Arrays are updated element by element by position (extra elements
	/// removed, new ones appended), dictionaries member by member by key (keys that are gone removed).
	/// @param node The node (made an object if it is not one).
	/// @return .Ok, or an error: a value JSON cannot hold (a NaN double, an enum value that is no case),
	/// a converter's.
	Result<void, JsonWriteError> JsonWrite(JsonNode node);
}

/// @brief Reads and writes one type `T` for [JsonObject] fields: types the serializer does not know, or
/// a custom form such as `"12px"` for a Length or `[x, y]` for a Point. Register it for every field of
/// type T with [JsonConverter(typeof(T))] on the converter, or use it for one field with
/// [JsonUseConverter(typeof(Converter))].
///
/// ```
/// [JsonConverter(typeof(Point))]
/// struct PointJson : IJsonConverter<Point>
/// {
/// 	public static Result<void, JsonParseError> Read(JsonReader reader, ref Point target)
/// 	{
/// 		// [x, y]
/// 		if (reader.TokenType != .StartArray)
/// 			return .Err(JsonBind.Mismatch(reader, "an array [x, y]"));
/// 		Try!(reader.Next());
/// 		target.X = Try!(reader.GetDouble());
/// 		Try!(reader.Next());
/// 		target.Y = Try!(reader.GetDouble());
/// 		if (Try!(reader.Next()) != .EndArray)
/// 			return .Err(JsonBind.Mismatch(reader, "the end of [x, y]"));
/// 		return .Ok;
/// 	}
///
/// 	public static void Write(Point value, JsonWriter writer)
/// 	{
/// 		writer.WriteStartArray();
/// 		writer.WriteNumber(value.X);
/// 		writer.WriteNumber(value.Y);
/// 		writer.WriteEndArray();
/// 	}
/// }
/// ```
public interface IJsonConverter<T>
{
	/// @brief Read the value the reader's current token starts into `target`, through its last token.
	/// @param reader The reader, at the value's first token.
	/// @param target The field or new list item to fill.
	/// @return .Ok, or an error (JsonBind.Mismatch and JsonBind.Invalid make located ones).
	static Result<void, JsonParseError> Read(JsonReader reader, ref T target);

	/// @brief Write `value` as one JSON value.
	/// @param value The value to write.
	/// @param writer Where it goes.
	static void Write(T value, JsonWriter writer);
}

/// @brief Registers the converter it is placed on (an IJsonConverter<T>) for every [JsonObject] field and
/// item of type `T`, in every project that can see the converter. At most one converter per type.
[AttributeUsage(.Struct | .Class)]
public struct JsonConverterAttribute : Attribute
{
	/// @brief The type the converter handles.
	public Type mTarget;

	/// @brief Register the converter for `target`.
	/// @param target The type the converter handles.
	public this(Type target)
	{
		mTarget = target;
	}
}

/// @brief Reads and writes one field with the given converter (an IJsonConverter<T> for the field's
/// type, or for its innermost item type in a List or Dictionary), ahead of any registered converter or
/// built-in handling.
[AttributeUsage(.Field)]
public struct JsonUseConverterAttribute : Attribute
{
	/// @brief The converter type.
	public Type mConverter;

	/// @brief Use `converter` for this field.
	/// @param converter The converter type.
	public this(Type converter)
	{
		mConverter = converter;
	}
}
